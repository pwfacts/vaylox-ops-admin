-- ============================================
-- POST-PAYROLL EXCEPTION RESOLUTION
-- Auto-resolve old exceptions after payroll lock
-- ============================================

-- Rule: Never delete records, only resolve with audit trail
-- Auto-resolution triggers when payroll status → LOCKED

-- ========================================
-- 1. ADD RESOLUTION METADATA COLUMNS
-- ========================================

ALTER TABLE attendance_exceptions
  ADD COLUMN IF NOT EXISTS resolution_source TEXT DEFAULT 'ADMIN' 
    CHECK (resolution_source IN ('ADMIN', 'SYSTEM_AUTO')),
  ADD COLUMN IF NOT EXISTS liability_role TEXT 
    CHECK (liability_role IN ('GUARD', 'SUPERVISOR', 'ADMIN', 'SYSTEM', NULL));

CREATE INDEX idx_attendance_exceptions_resolution_source ON attendance_exceptions(resolution_source);
CREATE INDEX idx_attendance_exceptions_liability_role ON attendance_exceptions(liability_role);

COMMENT ON COLUMN attendance_exceptions.resolution_source IS 
'ADMIN: Manual admin resolution, SYSTEM_AUTO: Automatic post-payroll resolution';

COMMENT ON COLUMN attendance_exceptions.liability_role IS 
'Tracks who is liable for the exception - used for accountability reporting';

-- ========================================
-- 2. AUTO-RESOLUTION FUNCTION
-- ========================================

