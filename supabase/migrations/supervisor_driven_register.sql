-- ============================================
-- SUPERVISOR-DRIVEN ATTENDANCE SYSTEM
-- Human supervisor decides payroll, not algorithms
-- ============================================

-- CORE PRINCIPLE:
-- RECORDED → APPROVED → PAYABLE
-- All validation = advisory signals only

-- ========================================
-- 1. MINIMAL SCHEMA ADDITIONS
-- ========================================

-- Add supervisor approval tracking to attendance
ALTER TABLE attendance
  ADD COLUMN IF NOT EXISTS approval_status TEXT DEFAULT 'RECORDED' 
    CHECK (approval_status IN ('RECORDED', 'APPROVED', 'APPROVED_AUTO', 'REJECTED')),
  ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

CREATE INDEX idx_attendance_approval_status ON attendance(approval_status);
CREATE INDEX idx_attendance_approved_by ON attendance(approved_by);

COMMENT ON COLUMN attendance.approval_status IS 
'SUPERVISOR DECISION: RECORDED (default), APPROVED (supervisor approved), APPROVED_AUTO (24h auto), REJECTED (supervisor rejected)';

COMMENT ON COLUMN attendance.approved_by IS 
'Supervisor who made approval/rejection decision';

-- ========================================
-- 2. ATTENDANCE STATE TRANSITIONS
-- ========================================

-- Punch time: Always RECORDED (never blocked)
CREATE OR REPLACE FUNCTION record_attendance(
  p_organization_id UUID,
  p_guard_id UUID,
  p_shift_instance_id UUID,
  p_attendance_date DATE,
  p_check_in_time TIMESTAMPTZ,
  p_check_out_time TIMESTAMPTZ,
  p_verification_mode TEXT,
  p_location_coords GEOGRAPHY,
  p_face_verified BOOLEAN,
  p_metadata JSONB
)
RETURNS JSONB AS $$
DECLARE
  v_attendance_id UUID;
  v_advisory_warnings JSONB := '[]'::JSONB;
  v_shift shift_instances;
  v_profile_id UUID;
BEGIN
  -- Get profile and shift (for advisory checks only)
  SELECT id INTO v_profile_id 
  FROM workforce_profiles 
  WHERE linked_auth_user = p_guard_id 
  LIMIT 1;
  
  IF p_shift_instance_id IS NOT NULL THEN
    SELECT * INTO v_shift FROM shift_instances WHERE id = p_shift_instance_id;
    
    -- ADVISORY CHECK 1: Ownership (does not block)
    IF v_shift IS NOT NULL AND v_shift.current_owner_profile_id != v_profile_id THEN
      v_advisory_warnings := v_advisory_warnings || jsonb_build_object(
        'type', 'ownership_mismatch',
        'message', 'Guard not current shift owner',
        'for_supervisor_review', true
      );
    END IF;
    
    -- ADVISORY CHECK 2: Date (does not block)
    IF v_shift IS NOT NULL AND p_attendance_date != v_shift.shift_date THEN
      v_advisory_warnings := v_advisory_warnings || jsonb_build_object(
        'type', 'date_mismatch',
        'message', format('Attendance %s != Shift %s', p_attendance_date, v_shift.shift_date),
        'for_supervisor_review', true
      );
    END IF;
  END IF;
  
  -- ALWAYS INSERT AS RECORDED
  INSERT INTO attendance (
    organization_id,
    guard_id,
    shift_instance_id,
    attendance_date,
    check_in_time,
    check_out_time,
    verification_mode,
    location_coords,
    face_verified,
    metadata,
    approval_status,  -- Always RECORDED
    warning_details   -- Advisory only
  )
  VALUES (
    p_organization_id,
    p_guard_id,
    p_shift_instance_id,
    p_attendance_date,
    p_check_in_time,
    p_check_out_time,
    p_verification_mode,
    p_location_coords,
    p_face_verified,
    p_metadata,
    'RECORDED',
    CASE WHEN jsonb_array_length(v_advisory_warnings) > 0 THEN v_advisory_warnings ELSE NULL END
  )
  ON CONFLICT (attendance_identity_key) 
  WHERE approval_status = 'RECORDED'
  DO UPDATE SET
    check_in_time = LEAST(EXCLUDED.check_in_time, attendance.check_in_time),
    updated_at = NOW()
  RETURNING id INTO v_attendance_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'attendance_id', v_attendance_id,
    'approval_status', 'RECORDED',
    'advisory_warnings', v_advisory_warnings,
    'awaiting_supervisor_approval', true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION record_attendance IS 
