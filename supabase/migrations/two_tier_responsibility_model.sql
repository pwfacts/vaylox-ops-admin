-- ============================================
-- TWO-TIER RESPONSIBILITY MODEL
-- Supervisor = Presence Confirmation
-- Field Officer = Operational Validation
-- ============================================

-- CRITICAL: Existing approval_status system remains
-- This adds SECOND layer of validation for payroll

-- ========================================
-- 1. ADD OPERATIONAL STATUS TRACKING
-- ========================================

-- Add operational validation fields to attendance
ALTER TABLE attendance
  ADD COLUMN IF NOT EXISTS operational_status TEXT DEFAULT 'PENDING_VALIDATION' 
    CHECK (operational_status IN (
      'PENDING_VALIDATION',
      'PRESENT_CONFIRMED',
      'OPERATIONALLY_VALIDATED',
      'OPERATIONALLY_REJECTED'
    )),
  ADD COLUMN IF NOT EXISTS validated_by_field_officer_id UUID REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS validation_timestamp TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS validation_reason TEXT;

CREATE INDEX idx_attendance_operational_status ON attendance(operational_status);
CREATE INDEX idx_attendance_validated_by ON attendance(validated_by_field_officer_id);

COMMENT ON COLUMN attendance.operational_status IS 
'TWO-TIER MODEL: PENDING_VALIDATION → PRESENT_CONFIRMED (supervisor) → OPERATIONALLY_VALIDATED (FO) → payable';

COMMENT ON COLUMN attendance.validated_by_field_officer_id IS 
'Field Officer who performed operational validation (payroll authority)';

-- ========================================
-- 2. MODIFIED SUPERVISOR APPROVAL 
-- (Sets PRESENT_CONFIRMED, not final payroll decision)
-- ========================================