CREATE OR REPLACE FUNCTION auto_resolve_post_payroll_exceptions(p_period_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_period payroll_periods;
  v_exception RECORD;
  v_resolved_count INTEGER := 0;
  v_approved_count INTEGER := 0;
  v_rejected_count INTEGER := 0;
  v_duplicate_attendances UUID[];
  v_earliest_attendance UUID;
BEGIN
  -- Get period
  SELECT * INTO v_period FROM payroll_periods WHERE id = p_period_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'PERIOD_NOT_FOUND');
  END IF;
  
  -- Must be LOCKED
  IF v_period.status != 'LOCKED' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'PERIOD_NOT_LOCKED',
      'current_status', v_period.status,
      'message', 'Auto-resolution only runs after payroll is LOCKED'
    );
  END IF;
  
  -- ========================================
  -- PROCESS EACH UNRESOLVED EXCEPTION
  -- ========================================
  
  FOR v_exception IN
    SELECT * FROM attendance_exceptions
    WHERE attempted_period_id = p_period_id
      AND resolution_status = 'PENDING'
    ORDER BY created_at
  LOOP
    -- ========================================
    -- RULE 1: PERIOD_FINALIZED, LATE_SYNC
    -- Auto-approve (guard worked, just late capture)
    -- ========================================
    
    IF v_exception.exception_type IN ('PERIOD_FINALIZED', 'LATE_SYNC') THEN
      -- Update attendance to RESOLVED
      UPDATE attendance
      SET 
        validation_status = 'RESOLVED',
        updated_at = NOW()
      WHERE id = v_exception.attendance_id;
      
      -- Update exception
      UPDATE attendance_exceptions
      SET
        resolution_status = 'RESOLVED',
        resolved_at = NOW(),
        resolved_by = NULL,  -- System resolution
        resolution_note = 'Auto-resolved after payroll lock - late capture accepted',
        resolution_source = 'SYSTEM_AUTO',
        liability_role = 'SYSTEM'  -- System liability (not individual)
      WHERE id = v_exception.id;
      
      v_resolved_count := v_resolved_count + 1;
      v_approved_count := v_approved_count + 1;
      
    -- ========================================
    -- RULE 2: DUPLICATE_ATTENDANCE
    -- Keep earliest, reject later
    -- ========================================
    
    ELSIF v_exception.exception_type = 'DUPLICATE_ATTENDANCE' THEN
      -- Find all attendance records for same guard/date
      SELECT array_agg(a.id ORDER BY a.created_at) INTO v_duplicate_attendances
      FROM attendance a
      WHERE a.guard_id = v_exception.guard_id
        AND a.attendance_date = v_exception.attendance_date
        AND a.payroll_period_id = p_period_id;
      
      -- Keep earliest (first in array)
      v_earliest_attendance := v_duplicate_attendances[1];
      
      IF v_exception.attendance_id = v_earliest_attendance THEN
        -- This is the earliest - APPROVE
        UPDATE attendance
        SET 
          validation_status = 'RESOLVED',
          updated_at = NOW()
        WHERE id = v_exception.attendance_id;
        
        UPDATE attendance_exceptions
        SET
          resolution_status = 'RESOLVED',
          resolved_at = NOW(),
          resolution_note = 'Auto-resolved: Kept earliest attendance record',
          resolution_source = 'SYSTEM_AUTO',
          liability_role = 'SYSTEM'
        WHERE id = v_exception.id;
        
        v_approved_count := v_approved_count + 1;
      ELSE
        -- This is duplicate - REJECT
        UPDATE attendance
        SET 
          validation_status = 'OPERATIONAL_ONLY',  -- Stay excluded
          updated_at = NOW()
        WHERE id = v_exception.attendance_id;
        
        UPDATE attendance_exceptions
        SET
          resolution_status = 'REJECTED',
          resolved_at = NOW(),
          resolution_note = 'Auto-resolved: Duplicate attendance - earlier record kept',
          resolution_source = 'SYSTEM_AUTO',
          liability_role = 'SUPERVISOR'  -- Supervisor created duplicate
        WHERE id = v_exception.id;
        
        v_rejected_count := v_rejected_count + 1;
      END IF;
      
      v_resolved_count := v_resolved_count + 1;
      
    -- ========================================
    -- RULE 3: OWNERSHIP_INVALID, REPLACED_SHIFT
    -- Approve with supervisor liability
    -- ========================================
    
    ELSIF v_exception.exception_type IN ('OWNERSHIP_INVALID', 'REPLACED_SHIFT') THEN
      -- Update attendance to RESOLVED
      UPDATE attendance
      SET 
        validation_status = 'RESOLVED',
        updated_at = NOW()
      WHERE id = v_exception.attendance_id;
      
      -- Update exception with supervisor liability
      UPDATE attendance_exceptions
      SET
        resolution_status = 'RESOLVED',
        resolved_at = NOW(),
        resolution_note = format('Auto-resolved after payroll lock - %s accepted with supervisor liability', 
          v_exception.exception_type),
        resolution_source = 'SYSTEM_AUTO',
        liability_role = 'SUPERVISOR'  -- Supervisor marked wrong guard
      WHERE id = v_exception.id;
      
      v_resolved_count := v_resolved_count + 1;
      v_approved_count := v_approved_count + 1;
      
    -- ========================================
    -- RULE 4: OTHER EXCEPTION TYPES
    -- Keep pending (require manual review)
    -- ========================================
    
    ELSE
      -- Don't auto-resolve unknown types
      -- Leave as PENDING for manual admin review
      CONTINUE;
    END IF;
  END LOOP;
  
  -- ========================================
  -- CREATE SUMMARY NOTIFICATION
  -- ========================================
  
  IF v_resolved_count > 0 THEN
    INSERT INTO notification_events (
      event_type,
      recipient_user_id,
      reference_id,
      reference_type,
      title,
      message,
      severity,
      metadata
    )
    SELECT
      'EXCEPTION_RESOLVED',
      u.id,
      p_period_id,
      'PAYROLL_PERIOD',
      'Post-Payroll Auto-Resolution Complete',
      format('%s exceptions auto-resolved after payroll lock (%s approved, %s rejected)',
        v_resolved_count, v_approved_count, v_rejected_count),
      'INFO',
      jsonb_build_object(
        'period_id', p_period_id,
        'resolved_count', v_resolved_count,
        'approved_count', v_approved_count,
        'rejected_count', v_rejected_count
      )
    FROM users u
    WHERE u.organization_id = v_period.organization_id
      AND u.role IN ('ADMIN', 'SUPER_ADMIN')
    LIMIT 1;
  END IF;
  
  RETURN jsonb_build_object(
    'success', true,
    'period_id', p_period_id,
    'resolved_count', v_resolved_count,
    'approved_count', v_approved_count,
    'rejected_count', v_rejected_count,
    'resolution_source', 'SYSTEM_AUTO'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION auto_resolve_post_payroll_exceptions IS 
'Auto-resolves exceptions after payroll lock based on exception type - maintains audit trail';

-- ========================================
-- 3. AUTO-TRIGGER ON PAYROLL LOCK
-- ========================================

CREATE OR REPLACE FUNCTION trigger_post_payroll_resolution()
RETURNS TRIGGER AS $$
BEGIN
  -- Only trigger when status changes to LOCKED
  IF NEW.status = 'LOCKED' AND (OLD.status IS NULL OR OLD.status != 'LOCKED') THEN
    -- Run auto-resolution asynchronously
    PERFORM auto_resolve_post_payroll_exceptions(NEW.id);
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auto_resolve_on_payroll_lock
  AFTER UPDATE ON payroll_periods
  FOR EACH ROW
  EXECUTE FUNCTION trigger_post_payroll_resolution();

COMMENT ON FUNCTION trigger_post_payroll_resolution IS 
'Triggers auto-resolution when payroll period status becomes LOCKED';

-- ========================================
-- 4. RESOLUTION AUDIT VIEW
-- ========================================

CREATE OR REPLACE VIEW exception_resolution_audit AS
SELECT 
  ae.id AS exception_id,
  ae.exception_type,
  ae.resolution_status,
  ae.resolution_source,
  ae.liability_role,
  
  -- Guard info
  g.full_name AS guard_name,
  g.id AS guard_id,
  
  -- Attendance info
  ae.attendance_date,
  a.validation_status AS attendance_validation_status,
  
  -- Period info
  pp.id AS period_id,
  pp.from_date AS period_from,
  pp.to_date AS period_to,
  pp.status AS period_status,
  
  -- Resolution details
  ae.resolved_at,
  u.email AS resolved_by_email,
  ae.resolution_note,
  
  -- Timestamps
  ae.created_at AS exception_created_at,
  EXTRACT(EPOCH FROM (ae.resolved_at - ae.created_at)) / 3600 AS hours_to_resolution
FROM attendance_exceptions ae
JOIN attendance a ON a.id = ae.attendance_id
JOIN guards g ON g.id = ae.guard_id
LEFT JOIN payroll_periods pp ON pp.id = ae.attempted_period_id
LEFT JOIN users u ON u.id = ae.resolved_by
WHERE ae.resolution_status != 'PENDING'
ORDER BY ae.resolved_at DESC;

COMMENT ON VIEW exception_resolution_audit IS 
'Audit trail for all resolved exceptions - tracks manual vs auto resolution';

-- ========================================
-- 5. LIABILITY REPORT VIEW
-- ========================================

CREATE OR REPLACE VIEW exception_liability_report AS
SELECT 
  pp.id AS period_id,
  pp.from_date,
  pp.to_date,
  o.name AS organization_name,
  
  -- Liability breakdown
  ae.liability_role,
  COUNT(*) AS exception_count,
  
  -- Exception types
  json_agg(DISTINCT ae.exception_type) AS exception_types,
  
  -- Resolution details
  COUNT(*) FILTER (WHERE ae.resolution_source = 'ADMIN') AS admin_resolved,
  COUNT(*) FILTER (WHERE ae.resolution_source = 'SYSTEM_AUTO') AS auto_resolved,
  COUNT(*) FILTER (WHERE ae.resolution_status = 'RESOLVED') AS approved,
  COUNT(*) FILTER (WHERE ae.resolution_status = 'REJECTED') AS rejected
FROM payroll_periods pp
JOIN organizations o ON o.id = pp.organization_id
JOIN attendance_exceptions ae ON ae.attempted_period_id = pp.id
WHERE ae.resolution_status != 'PENDING'
  AND ae.liability_role IS NOT NULL
GROUP BY pp.id, pp.from_date, pp.to_date, o.name, ae.liability_role
ORDER BY pp.from_date DESC, ae.liability_role;

COMMENT ON VIEW exception_liability_report IS 
'Liability breakdown per payroll period - tracks who is responsible for exceptions';

-- ========================================
-- 6. ENHANCED RESOLUTION FUNCTION
-- ========================================

-- Update manual resolution to include source tracking
CREATE OR REPLACE FUNCTION resolve_attendance_exception_v2(
  p_exception_id UUID,
  p_admin_user_id UUID,
  p_resolution_action TEXT,
  p_resolution_note TEXT,
  p_override_reason TEXT DEFAULT NULL,
  p_liability_role TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_exception attendance_exceptions;
  v_attendance attendance;
  v_admin_role TEXT;
BEGIN
  -- Get exception
  SELECT * INTO v_exception FROM attendance_exceptions WHERE id = p_exception_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'EXCEPTION_NOT_FOUND');
  END IF;
  
  IF v_exception.resolution_status != 'PENDING' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'ALREADY_RESOLVED',
      'current_status', v_exception.resolution_status
    );
  END IF;
  
  -- Verify admin role
  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_user_id;
  
  IF v_admin_role NOT IN ('ADMIN', 'SUPER_ADMIN') THEN
    RETURN jsonb_build_object('success', false, 'error', 'PERMISSION_DENIED');
  END IF;
  
  -- Get attendance
  SELECT * INTO v_attendance FROM attendance WHERE id = v_exception.attendance_id;
  
  -- ========================================
  -- RESOLUTION ACTIONS
  -- ========================================
  
  IF p_resolution_action = 'APPROVE' THEN
    UPDATE attendance
    SET validation_status = 'RESOLVED', updated_at = NOW()
    WHERE id = v_exception.attendance_id;
    
    UPDATE attendance_exceptions
    SET
      resolution_status = 'RESOLVED',
      resolved_at = NOW(),
      resolved_by = p_admin_user_id,
      resolution_note = p_resolution_note,
      resolution_source = 'ADMIN',  -- Manual admin resolution
      liability_role = COALESCE(p_liability_role, 'ADMIN')
    WHERE id = p_exception_id;
    
    RETURN jsonb_build_object('success', true, 'action', 'APPROVED', 'resolution_source', 'ADMIN');
    
  ELSIF p_resolution_action = 'REJECT' THEN
    UPDATE attendance
    SET validation_status = 'OPERATIONAL_ONLY', updated_at = NOW()
    WHERE id = v_exception.attendance_id;
    
    UPDATE attendance_exceptions
    SET
      resolution_status = 'REJECTED',
      resolved_at = NOW(),
      resolved_by = p_admin_user_id,
      resolution_note = p_resolution_note,
      resolution_source = 'ADMIN',
      liability_role = COALESCE(p_liability_role, 'ADMIN')
    WHERE id = p_exception_id;
    
    RETURN jsonb_build_object('success', true, 'action', 'REJECTED', 'resolution_source', 'ADMIN');
    
  ELSIF p_resolution_action = 'OVERRIDE' THEN
    IF p_override_reason IS NULL THEN
      RETURN jsonb_build_object('success', false, 'error', 'OVERRIDE_REASON_REQUIRED');
    END IF;
    
    UPDATE attendance
    SET validation_status = 'RESOLVED', updated_at = NOW()
    WHERE id = v_exception.attendance_id;
    
    UPDATE attendance_exceptions
    SET
      resolution_status = 'RESOLVED',
      resolved_at = NOW(),
      resolved_by = p_admin_user_id,
      resolution_note = p_resolution_note,
      override_applied = true,
      override_reason = p_override_reason,
      resolution_source = 'ADMIN',
      liability_role = COALESCE(p_liability_role, 'ADMIN')
    WHERE id = p_exception_id;
    
    RETURN jsonb_build_object('success', true, 'action', 'OVERRIDE_APPROVED', 'resolution_source', 'ADMIN');
    
  ELSE
    RETURN jsonb_build_object('success', false, 'error', 'INVALID_ACTION');
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION resolve_attendance_exception_v2 IS 
'Enhanced manual resolution with resolution_source and liability_role tracking';