'CAPTURE LAYER: Always succeeds with RECORDED status. Warnings are advisory for supervisor only.';

-- ========================================
-- 3. SUPERVISOR APPROVAL ACTIONS
-- ========================================

CREATE OR REPLACE FUNCTION supervisor_approve_attendance(
  p_attendance_id UUID,
  p_supervisor_user_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_attendance attendance;
  v_supervisor_role TEXT;
BEGIN
  -- Verify supervisor role
  SELECT role INTO v_supervisor_role FROM users WHERE id = p_supervisor_user_id;
  
  IF v_supervisor_role NOT IN ('SUPERVISOR', 'SITE_SUPERVISOR', 'FIELD_OFFICER', 'ADMIN', 'SUPER_ADMIN') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INSUFFICIENT_PERMISSIONS');
  END IF;
  
  -- Get attendance
  SELECT * INTO v_attendance FROM attendance WHERE id = p_attendance_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ATTENDANCE_NOT_FOUND');
  END IF;
  
  -- SUPERVISOR DECISION OVERRIDES ALL
  UPDATE attendance
  SET
    approval_status = 'APPROVED',
    approved_by = p_supervisor_user_id,
    approved_at = NOW()
  WHERE id = p_attendance_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'attendance_id', p_attendance_id,
    'approval_status', 'APPROVED',
    'approved_by', p_supervisor_user_id,
    'payroll_eligible', true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION supervisor_approve_attendance IS 
'SUPERVISOR DECISION: Marks attendance APPROVED. This makes it payable regardless of warnings.';

CREATE OR REPLACE FUNCTION supervisor_reject_attendance(
  p_attendance_id UUID,
  p_supervisor_user_id UUID,
  p_rejection_reason TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_supervisor_role TEXT;
BEGIN
  SELECT role INTO v_supervisor_role FROM users WHERE id = p_supervisor_user_id;
  
  IF v_supervisor_role NOT IN ('SUPERVISOR', 'SITE_SUPERVISOR', 'FIELD_OFFICER', 'ADMIN', 'SUPER_ADMIN') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INSUFFICIENT_PERMISSIONS');
  END IF;
  
  UPDATE attendance
  SET
    approval_status = 'REJECTED',
    approved_by = p_supervisor_user_id,
    approved_at = NOW(),
    rejection_reason = p_rejection_reason
  WHERE id = p_attendance_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'attendance_id', p_attendance_id,
    'approval_status', 'REJECTED',
    'payroll_eligible', false
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION supervisor_reject_attendance IS 
'SUPERVISOR DECISION: Marks attendance REJECTED. This excludes it from payroll.';

CREATE OR REPLACE FUNCTION supervisor_bulk_approve(
  p_attendance_ids UUID[],
  p_supervisor_user_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_approved_count INTEGER;
BEGIN
  UPDATE attendance
  SET
    approval_status = 'APPROVED',
    approved_by = p_supervisor_user_id,
    approved_at = NOW()
  WHERE id = ANY(p_attendance_ids)
    AND approval_status = 'RECORDED';
  
  GET DIAGNOSTICS v_approved_count = ROW_COUNT;
  
  RETURN jsonb_build_object(
    'success', true,
    'approved_count', v_approved_count
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION supervisor_bulk_approve IS 
'SUPERVISOR BULK ACTION: Approve multiple attendance records at once';

-- ========================================
-- 4. AUTO-APPROVAL (24H FALLBACK)
-- ========================================

CREATE OR REPLACE FUNCTION auto_approve_attendance()
RETURNS JSONB AS $$
DECLARE
  v_auto_approved_count INTEGER;
BEGIN
  -- Auto-approve recorded attendance older than 24h
  UPDATE attendance
  SET
    approval_status = 'APPROVED_AUTO',
    approved_at = NOW()
  WHERE approval_status = 'RECORDED'
    AND created_at < NOW() - INTERVAL '24 hours';
  
  GET DIAGNOSTICS v_auto_approved_count = ROW_COUNT;
  
  RETURN jsonb_build_object(
    'success', true,
    'auto_approved_count', v_auto_approved_count
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION auto_approve_attendance IS 
'AUTO-APPROVAL: If supervisor does not act within 24h, attendance auto-approved for payroll';

-- Cron job for auto-approval (runs every 6 hours)
-- SELECT cron.schedule('auto-approve-attendance', '0 */6 * * *', $$SELECT auto_approve_attendance()$$);

-- ========================================
-- 5. SUPERVISOR REVIEW VIEWS
-- ========================================

CREATE OR REPLACE VIEW supervisor_daily_register AS
SELECT 
  a.id AS attendance_id,
  a.attendance_date,
  a.approval_status,
  a.check_in_time,
  a.check_out_time,
  
  -- Guard info
  g.full_name AS guard_name,
  g.id AS guard_id,
  
  -- Shift info
  si.shift_date,
  si.shift_start_time,
  u.name AS unit_name,
  
  -- Advisory warnings (for supervisor review)
  a.warning_details AS advisory_warnings,
  
  -- Approver info
  sup.email AS approved_by_email,
  a.approved_at,
  a.rejection_reason,
  
  -- Organization
  o.id AS organization_id,
  o.name AS organization_name
FROM attendance a
JOIN guards g ON g.id = a.guard_id
JOIN organizations o ON o.id = a.organization_id
LEFT JOIN shift_instances si ON si.id = a.shift_instance_id
LEFT JOIN units u ON u.id = si.unit_id
LEFT JOIN users sup ON sup.id = a.approved_by
ORDER BY a.attendance_date DESC, a.created_at DESC;

COMMENT ON VIEW supervisor_daily_register IS 
'SUPERVISOR REVIEW: Daily attendance with advisory warnings. Supervisor decides APPROVED/REJECTED.';

-- ========================================
-- 6. PAYROLL QUERY (SIMPLE - APPROVED ONLY)
-- ========================================

CREATE OR REPLACE FUNCTION calculate_payroll_simple(p_period_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_period payroll_periods;
  v_guard_id UUID;
  v_approved_count INTEGER;
  v_units_created INTEGER := 0;
BEGIN
  SELECT * INTO v_period FROM payroll_periods WHERE id = p_period_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'PERIOD_NOT_FOUND');
  END IF;
  
  -- ========================================
  -- PAYROLL RULE: COUNT APPROVED ONLY
  -- ========================================
  
  FOR v_guard_id IN
    SELECT DISTINCT guard_id
    FROM attendance
    WHERE payroll_period_id = p_period_id
      AND approval_status IN ('APPROVED', 'APPROVED_AUTO')
  LOOP
    -- Count approved shifts
    SELECT COUNT(*) INTO v_approved_count
    FROM attendance
    WHERE payroll_period_id = p_period_id
      AND guard_id = v_guard_id
      AND approval_status IN ('APPROVED', 'APPROVED_AUTO');
    
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
      v_approved_count,
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
    'payroll_rule', 'COUNT(approval_status IN (APPROVED, APPROVED_AUTO))',
    'note', 'Payroll counts supervisor-approved attendance only'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION calculate_payroll_simple IS 
'PAYROLL LAYER: Counts APPROVED + APPROVED_AUTO only. No validation, no filtering, no algorithms.';

-- ========================================
-- 7. INTEGRATION: EXISTING WARNING SYSTEMS
-- ========================================

-- All existing systems (ownership, idempotency, exceptions) now populate warning_details
-- Supervisor sees warnings during review, decides APPROVED or REJECTED

CREATE OR REPLACE VIEW supervisor_review_with_advisories AS
SELECT 
  a.id AS attendance_id,
  a.attendance_date,
  a.approval_status,
  g.full_name AS guard_name,
  u.name AS unit_name,
  
  -- Advisory warnings from existing systems
  COALESCE(
    jsonb_array_length(a.warning_details), 
    0
  ) AS warning_count,
  
  -- Specific advisory flags
  EXISTS (
    SELECT 1 FROM attendance_exceptions ae
    WHERE ae.attendance_id = a.id 
      AND ae.exception_type = 'OWNERSHIP_INVALID'
  ) AS advisory_ownership_issue,
  
  EXISTS (
    SELECT 1 FROM attendance_exceptions ae
    WHERE ae.attendance_id = a.id 
      AND ae.exception_type = 'SHIFT_MISMATCH'
  ) AS advisory_shift_mismatch,
  
  EXISTS (
    SELECT 1 FROM attendance_exceptions ae
    WHERE ae.attendance_id = a.id 
      AND ae.exception_type = 'DUPLICATE_ATTENDANCE'
  ) AS advisory_duplicate,
  
  a.is_retroactive_change AS advisory_retroactive,
  
  -- Full warning details
  a.warning_details AS all_advisories,
  
  -- Exception details for review
  (
    SELECT json_agg(
      json_build_object(
        'type', ae.exception_type,
        'message', ae.exception_message,
        'details', ae.exception_details
      )
    )
    FROM attendance_exceptions ae
    WHERE ae.attendance_id = a.id
  ) AS exception_advisories
FROM attendance a
JOIN guards g ON g.id = a.guard_id
LEFT JOIN shift_instances si ON si.id = a.shift_instance_id
LEFT JOIN units u ON u.id = si.unit_id
WHERE a.approval_status = 'RECORDED'
ORDER BY a.attendance_date DESC;

COMMENT ON VIEW supervisor_review_with_advisories IS 
'SUPERVISOR INTERFACE: Shows all advisory warnings. Supervisor decides despite warnings.';

-- ========================================
-- 8. REPLACEMENT INTEGRATION
-- ========================================

-- Replacement no longer invalidates attendance
-- Both old and new owner attendance stay RECORDED
-- Supervisor decides which to APPROVE

CREATE OR REPLACE FUNCTION transfer_shift_register_model(
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
  
  -- Update shift ownership
  UPDATE shift_instances
  SET
    previous_owner_profile_id = v_old_profile_id,
    current_owner_profile_id = p_new_profile_id,
    updated_at = NOW()
  WHERE id = p_shift_instance_id;
  
  -- Log transfer
  INSERT INTO shift_ownership_history (
    shift_instance_id,
    organization_id,
    unit_id,
    shift_date,
    from_profile_id,
    to_profile_id,
    change_reason,
    change_note,
    changed_by,
    new_status
  )
  VALUES (
    p_shift_instance_id,
    v_shift.organization_id,
    v_shift.unit_id,
    v_shift.shift_date,
    v_old_profile_id,
    p_new_profile_id,
    'GUARD_REPLACEMENT',
    p_change_note,
    p_changed_by,
    'REASSIGNED'
  );
  
  -- Add advisory warning to old owner attendance (if exists)
  UPDATE attendance
  SET
    warning_details = COALESCE(warning_details, '[]'::JSONB) || jsonb_build_object(
      'type', 'shift_ownership_changed',
      'message', 'Shift was reassigned to another guard',
      'for_supervisor_review', true
    )
  WHERE shift_instance_id = p_shift_instance_id
    AND guard_id = (SELECT linked_auth_user FROM workforce_profiles WHERE id = v_old_profile_id)
    AND approval_status = 'RECORDED';
  
  -- NOTE: Old owner attendance stays RECORDED, not auto-rejected
  -- Supervisor decides which guard to approve
  
  RETURN jsonb_build_object(
    'success', true,
    'old_owner_profile_id', v_old_profile_id,
    'new_owner_profile_id', p_new_profile_id,
    'note', 'Both guards attendance stays RECORDED. Supervisor decides which to approve.'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION transfer_shift_register_model IS 
'REPLACEMENT: Never auto-rejects attendance. Supervisor decides which guard to approve.';
