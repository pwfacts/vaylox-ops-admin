-- ============================================
-- SUPERVISOR-DRIVEN RESPONSIBILITY MODEL REFACTOR
-- Changes: System audits silently, supervisor confirms
-- ============================================

-- Rule: Do NOT drop tables, columns, or redesign
-- Only change WHEN systems activate

-- ========================================
-- 1. ADD ATTENDANCE STATE TRACKING
-- ========================================

ALTER TABLE attendance ADD COLUMN IF NOT EXISTS supervisor_status TEXT 
  DEFAULT 'PENDING_SUPERVISOR_CONFIRMATION'
  CHECK (supervisor_status IN (
    'PENDING_SUPERVISOR_CONFIRMATION',
    'CONFIRMED',
    'DISPUTED'
  ));

ALTER TABLE attendance ADD COLUMN IF NOT EXISTS internal_review_flag BOOLEAN DEFAULT false;
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS supervisor_confirmed_by UUID REFERENCES users(id);
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS supervisor_confirmed_at TIMESTAMPTZ;
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS dispute_reason TEXT;

CREATE INDEX IF NOT EXISTS idx_attendance_supervisor_status ON attendance(supervisor_status);
CREATE INDEX IF NOT EXISTS idx_attendance_review_flag ON attendance(internal_review_flag) WHERE internal_review_flag = true;

COMMENT ON COLUMN attendance.supervisor_status IS 
'PENDING = awaiting confirmation, CONFIRMED = approved, DISPUTED = rejected (triggers investigation)';

COMMENT ON COLUMN attendance.internal_review_flag IS 
'Silent flag for low trust/issues - never blocks workflow, only for audit';

-- ========================================
-- 2. DISABLE AUTO-VERIFICATION TASK CREATION
-- ========================================

-- Drop old trigger that auto-creates tasks on trust score
DROP TRIGGER IF EXISTS trigger_auto_create_verification_task ON attendance;

-- Replace with trigger that ONLY sets internal_review_flag
CREATE OR REPLACE FUNCTION flag_attendance_for_internal_review()
RETURNS TRIGGER AS $$
BEGIN
  -- Only flag, never create tasks automatically
  IF NEW.trust_score IS NOT NULL AND NEW.trust_score < 60 THEN
    NEW.internal_review_flag := true;
  END IF;
  
  -- Silent flagging for:
  -- - time drift
  -- - offline excess
  -- - device mismatch
  -- - photo validation issues
  -- These DO NOT create verification tasks anymore
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_flag_attendance_for_review
  BEFORE INSERT OR UPDATE OF trust_score ON attendance
  FOR EACH ROW
  EXECUTE FUNCTION flag_attendance_for_internal_review();

COMMENT ON TRIGGER trigger_flag_attendance_for_review ON attendance IS 
'Silent flagging only - never creates tasks or blocks workflow';

-- ========================================
-- 3. SUPERVISOR CONFIRMATION FUNCTIONS
-- ========================================