-- ========================================
-- 7. POST-PAYROLL SUMMARY
-- ========================================

CREATE OR REPLACE FUNCTION get_post_payroll_resolution_summary(p_period_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_total_exceptions INTEGER;
  v_auto_resolved INTEGER;
  v_admin_resolved INTEGER;
  v_still_pending INTEGER;
  v_liability_breakdown JSONB;
BEGIN
  -- Count exceptions
  SELECT 
    COUNT(*),
    COUNT(*) FILTER (WHERE resolution_source = 'SYSTEM_AUTO'),
    COUNT(*) FILTER (WHERE resolution_source = 'ADMIN'),
    COUNT(*) FILTER (WHERE resolution_status = 'PENDING')
  INTO 
    v_total_exceptions,
    v_auto_resolved,
    v_admin_resolved,
    v_still_pending
  FROM attendance_exceptions
  WHERE attempted_period_id = p_period_id;
  
  -- Liability breakdown
  SELECT json_agg(
    json_build_object(
      'liability_role', liability_role,
      'count', count
    )
  )
  INTO v_liability_breakdown
  FROM (
    SELECT 
      liability_role,
      COUNT(*) AS count
    FROM attendance_exceptions
    WHERE attempted_period_id = p_period_id
      AND resolution_status != 'PENDING'
    GROUP BY liability_role
  ) sub;
  
  RETURN jsonb_build_object(
    'period_id', p_period_id,
    'total_exceptions', v_total_exceptions,
    'auto_resolved', v_auto_resolved,
    'admin_resolved', v_admin_resolved,
    'still_pending', v_still_pending,
    'liability_breakdown', v_liability_breakdown
  );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_post_payroll_resolution_summary IS 
'Summary of exception resolution after payroll lock';