CREATE OR REPLACE FUNCTION supervisor_confirm_presence(
  p_attendance_id UUID,
  p_supervisor_user_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_attendance attendance;
  v_supervisor_role TEXT;
BEGIN
  -- Verify supervisor role
  SELECT role INTO v_supervisor_role FROM workforce_profiles WHERE linked_auth_user = p_supervisor_user_id LIMIT 1;
  
  IF v_supervisor_role NOT IN ('supervisor', 'site_supervisor', 'field_officer', 'admin', 'super_admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INSUFFICIENT_PERMISSIONS');
  END IF;
  
  -- Get attendance
  SELECT * INTO v_attendance FROM attendance WHERE id = p_attendance_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ATTENDANCE_NOT_FOUND');
  END IF;
  
  -- SUPERVISOR CONFIRMS PRESENCE ONLY (not payroll eligibility)
  UPDATE attendance
  SET
    approval_status = 'APPROVED',  -- Existing field (backward compatible)
    operational_status = 'PRESENT_CONFIRMED',  -- NEW: Presence confirmed, awaits FO validation
    approved_by = p_supervisor_user_id,
    approved_at = NOW()
  WHERE id = p_attendance_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'attendance_id', p_attendance_id,
    'approval_status', 'APPROVED',
    'operational_status', 'PRESENT_CONFIRMED',
    'approved_by', p_supervisor_user_id,
    'payroll_eligible', false,  -- NOT YET - needs FO validation
    'next_step', 'REQUIRES_FIELD_OFFICER_VALIDATION'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION supervisor_confirm_presence IS 
'PRESENCE CONFIRMATION: Supervisor confirms guard was present (not payroll decision)';

-- ========================================
-- 3. FIELD OFFICER OPERATIONAL VALIDATION
-- (Final payroll authority)
-- ========================================

CREATE OR REPLACE FUNCTION field_officer_validate_attendance(
  p_attendance_id UUID,
  p_field_officer_id UUID,
  p_validation_reason TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_attendance attendance;
  v_fo_role TEXT;
BEGIN
  -- Verify FO role
  SELECT role INTO v_fo_role FROM workforce_profiles WHERE linked_auth_user = p_field_officer_id LIMIT 1;
  
  IF v_fo_role NOT IN ('field_officer', 'admin', 'super_admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'REQUIRES_FIELD_OFFICER_ROLE');
  END IF;
  
  -- Get attendance
  SELECT * INTO v_attendance FROM attendance WHERE id = p_attendance_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ATTENDANCE_NOT_FOUND');
  END IF;
  
  -- FIELD OFFICER VALIDATES OPERATIONAL CORRECTNESS
  UPDATE attendance
  SET
    operational_status = 'OPERATIONALLY_VALIDATED',  -- PAYROLL ELIGIBLE
    validated_by_field_officer_id = p_field_officer_id,
    validation_timestamp = NOW(),
    validation_reason = p_validation_reason
  WHERE id = p_attendance_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'attendance_id', p_attendance_id,
    'operational_status', 'OPERATIONALLY_VALIDATED',
    'validated_by', p_field_officer_id,
    'payroll_eligible', true,  -- NOW PAYABLE
    'message', 'Attendance operationally validated - eligible for payroll'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION field_officer_validate_attendance IS 
'OPERATIONAL VALIDATION: FO validates correct assignment (payroll authority)';

-- Field Officer rejection
CREATE OR REPLACE FUNCTION field_officer_reject_attendance(
  p_attendance_id UUID,
  p_field_officer_id UUID,
  p_rejection_reason TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_fo_role TEXT;
BEGIN
  SELECT role INTO v_fo_role FROM workforce_profiles WHERE linked_auth_user = p_field_officer_id LIMIT 1;
  
  IF v_fo_role NOT IN ('field_officer', 'admin', 'super_admin') THEN
    RETURN jsonb_build_object('success', false, 'error', 'REQUIRES_FIELD_OFFICER_ROLE');
  END IF;
  
  -- Reject operationally (NOT PAYABLE)
  UPDATE attendance
  SET
    operational_status = 'OPERATIONALLY_REJECTED',
    validated_by_field_officer_id = p_field_officer_id,
    validation_timestamp = NOW(),
    validation_reason = p_rejection_reason
  WHERE id = p_attendance_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'attendance_id', p_attendance_id,
    'operational_status', 'OPERATIONALLY_REJECTED',
    'payroll_eligible', false,
    'message', 'Attendance rejected - not eligible for payroll'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION field_officer_reject_attendance IS 
'OPERATIONAL REJECTION: FO rejects incorrect assignment (excludes from payroll)';

-- ========================================
-- 4. MODIFIED AUTO-APPROVAL
-- (Sets PRESENT_CONFIRMED only, NOT OPERATIONALLY_VALIDATED)
-- ========================================

CREATE OR REPLACE FUNCTION auto_confirm_presence()
RETURNS JSONB AS $$
DECLARE
  v_auto_confirmed_count INTEGER;
BEGIN
  -- Auto-confirm PRESENCE after 24h (NOT operational validation)
  UPDATE attendance
  SET
    approval_status = 'APPROVED_AUTO',  -- Existing field
    operational_status = 'PRESENT_CONFIRMED',  -- Presence confirmed, NOT validated
    approved_at = NOW()
  WHERE approval_status = 'RECORDED'
    AND operational_status = 'PENDING_VALIDATION'
    AND created_at < NOW() - INTERVAL '24 hours';
  
  GET DIAGNOSTICS v_auto_confirmed_count = ROW_COUNT;
  
  RETURN jsonb_build_object(
    'success', true,
    'auto_confirmed_count', v_auto_confirmed_count,
    'note', 'Auto-confirmed PRESENCE only - still requires FO validation for payroll'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION auto_confirm_presence IS 
'AUTO-CONFIRMATION: Sets PRESENT_CONFIRMED after 24h (NOT OPERATIONALLY_VALIDATED)';

-- ========================================
-- 5. MODIFIED PAYROLL CALCULATION
-- (Counts OPERATIONALLY_VALIDATED only)
-- ========================================

CREATE OR REPLACE FUNCTION calculate_payroll_fo_validated(p_period_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_period payroll_periods;
  v_guard_id UUID;
  v_validated_count INTEGER;
  v_units_created INTEGER := 0;
  v_present_confirmed_not_validated INTEGER;
BEGIN
  SELECT * INTO v_period FROM payroll_periods WHERE id = p_period_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'PERIOD_NOT_FOUND');
  END IF;
  
  -- Count attendance needing FO validation
  SELECT COUNT(*) INTO v_present_confirmed_not_validated
  FROM attendance
  WHERE payroll_period_id = p_period_id
    AND operational_status = 'PRESENT_CONFIRMED'
    AND validated_by_field_officer_id IS NULL;
  
  -- ========================================
  -- PAYROLL RULE: COUNT OPERATIONALLY_VALIDATED ONLY
  -- ========================================
  
  FOR v_guard_id IN
    SELECT DISTINCT guard_id
    FROM attendance
    WHERE payroll_period_id = p_period_id
      AND operational_status = 'OPERATIONALLY_VALIDATED'
  LOOP
    -- Count validated attendance
    SELECT COUNT(*) INTO v_validated_count
    FROM attendance
    WHERE payroll_period_id = p_period_id
      AND guard_id = v_guard_id
      AND operational_status = 'OPERATIONALLY_VALIDATED';
    
    INSERT INTO payroll_work_units (
      payroll_period_id,
      guard_id,
      organization_id,
      present_days,
      aggregation_status
    )
    VALUES (
      p_period_id,
      v_guard_id,
      v_period.organization_id,
      v_validated_count,
      'DRAFT'
    )
    ON CONFLICT (payroll_period_id, guard_id)
    DO UPDATE SET
      present_days = EXCLUDED.present_days,
      updated_at = NOW();
    
    v_units_created := v_units_created + 1;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'work_units_created', v_units_created,
    'payroll_rule', 'COUNT(operational_status = OPERATIONALLY_VALIDATED)',
    'present_confirmed_requiring_fo_validation', v_present_confirmed_not_validated,
    'note', 'Payroll counts FO-validated attendance only'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION calculate_payroll_fo_validated IS 
'PAYROLL CALCULATION: Counts OPERATIONALLY_VALIDATED only (FO-approved)';

-- ========================================
-- 6. REPLACEMENT WORKFLOW INTEGRATION
-- ========================================

CREATE OR REPLACE FUNCTION transfer_shift_with_revalidation(
  p_shift_instance_id UUID,
  p_new_profile_id UUID,
  p_changed_by UUID,
  p_change_note TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_shift shift_instances;
  v_old_profile_id UUID;
BEGIN
  SELECT * INTO v_shift FROM shift_instances WHERE id = p_shift_instance_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'SHIFT_NOT_FOUND');
  END IF;
  
  v_old_profile_id := v_shift.current_owner_profile_id;
  
  -- Transfer shift ownership
  UPDATE shift_instances
  SET
    previous_owner_profile_id = v_old_profile_id,
    current_owner_profile_id = p_new_profile_id,
    updated_at = NOW()
  WHERE id = p_shift_instance_id;
  
  -- Old owner attendance: remains PRESENT_CONFIRMED but needs FO revalidation
  UPDATE attendance
  SET
    operational_status = 'PRESENT_CONFIRMED',  -- Presence confirmed, awaits FO decision
    warning_details = COALESCE(warning_details, '[]'::JSONB) || jsonb_build_object(
      'type', 'shift_ownership_changed',
      'message', 'Shift reassigned - requires FO validation',
      'requires_fo_validation', true
    )
  WHERE shift_instance_id = p_shift_instance_id
    AND guard_id = (SELECT linked_auth_user FROM workforce_profiles WHERE id = v_old_profile_id)
    AND operational_status IN ('PENDING_VALIDATION', 'PRESENT_CONFIRMED');
  
  -- NOTE: FO must validate which guard gets paid
  
  RETURN jsonb_build_object(
    'success', true,
    'old_owner_profile_id', v_old_profile_id,
    'new_owner_profile_id', p_new_profile_id,
    'note', 'Old guard attendance remains PRESENT_CONFIRMED - FO must validate for payroll',
    'requires_fo_action', true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION transfer_shift_with_revalidation IS 
'REPLACEMENT: Attendance stays PRESENT_CONFIRMED, requires FO validation for payroll';

-- ========================================
-- 7. FIELD OFFICER DASHBOARD
-- ========================================

CREATE OR REPLACE VIEW field_officer_pending_validation AS
SELECT 
  a.id AS attendance_id,
  a.attendance_date,
  a.check_in_time,
  a.check_out_time,
  a.approval_status,
  a.operational_status,
  
  -- Guard info
  g.full_name AS guard_name,
  g.employee_code,
  
  -- Shift info
  si.shift_date,
  u.name AS unit_name,
  
  -- Approval info
  sup.email AS supervisor_email,
  a.approved_at AS supervisor_approved_at,
  
  -- Warning flags
  a.warning_details,
  COALESCE(jsonb_array_length(a.warning_details), 0) AS warning_count,
  
  -- Organization
  o.id AS organization_id,
  o.name AS organization_name,
  
  -- Urgency
  CURRENT_DATE - a.attendance_date AS days_since_attendance
FROM attendance a
JOIN guards g ON g.id = a.guard_id
JOIN organizations o ON o.id = a.organization_id
LEFT JOIN shift_instances si ON si.id = a.shift_instance_id
LEFT JOIN units u ON u.id = si.unit_id
LEFT JOIN users sup ON sup.id = a.approved_by
WHERE a.operational_status = 'PRESENT_CONFIRMED'
  AND a.validated_by_field_officer_id IS NULL
ORDER BY a.attendance_date ASC, a.created_at ASC;

COMMENT ON VIEW field_officer_pending_validation IS 
'FO DASHBOARD: Attendance confirmed by supervisor, awaiting FO operational validation';

-- Field Officer work summary
CREATE OR REPLACE VIEW field_officer_validation_summary AS
SELECT 
  u.id AS field_officer_id,
  u.email AS field_officer_email,
  wp.organization_id,
  
  -- Pending counts
  COUNT(DISTINCT a.id) FILTER (
    WHERE a.operational_status = 'PRESENT_CONFIRMED'
      AND a.validated_by_field_officer_id IS NULL
  ) AS pending_validation_count,
  
  -- Validated counts (last 7 days)
  COUNT(DISTINCT a2.id) FILTER (
    WHERE a2.operational_status = 'OPERATIONALLY_VALIDATED'
      AND a2.validation_timestamp >= CURRENT_DATE - INTERVAL '7 days'
  ) AS validated_7_days,
  
  -- Rejected counts (last 7 days)
  COUNT(DISTINCT a3.id) FILTER (
    WHERE a3.operational_status = 'OPERATIONALLY_REJECTED'
      AND a3.validation_timestamp >= CURRENT_DATE - INTERVAL '7 days'
  ) AS rejected_7_days,
  
  -- Oldest pending
  MIN(a.attendance_date) FILTER (
    WHERE a.operational_status = 'PRESENT_CONFIRMED'
      AND a.validated_by_field_officer_id IS NULL
  ) AS oldest_pending_date
FROM workforce_profiles wp
JOIN users u ON u.id = wp.linked_auth_user
LEFT JOIN attendance a ON a.organization_id = wp.organization_id
LEFT JOIN attendance a2 ON a2.validated_by_field_officer_id = u.id
LEFT JOIN attendance a3 ON a3.validated_by_field_officer_id = u.id
WHERE wp.role IN ('field_officer', 'admin', 'super_admin')
GROUP BY u.id, u.email, wp.organization_id;

COMMENT ON VIEW field_officer_validation_summary IS 
'FO METRICS: Pending validation workload and activity summary';

-- ========================================
-- 8. BULK VALIDATION OPERATIONS
-- ========================================

CREATE OR REPLACE FUNCTION field_officer_bulk_validate(
  p_attendance_ids UUID[],
  p_field_officer_id UUID,
  p_validation_reason TEXT DEFAULT 'Bulk validation'
)
RETURNS JSONB AS $$
DECLARE
  v_validated_count INTEGER;
BEGIN
  UPDATE attendance
  SET
    operational_status = 'OPERATIONALLY_VALIDATED',
    validated_by_field_officer_id = p_field_officer_id,
    validation_timestamp = NOW(),
    validation_reason = p_validation_reason
  WHERE id = ANY(p_attendance_ids)
    AND operational_status = 'PRESENT_CONFIRMED';
  
  GET DIAGNOSTICS v_validated_count = ROW_COUNT;
  
  RETURN jsonb_build_object(
    'success', true,
    'validated_count', v_validated_count
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION field_officer_bulk_validate IS 
'BULK VALIDATION: FO validates multiple attendance records at once';

-- ========================================
-- 9. RESPONSIBILITY AUDIT TRAIL
-- ========================================

CREATE OR REPLACE VIEW responsibility_audit_trail AS
SELECT 
  a.id AS attendance_id,
  a.attendance_date,
  g.full_name AS guard_name,
  u.name AS unit_name,
  
  -- Responsibility chain
  sup.email AS supervisor_email,
  a.approved_at AS supervisor_confirmed_at,
  
  fo.email AS field_officer_email,
  a.validation_timestamp AS fo_validated_at,
  
  -- Status progression
  a.approval_status,
  a.operational_status,
  
  -- Payroll eligibility
  a.operational_status = 'OPERATIONALLY_VALIDATED' AS is_payable,
  
  -- Reasons
  a.rejection_reason AS supervisor_rejection_reason,
  a.validation_reason AS fo_validation_reason,
  
  -- Organization
  o.name AS organization_name
FROM attendance a
JOIN guards g ON g.id = a.guard_id
JOIN organizations o ON o.id = a.organization_id
LEFT JOIN shift_instances si ON si.id = a.shift_instance_id
LEFT JOIN units u ON u.id = si.unit_id
LEFT JOIN users sup ON sup.id = a.approved_by
LEFT JOIN users fo ON fo.id = a.validated_by_field_officer_id
ORDER BY a.attendance_date DESC, a.created_at DESC;

COMMENT ON VIEW responsibility_audit_trail IS 
'AUDIT: Shows responsibility chain (supervisor presence, FO validation)';

-- ========================================
-- 10. BACKWARD COMPATIBILITY WRAPPER
-- ========================================

-- Existing code calling supervisor_approve_attendance still works
CREATE OR REPLACE FUNCTION supervisor_approve_attendance(
  p_attendance_id UUID,
  p_supervisor_user_id UUID
)
RETURNS JSONB AS $$
BEGIN
  -- Calls new presence confirmation function
  RETURN supervisor_confirm_presence(p_attendance_id, p_supervisor_user_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION supervisor_approve_attendance IS 
'BACKWARD COMPATIBLE: Wraps supervisor_confirm_presence';