-- Confirm attendance (supervisor accepts)
CREATE OR REPLACE FUNCTION confirm_attendance(
  p_attendance_id UUID,
  p_supervisor_id UUID,
  p_note TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_attendance attendance;
BEGIN
  SELECT * INTO v_attendance
  FROM attendance
  WHERE id = p_attendance_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ATTENDANCE_NOT_FOUND');
  END IF;
  
  IF v_attendance.supervisor_status != 'PENDING_SUPERVISOR_CONFIRMATION' THEN
    RETURN jsonb_build_object(
      'success', false, 
      'error', 'ALREADY_PROCESSED',
      'current_status', v_attendance.supervisor_status
    );
  END IF;
  
  UPDATE attendance
  SET 
    supervisor_status = 'CONFIRMED',
    supervisor_confirmed_by = p_supervisor_id,
    supervisor_confirmed_at = NOW()
  WHERE id = p_attendance_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'attendance_id', p_attendance_id,
    'status', 'CONFIRMED'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION confirm_attendance IS 
'Supervisor confirms attendance - no investigation needed';

-- Dispute attendance (supervisor rejects - NOW verification engine activates)
CREATE OR REPLACE FUNCTION dispute_attendance(
  p_attendance_id UUID,
  p_supervisor_id UUID,
  p_dispute_reason TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_attendance attendance;
  v_task_id UUID;
  v_required_role TEXT;
  v_reason_code TEXT;
BEGIN
  SELECT * INTO v_attendance
  FROM attendance
  WHERE id = p_attendance_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ATTENDANCE_NOT_FOUND');
  END IF;
  
  IF v_attendance.supervisor_status = 'DISPUTED' THEN
    RETURN jsonb_build_object('success', false, 'error', 'ALREADY_DISPUTED');
  END IF;
  
  IF p_dispute_reason IS NULL OR LENGTH(TRIM(p_dispute_reason)) < 10 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'DISPUTE_REASON_REQUIRED',
      'message', 'Dispute reason must be at least 10 characters'
    );
  END IF;
  
  -- Update attendance to DISPUTED
  UPDATE attendance
  SET 
    supervisor_status = 'DISPUTED',
    supervisor_confirmed_by = p_supervisor_id,
    supervisor_confirmed_at = NOW(),
    dispute_reason = p_dispute_reason
  WHERE id = p_attendance_id;
  
  -- NOW create verification task (only on dispute)
  IF v_attendance.trust_score < 40 THEN
    v_required_role := 'ADMIN';
    v_reason_code := 'SUPERVISOR_DISPUTED';
  ELSE
    v_required_role := 'FIELD_OFFICER';
    v_reason_code := 'SUPERVISOR_DISPUTED';
  END IF;
  
  INSERT INTO attendance_verification_tasks (
    attendance_id,
    organization_id,
    required_role,
    reason_code,
    trust_score,
    status
  )
  VALUES (
    p_attendance_id,
    v_attendance.organization_id,
    v_required_role,
    v_reason_code,
    v_attendance.trust_score,
    'PENDING'
  )
  RETURNING id INTO v_task_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'attendance_id', p_attendance_id,
    'status', 'DISPUTED',
    'verification_task_id', v_task_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION dispute_attendance IS 
'Supervisor disputes attendance - activates verification engine';

-- ========================================
-- 4. UPDATE PAYROLL CLOSURE RULES
-- ========================================

CREATE OR REPLACE FUNCTION can_close_payroll_period(
  p_org_id UUID,
  p_period_start DATE,
  p_period_end DATE
)
RETURNS JSONB AS $$
DECLARE
  v_disputed_count INTEGER;
  v_disputed_attendance JSONB;
BEGIN
  -- NEW RULE: Only DISPUTED attendance blocks payroll
  -- PENDING_SUPERVISOR_CONFIRMATION does NOT block
  
  SELECT COUNT(*) INTO v_disputed_count
  FROM attendance
  WHERE organization_id = p_org_id
    AND attendance_date >= p_period_start
    AND attendance_date <= p_period_end
    AND supervisor_status = 'DISPUTED';
  
  SELECT jsonb_agg(
    jsonb_build_object(
      'attendance_id', a.id,
      'guard_name', g.full_name,
      'attendance_date', a.attendance_date,
      'dispute_reason', a.dispute_reason,
      'confirmed_by', u.email
    )
  )
  INTO v_disputed_attendance
  FROM attendance a
  JOIN guards g ON g.id = a.guard_id
  LEFT JOIN users u ON u.id = a.supervisor_confirmed_by
  WHERE a.organization_id = p_org_id
    AND a.attendance_date >= p_period_start
    AND a.attendance_date <= p_period_end
    AND a.supervisor_status = 'DISPUTED'
  LIMIT 20;
  
  RETURN jsonb_build_object(
    'can_close', v_disputed_count = 0,
    'disputed_count', v_disputed_count,
    'disputed_attendance', COALESCE(v_disputed_attendance, '[]'::JSONB),
    'message', CASE
      WHEN v_disputed_count = 0 THEN 'Period can be closed'
      ELSE format('%s disputed attendance records must be resolved', v_disputed_count)
    END
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION can_close_payroll_period IS 
'NEW RULE: Only DISPUTED attendance blocks payroll, not pending confirmation';

-- ========================================
-- 5. DISPATCH ENGINE COMPATIBILITY
-- ========================================

-- Update dispatch view to treat PENDING and CONFIRMED as PRESENT
CREATE OR REPLACE VIEW dispatch_attendance_status AS
SELECT 
  a.id,
  a.guard_id,
  a.unit_id,
  a.attendance_date,
  a.shift,
  a.check_in_time,
  a.check_out_time,
  a.supervisor_status,
  a.trust_score,
  a.internal_review_flag,
  CASE 
    WHEN a.supervisor_status IN ('PENDING_SUPERVISOR_CONFIRMATION', 'CONFIRMED') THEN 'PRESENT'
    WHEN a.supervisor_status = 'DISPUTED' THEN 'ABSENT'
    ELSE 'PRESENT'
  END AS dispatch_status,
  CASE
    WHEN a.supervisor_status = 'PENDING_SUPERVISOR_CONFIRMATION' THEN 'Awaiting Supervisor Confirmation'
    WHEN a.supervisor_status = 'CONFIRMED' THEN 'Confirmed'
    WHEN a.supervisor_status = 'DISPUTED' THEN 'Needs Review'
  END AS friendly_status
FROM attendance a;

COMMENT ON VIEW dispatch_attendance_status IS 
'Dispatch treats PENDING and CONFIRMED as PRESENT, only DISPUTED as ABSENT';

-- ========================================
-- 6. UPDATE VERIFICATION SUMMARY
-- ========================================

CREATE OR REPLACE FUNCTION get_pending_verification_summary(
  p_org_id UUID,
  p_period_start DATE DEFAULT NULL,
  p_period_end DATE DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_pending_confirmation INTEGER;
  v_disputed_count INTEGER;
  v_internal_review_count INTEGER;
BEGIN
  -- Count attendance awaiting supervisor confirmation
  SELECT COUNT(*) INTO v_pending_confirmation
  FROM attendance
  WHERE organization_id = p_org_id
    AND supervisor_status = 'PENDING_SUPERVISOR_CONFIRMATION'
    AND (p_period_start IS NULL OR attendance_date >= p_period_start)
    AND (p_period_end IS NULL OR attendance_date <= p_period_end);
  
  -- Count disputed (verification tasks active)
  SELECT COUNT(*) INTO v_disputed_count
  FROM attendance
  WHERE organization_id = p_org_id
    AND supervisor_status = 'DISPUTED'
    AND (p_period_start IS NULL OR attendance_date >= p_period_start)
    AND (p_period_end IS NULL OR attendance_date <= p_period_end);
  
  -- Count internal review flags (silent audit)
  SELECT COUNT(*) INTO v_internal_review_count
  FROM attendance
  WHERE organization_id = p_org_id
    AND internal_review_flag = true
    AND supervisor_status = 'PENDING_SUPERVISOR_CONFIRMATION'
    AND (p_period_start IS NULL OR attendance_date >= p_period_start)
    AND (p_period_end IS NULL OR attendance_date <= p_period_end);
  
  RETURN jsonb_build_object(
    'pending_confirmation', v_pending_confirmation,
    'disputed', v_disputed_count,
    'internal_review_flags', v_internal_review_count,
    'message', format('%s awaiting confirmation, %s disputed', v_pending_confirmation, v_disputed_count)
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION get_pending_verification_summary IS 
'NEW: Shows supervisor confirmation queue, not automatic verification queue';

-- ========================================
-- 7. BULK CONFIRMATION HELPER
-- ========================================

CREATE OR REPLACE FUNCTION bulk_confirm_attendance(
  p_attendance_ids UUID[],
  p_supervisor_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_confirmed_count INTEGER := 0;
  v_failed_count INTEGER := 0;
  v_attendance_id UUID;
BEGIN
  FOREACH v_attendance_id IN ARRAY p_attendance_ids
  LOOP
    UPDATE attendance
    SET 
      supervisor_status = 'CONFIRMED',
      supervisor_confirmed_by = p_supervisor_id,
      supervisor_confirmed_at = NOW()
    WHERE id = v_attendance_id
      AND supervisor_status = 'PENDING_SUPERVISOR_CONFIRMATION';
    
    IF FOUND THEN
      v_confirmed_count := v_confirmed_count + 1;
    ELSE
      v_failed_count := v_failed_count + 1;
    END IF;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'confirmed', v_confirmed_count,
    'failed', v_failed_count
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION bulk_confirm_attendance IS 
'Supervisor bulk confirms multiple attendance records';

-- ========================================
-- 8. UPDATE EXISTING ATTENDANCE TO NEW MODEL
-- ========================================

-- Migrate existing attendance to new state model
UPDATE attendance
SET supervisor_status = CASE
  WHEN status = 'approved' THEN 'CONFIRMED'
  WHEN status = 'rejected' THEN 'DISPUTED'
  ELSE 'PENDING_SUPERVISOR_CONFIRMATION'
END
WHERE supervisor_status IS NULL;

-- Flag existing low-trust for internal review
UPDATE attendance
SET internal_review_flag = true
WHERE trust_score IS NOT NULL 
  AND trust_score < 60
  AND supervisor_status = 'PENDING_SUPERVISOR_CONFIRMATION';
