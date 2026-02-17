-- ============================================
-- VERIFICATION ENFORCEMENT: OWNERSHIP & ESCALATION
-- Extends existing system with automatic assignment and escalation
-- ============================================

-- 1. AUTO-ASSIGN TASK ON CREATION
CREATE OR REPLACE FUNCTION auto_assign_verification_task()
RETURNS TRIGGER AS $$
DECLARE
  v_attendance attendance;
  v_creator_role TEXT;
  v_responsible_user UUID;
  v_escalation_level TEXT;
BEGIN
  -- Get attendance record
  SELECT * INTO v_attendance
  FROM attendance a
  WHERE a.id = NEW.attendance_id;
  
  -- Determine who created the attendance (based on attendance_method or approval)
  -- Default: assign to unit supervisor
  
  -- Get unit supervisor
  SELECT wp.linked_auth_user INTO v_responsible_user
  FROM unit_assignments ua
  JOIN workforce_profiles wp ON wp.id = ua.profile_id
  WHERE ua.unit_id = v_attendance.unit_id
    AND ua.role = 'supervisor'
    AND ua.status = 'active'
  LIMIT 1;
  
  -- If no supervisor found, assign to field officer
  IF v_responsible_user IS NULL THEN
    SELECT wp.linked_auth_user INTO v_responsible_user
    FROM workforce_profiles wp
    JOIN organization_users ou ON ou.user_id = wp.linked_auth_user
    WHERE wp.organization_id = v_attendance.organization_id
      AND ou.role = 'field_officer'
    LIMIT 1;
  END IF;
  
  -- Set escalation level based on trust score
  IF NEW.trust_score < 40 THEN
    v_escalation_level := 'ADMIN';
  ELSIF NEW.trust_score < 50 THEN
    v_escalation_level := 'FIELD_OFFICER';
  ELSE
    v_escalation_level := 'SUPERVISOR';
  END IF;
  
  -- Set initial assignment
  NEW.responsible_user_id := v_responsible_user;
  NEW.escalation_level := v_escalation_level;
  NEW.first_assigned_at := NOW();
  NEW.due_at := NOW() + INTERVAL '24 hours';
  NEW.payroll_blocking := false;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Update trigger to include auto-assignment
DROP TRIGGER IF EXISTS trigger_auto_assign_verification_task ON attendance_verification_tasks;
CREATE TRIGGER trigger_auto_assign_verification_task
  BEFORE INSERT ON attendance_verification_tasks
  FOR EACH ROW
  EXECUTE FUNCTION auto_assign_verification_task();

-- 2. ESCALATION WORKER
CREATE OR REPLACE FUNCTION escalate_overdue_verification_tasks()
RETURNS JSONB AS $$
DECLARE
  v_escalated_count INTEGER := 0;
  v_blocked_count INTEGER := 0;
  v_task attendance_verification_tasks;
  v_new_responsible UUID;
