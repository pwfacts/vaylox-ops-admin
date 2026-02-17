-- ============================================
-- ATTENDANCE VERIFICATION ENFORCEMENT LAYER
-- Forces accountability without blocking operations
-- ============================================

-- 1. AUTO-CREATE VERIFICATION TASKS
CREATE OR REPLACE FUNCTION auto_create_verification_task()
RETURNS TRIGGER AS $$
DECLARE
  v_required_role TEXT;
  v_reason_code TEXT;
BEGIN
  -- Only create task if trust score is low
  IF NEW.trust_score IS NULL OR NEW.trust_score >= 60 THEN
    RETURN NEW;
  END IF;
  
  -- Determine required role and reason code
  IF NEW.trust_score < 40 THEN
    v_required_role := 'ADMIN';
    v_reason_code := 'VERY_LOW_TRUST';
  ELSE
    v_required_role := 'SUPERVISOR';
    v_reason_code := 'LOW_TRUST';
  END IF;
  
  -- Check for specific flags
  IF NEW.trust_score_details IS NOT NULL THEN
    IF (NEW.trust_score_details->'flags')::TEXT LIKE '%TIME_DRIFT%' THEN
      v_reason_code := 'TIME_DRIFT';
    ELSIF (NEW.trust_score_details->'flags')::TEXT LIKE '%OFFLINE_PUNCH%' THEN
      v_reason_code := 'OFFLINE_EXCESS';
    END IF;
  END IF;
  
  -- Create verification task
  INSERT INTO attendance_verification_tasks (
    attendance_id,
    organization_id,
    required_role,
    reason_code,
    trust_score,
    verification_flags
  )
  VALUES (
    NEW.id,
    NEW.organization_id,
    v_required_role,
    v_reason_code,
    NEW.trust_score,
    CASE 
      WHEN NEW.trust_score_details IS NOT NULL 
      THEN (NEW.trust_score_details->'flags')::TEXT[]
      ELSE ARRAY[]::TEXT[]
    END
  )
  ON CONFLICT (attendance_id) DO NOTHING;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS trigger_auto_create_verification_task ON attendance;
CREATE TRIGGER trigger_auto_create_verification_task
  AFTER INSERT OR UPDATE OF trust_score ON attendance
  FOR EACH ROW
  EXECUTE FUNCTION auto_create_verification_task();

COMMENT ON TRIGGER trigger_auto_create_verification_task ON attendance IS 
'Automatically create verification task for low-trust attendance';

-- 2. RESOLVE VERIFICATION TASK
CREATE OR REPLACE FUNCTION resolve_verification_task(
  p_task_id UUID,
  p_action TEXT, -- 'VERIFIED', 'JUSTIFIED', 'REJECTED'
  p_note TEXT,
  p_resolved_by UUID
)
RETURNS JSONB AS $$
DECLARE
  v_task attendance_verification_tasks;
BEGIN
  -- Validate action
  IF p_action NOT IN ('VERIFIED', 'JUSTIFIED', 'REJECTED') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'INVALID_ACTION',
      'message', 'Action must be VERIFIED, JUSTIFIED, or REJECTED'
    );
  END IF;
  
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
      'error', 'TASK_ALREADY_RESOLVED',
      'current_status', v_task.status
    );
  END IF;
  
  -- Update task
  UPDATE attendance_verification_tasks
  SET 
    status = p_action,
    resolved_at = NOW(),
    resolved_by = p_resolved_by,
    resolution_note = p_note
  WHERE id = p_task_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'task_id', p_task_id,
    'action', p_action,
    'attendance_id', v_task.attendance_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION resolve_verification_task IS 
'Resolve verification task with VERIFIED, JUSTIFIED, or REJECTED';