BEGIN
  -- Process all pending tasks
  FOR v_task IN
    SELECT * FROM attendance_verification_tasks
    WHERE status = 'PENDING'
    ORDER BY created_at ASC
  LOOP
    -- 72 hours: mark as payroll blocking
    IF v_task.created_at < NOW() - INTERVAL '72 hours' AND v_task.payroll_blocking = false THEN
      UPDATE attendance_verification_tasks
      SET payroll_blocking = true
      WHERE id = v_task.id;
      v_blocked_count := v_blocked_count + 1;
    END IF;
    
    -- 48 hours: escalate to ADMIN
    IF v_task.created_at < NOW() - INTERVAL '48 hours' AND v_task.escalation_level != 'ADMIN' THEN
      -- Find admin
      SELECT wp.linked_auth_user INTO v_new_responsible
      FROM workforce_profiles wp
      JOIN organization_users ou ON ou.user_id = wp.linked_auth_user
      WHERE wp.organization_id = v_task.organization_id
        AND ou.role IN ('admin', 'super_admin')
      LIMIT 1;
      
      IF v_new_responsible IS NOT NULL THEN
        UPDATE attendance_verification_tasks
        SET 
          responsible_user_id = v_new_responsible,
          escalation_level = 'ADMIN',
          escalated_at = NOW(),
          due_at = NOW() + INTERVAL '24 hours'
        WHERE id = v_task.id;
        v_escalated_count := v_escalated_count + 1;
      END IF;
      
    -- 24 hours: escalate to FIELD_OFFICER
    ELSIF v_task.created_at < NOW() - INTERVAL '24 hours' AND v_task.escalation_level = 'SUPERVISOR' THEN
      -- Find field officer
      SELECT wp.linked_auth_user INTO v_new_responsible
      FROM workforce_profiles wp
      JOIN organization_users ou ON ou.user_id = wp.linked_auth_user
      WHERE wp.organization_id = v_task.organization_id
        AND ou.role = 'field_officer'
      LIMIT 1;
      
      IF v_new_responsible IS NOT NULL THEN
        UPDATE attendance_verification_tasks
        SET 
          responsible_user_id = v_new_responsible,
          escalation_level = 'FIELD_OFFICER',
          escalated_at = NOW(),
          due_at = NOW() + INTERVAL '24 hours'
        WHERE id = v_task.id;
        v_escalated_count := v_escalated_count + 1;
      END IF;
    END IF;
  END LOOP;
  
  RETURN jsonb_build_object(
    'escalated_count', v_escalated_count,
    'payroll_blocked_count', v_blocked_count,
    'processed_at', NOW()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION escalate_overdue_verification_tasks IS 
'Auto-escalate overdue tasks: 24h→Field Officer, 48h→Admin, 72h→Payroll Blocking';

-- 3. REASSIGN TASK
CREATE OR REPLACE FUNCTION reassign_verification_task(
  p_task_id UUID,
  p_new_owner_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_task attendance_verification_tasks;
BEGIN
  -- Get task
  SELECT * INTO v_task
  FROM attendance_verification_tasks
  WHERE id = p_task_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'TASK_NOT_FOUND'
    );
  END IF;
  
  -- Check if already resolved
  IF v_task.status != 'PENDING' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'TASK_ALREADY_RESOLVED'
    );
  END IF;
  
  -- Reassign
  UPDATE attendance_verification_tasks
  SET 
    responsible_user_id = p_new_owner_id,
    due_at = NOW() + INTERVAL '24 hours'
  WHERE id = p_task_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'task_id', p_task_id,
    'new_owner_id', p_new_owner_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION reassign_verification_task IS 
'Reassign verification task to a different user';