-- 3. GET PENDING VERIFICATION SUMMARY
CREATE OR REPLACE FUNCTION get_pending_verification_summary(
  p_org_id UUID,
  p_period_start DATE DEFAULT NULL,
  p_period_end DATE DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_summary JSONB;
  v_pending_count INTEGER;
  v_critical_count INTEGER;
  v_aging_count INTEGER;
  v_by_reason JSONB;
BEGIN
  -- Count pending tasks
  SELECT COUNT(*) INTO v_pending_count
  FROM attendance_verification_tasks vt
  JOIN attendance a ON a.id = vt.attendance_id
  WHERE vt.organization_id = p_org_id
    AND vt.status = 'PENDING'
    AND (p_period_start IS NULL OR a.attendance_date >= p_period_start)
    AND (p_period_end IS NULL OR a.attendance_date <= p_period_end);
  
  -- Count critical (ADMIN required)
  SELECT COUNT(*) INTO v_critical_count
  FROM attendance_verification_tasks vt
  JOIN attendance a ON a.id = vt.attendance_id
  WHERE vt.organization_id = p_org_id
    AND vt.status = 'PENDING'
    AND vt.required_role = 'ADMIN'
    AND (p_period_start IS NULL OR a.attendance_date >= p_period_start)
    AND (p_period_end IS NULL OR a.attendance_date <= p_period_end);
  
  -- Count aging (> 3 days old)
  SELECT COUNT(*) INTO v_aging_count
  FROM attendance_verification_tasks vt
  JOIN attendance a ON a.id = vt.attendance_id
  WHERE vt.organization_id = p_org_id
    AND vt.status = 'PENDING'
    AND vt.created_at < NOW() - INTERVAL '3 days'
    AND (p_period_start IS NULL OR a.attendance_date >= p_period_start)
    AND (p_period_end IS NULL OR a.attendance_date <= p_period_end);
  
  -- Group by reason code
  SELECT jsonb_object_agg(reason_code, count)
  INTO v_by_reason
  FROM (
    SELECT 
      vt.reason_code,
      COUNT(*)::INTEGER as count
    FROM attendance_verification_tasks vt
    JOIN attendance a ON a.id = vt.attendance_id
    WHERE vt.organization_id = p_org_id
      AND vt.status = 'PENDING'
      AND (p_period_start IS NULL OR a.attendance_date >= p_period_start)
      AND (p_period_end IS NULL OR a.attendance_date <= p_period_end)
    GROUP BY vt.reason_code
  ) counts;
  
  RETURN jsonb_build_object(
    'pending_reviews', v_pending_count,
    'critical_unverified', v_critical_count,
    'aging_tasks', v_aging_count,
    'by_reason', COALESCE(v_by_reason, '{}'::JSONB),
    'period_start', p_period_start,
    'period_end', p_period_end
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION get_pending_verification_summary IS 
'Get summary of pending verification tasks for dashboard counters';

-- 4. CHECK PERIOD CLOSURE ELIGIBILITY
CREATE OR REPLACE FUNCTION can_close_payroll_period(
  p_org_id UUID,
  p_period_start DATE,
  p_period_end DATE
)
RETURNS JSONB AS $$
DECLARE
  v_unresolved_count INTEGER;
  v_critical_count INTEGER;
  v_unresolved_tasks JSONB;
BEGIN
  -- Count unresolved tasks in period
  SELECT COUNT(*) INTO v_unresolved_count
  FROM attendance_verification_tasks vt
  JOIN attendance a ON a.id = vt.attendance_id
  WHERE vt.organization_id = p_org_id
    AND vt.status = 'PENDING'
    AND a.attendance_date >= p_period_start
    AND a.attendance_date <= p_period_end;
  
  -- Count critical unresolved
  SELECT COUNT(*) INTO v_critical_count
  FROM attendance_verification_tasks vt
  JOIN attendance a ON a.id = vt.attendance_id
  WHERE vt.organization_id = p_org_id
    AND vt.status = 'PENDING'
    AND vt.required_role = 'ADMIN'
    AND a.attendance_date >= p_period_start
    AND a.attendance_date <= p_period_end;
  
  -- Get list of unresolved tasks
  SELECT jsonb_agg(
    jsonb_build_object(
      'task_id', vt.id,
      'attendance_id', vt.attendance_id,
      'guard_name', g.full_name,
      'attendance_date', a.attendance_date,
      'trust_score', vt.trust_score,
      'reason_code', vt.reason_code,
      'required_role', vt.required_role,
      'days_pending', EXTRACT(DAY FROM NOW() - vt.created_at)::INTEGER
    )
  )
  INTO v_unresolved_tasks
  FROM attendance_verification_tasks vt
  JOIN attendance a ON a.id = vt.attendance_id
  JOIN guards g ON g.id = a.guard_id
  WHERE vt.organization_id = p_org_id
    AND vt.status = 'PENDING'
    AND a.attendance_date >= p_period_start
    AND a.attendance_date <= p_period_end
  ORDER BY vt.created_at ASC
  LIMIT 20;
  
  RETURN jsonb_build_object(
    'can_close', v_unresolved_count = 0,
    'unresolved_count', v_unresolved_count,
    'critical_count', v_critical_count,
    'unresolved_tasks', COALESCE(v_unresolved_tasks, '[]'::JSONB),
    'message', CASE
      WHEN v_unresolved_count = 0 THEN 'Period can be closed'
      WHEN v_critical_count > 0 THEN format('%s critical tasks require admin review', v_critical_count)
      ELSE format('%s tasks require supervisor review', v_unresolved_count)
    END
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION can_close_payroll_period IS 
'Check if payroll period can be closed - blocked if unresolved verification tasks exist';

-- 5. VIEW: VERIFICATION TASKS WITH DETAILS
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
  EXTRACT(DAY FROM NOW() - vt.created_at)::INTEGER AS days_pending,
  CASE 
    WHEN vt.status = 'PENDING' AND vt.created_at < NOW() - INTERVAL '7 days' THEN 'CRITICAL'
    WHEN vt.status = 'PENDING' AND vt.created_at < NOW() - INTERVAL '3 days' THEN 'WARNING'
    WHEN vt.status = 'PENDING' THEN 'NORMAL'
    ELSE NULL
  END AS urgency_level
FROM attendance_verification_tasks vt
JOIN attendance a ON a.id = vt.attendance_id
JOIN guards g ON g.id = a.guard_id
JOIN units u ON u.id = a.unit_id
LEFT JOIN users resolver ON resolver.id = vt.resolved_by;

COMMENT ON VIEW verification_tasks_with_details IS 
'Verification tasks with attendance and guard details for UI display';

-- 6. RLS POLICIES
-- Supervisors can view/resolve tasks for their organization
CREATE POLICY "Supervisors can manage verification tasks"
  ON attendance_verification_tasks FOR ALL
  USING (
    organization_id IN (
      SELECT organization_id FROM organization_users
      WHERE user_id = auth.uid()
        AND role IN ('supervisor', 'field_officer', 'admin', 'super_admin')
    )
  );

-- 7. UPDATE EXISTING LOW-TRUST ATTENDANCE
-- Create tasks for existing low-trust records
INSERT INTO attendance_verification_tasks (
  attendance_id,
  organization_id,
  required_role,
  reason_code,
  trust_score,
  verification_flags
)
SELECT 
  a.id,
  a.organization_id,
  CASE 
    WHEN a.trust_score < 40 THEN 'ADMIN'
    ELSE 'SUPERVISOR'
  END,
  CASE 
    WHEN a.trust_score < 40 THEN 'VERY_LOW_TRUST'
    ELSE 'LOW_TRUST'
  END,
  a.trust_score,
  COALESCE((a.trust_score_details->'flags')::TEXT[], ARRAY[]::TEXT[])
FROM attendance a
WHERE a.trust_score IS NOT NULL
  AND a.trust_score < 60
  AND a.created_at > NOW() - INTERVAL '90 days' -- Only recent records
  AND NOT EXISTS (
    SELECT 1 FROM attendance_verification_tasks vt
    WHERE vt.attendance_id = a.id
  )
ON CONFLICT (attendance_id) DO NOTHING;