-- 4. DASHBOARD METRICS
CREATE OR REPLACE FUNCTION get_verification_metrics(
  p_org_id UUID,
  p_user_id UUID DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_tasks_by_owner JSONB;
  v_escalated_count INTEGER;
  v_overdue_count INTEGER;
  v_my_tasks_count INTEGER;
BEGIN
  -- Tasks by owner
  SELECT jsonb_object_agg(
    COALESCE(u.email, 'Unassigned'),
    count
  ) INTO v_tasks_by_owner
  FROM (
    SELECT 
      responsible_user_id,
      COUNT(*)::INTEGER as count
    FROM attendance_verification_tasks
    WHERE organization_id = p_org_id
      AND status = 'PENDING'
    GROUP BY responsible_user_id
  ) counts
  LEFT JOIN users u ON u.id = counts.responsible_user_id;
  
  -- Escalated tasks count
  SELECT COUNT(*) INTO v_escalated_count
  FROM attendance_verification_tasks
  WHERE organization_id = p_org_id
    AND status = 'PENDING'
    AND escalated_at IS NOT NULL;
  
  -- Overdue tasks (past due_at)
  SELECT COUNT(*) INTO v_overdue_count
  FROM attendance_verification_tasks
  WHERE organization_id = p_org_id
    AND status = 'PENDING'
    AND due_at < NOW();
  
  -- My tasks (if user_id provided)
  IF p_user_id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_my_tasks_count
    FROM attendance_verification_tasks
    WHERE organization_id = p_org_id
      AND status = 'PENDING'
      AND responsible_user_id = p_user_id;
  ELSE
    v_my_tasks_count := 0;
  END IF;
  
  RETURN jsonb_build_object(
    'tasks_by_owner', COALESCE(v_tasks_by_owner, '{}'::JSONB),
    'escalated_tasks', v_escalated_count,
    'overdue_tasks', v_overdue_count,
    'my_tasks', v_my_tasks_count
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION get_verification_metrics IS 
'Get verification task metrics: by owner, escalated, overdue';

-- 5. UPDATE PAYROLL CLOSURE CHECK
CREATE OR REPLACE FUNCTION can_close_payroll_period(
  p_org_id UUID,
  p_period_start DATE,
  p_period_end DATE
)
RETURNS JSONB AS $$
DECLARE
  v_blocking_count INTEGER;
  v_pending_count INTEGER;
  v_blocking_tasks JSONB;
BEGIN
  -- Count payroll-blocking tasks in period
  SELECT COUNT(*) INTO v_blocking_count
  FROM attendance_verification_tasks vt
  JOIN attendance a ON a.id = vt.attendance_id
  WHERE vt.organization_id = p_org_id
    AND vt.status = 'PENDING'
    AND vt.payroll_blocking = true
    AND a.attendance_date >= p_period_start
    AND a.attendance_date <= p_period_end;
  
  -- Count all pending (for info)
  SELECT COUNT(*) INTO v_pending_count
  FROM attendance_verification_tasks vt
  JOIN attendance a ON a.id = vt.attendance_id
  WHERE vt.organization_id = p_org_id
    AND vt.status = 'PENDING'
    AND a.attendance_date >= p_period_start
    AND a.attendance_date <= p_period_end;
  
  -- Get list of blocking tasks
  SELECT jsonb_agg(
    jsonb_build_object(
      'task_id', vt.id,
      'attendance_id', vt.attendance_id,
      'guard_name', g.full_name,
      'attendance_date', a.attendance_date,
      'trust_score', vt.trust_score,
      'responsible_user', u.email,
      'escalation_level', vt.escalation_level,
      'days_pending', EXTRACT(DAY FROM NOW() - vt.created_at)::INTEGER
    )
  )
  INTO v_blocking_tasks
  FROM attendance_verification_tasks vt
  JOIN attendance a ON a.id = vt.attendance_id
  JOIN guards g ON g.id = a.guard_id
  LEFT JOIN users u ON u.id = vt.responsible_user_id
  WHERE vt.organization_id = p_org_id
    AND vt.status = 'PENDING'
    AND vt.payroll_blocking = true
    AND a.attendance_date >= p_period_start
    AND a.attendance_date <= p_period_end
  ORDER BY vt.created_at ASC
  LIMIT 20;
  
  RETURN jsonb_build_object(
    'can_close', v_blocking_count = 0,
    'blocking_count', v_blocking_count,
    'pending_count', v_pending_count,
    'blocking_tasks', COALESCE(v_blocking_tasks, '[]'::JSONB),
    'message', CASE
      WHEN v_blocking_count = 0 AND v_pending_count = 0 THEN 'Period can be closed'
      WHEN v_blocking_count = 0 THEN format('%s pending tasks (non-blocking)', v_pending_count)
      ELSE format('%s critical tasks blocking payroll (>72h unresolved)', v_blocking_count)
    END
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION can_close_payroll_period IS 
'Check if payroll can close - ONLY blocks if payroll_blocking=true (72h+ unresolved)';

-- 6. UPDATE VIEW
CREATE OR REPLACE VIEW verification_tasks_with_details AS
SELECT 
  vt.*,
  a.attendance_date,
  a.shift,
  a.check_in_time,
  a.check_out_time,
  a.verification_mode,
  g.full_name AS guard_name,
  g.employee_code,
  u.name AS unit_name,
  resolver.email AS resolved_by_email,
  owner.email AS responsible_user_email,
  owner.full_name AS responsible_user_name,
  EXTRACT(DAY FROM NOW() - vt.created_at)::INTEGER AS days_pending,
  EXTRACT(HOUR FROM (vt.due_at - NOW()))::INTEGER AS hours_until_due,
  CASE 
    WHEN vt.payroll_blocking = true THEN 'PAYROLL_BLOCKING'
    WHEN vt.due_at < NOW() THEN 'OVERDUE'
    WHEN vt.escalated_at IS NOT NULL THEN 'ESCALATED'
    ELSE 'NORMAL'
  END AS urgency_level
FROM attendance_verification_tasks vt
JOIN attendance a ON a.id = vt.attendance_id
JOIN guards g ON g.id = a.guard_id
JOIN units u ON u.id = a.unit_id
LEFT JOIN users resolver ON resolver.id = vt.resolved_by
LEFT JOIN users owner ON owner.id = vt.responsible_user_id;

COMMENT ON VIEW verification_tasks_with_details IS 
'Verification tasks with ownership and escalation details';
