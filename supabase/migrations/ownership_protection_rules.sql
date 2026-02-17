-- ============================================
-- OWNERSHIP PROTECTION RULES
-- Prevent historical manipulation, enable flexible replacement
-- ============================================

-- ========================================
-- 1. ADD SHIFT LOCK TRACKING
-- ========================================

ALTER TABLE shift_instances
  ADD COLUMN IF NOT EXISTS locked_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS locked_by UUID REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS lock_reason TEXT CHECK (lock_reason IN (
    'SUPERVISOR_CONFIRMED',
    'TIME_WINDOW_EXPIRED',
    'PAYROLL_FINALIZED',
    'ADMINISTRATIVE_LOCK'
  )),
  ADD COLUMN IF NOT EXISTS confirmed_by_supervisor UUID REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS confirmed_at TIMESTAMPTZ;

CREATE INDEX idx_shift_instances_locked_at ON shift_instances(locked_at);
CREATE INDEX idx_shift_instances_confirmed_by ON shift_instances(confirmed_by_supervisor);

COMMENT ON COLUMN shift_instances.locked_at IS 
'When shift ownership was locked - no further replacements allowed without admin override';

COMMENT ON COLUMN shift_instances.lock_reason IS 
'Why shift was locked - SUPERVISOR_CONFIRMED, TIME_WINDOW_EXPIRED (12h after end), PAYROLL_FINALIZED, ADMINISTRATIVE_LOCK';

-- ========================================
-- 2. SHIFT LOCK STATUS FUNCTION
-- ========================================

CREATE OR REPLACE FUNCTION get_shift_lock_status(p_shift_instance_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_shift shift_instances;
  v_shift_end_time TIMESTAMPTZ;
  v_time_since_end INTERVAL;
  v_is_locked BOOLEAN;
  v_lock_reason TEXT;
  v_can_replace BOOLEAN;
  v_requires_admin BOOLEAN;
BEGIN
  -- Get shift
  SELECT * INTO v_shift FROM shift_instances WHERE id = p_shift_instance_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'SHIFT_NOT_FOUND');
  END IF;
  
  -- Calculate shift end time (assuming 12-hour shifts if not specified)
  v_shift_end_time := v_shift.shift_date + v_shift.shift_start_time::TIME + INTERVAL '12 hours';
  v_time_since_end := NOW() - v_shift_end_time;
  
  -- ========================================
  -- LOCK STATUS DETERMINATION
  -- ========================================
  
  -- Already locked
  IF v_shift.locked_at IS NOT NULL THEN
    v_is_locked := true;
    v_lock_reason := v_shift.lock_reason;
    v_can_replace := false;
    v_requires_admin := true;
    
  -- 12 hours after shift end → HARD LOCK
  ELSIF v_time_since_end > INTERVAL '12 hours' THEN
    v_is_locked := true;
    v_lock_reason := 'TIME_WINDOW_EXPIRED';
    v_can_replace := false;
    v_requires_admin := true;
    
    -- Auto-lock the shift
    UPDATE shift_instances
    SET 
      locked_at = NOW(),
      lock_reason = 'TIME_WINDOW_EXPIRED',
      locked_by = NULL
    WHERE id = p_shift_instance_id 
      AND locked_at IS NULL;
    
  -- Supervisor confirmed → ADMIN ONLY
  ELSIF v_shift.confirmed_by_supervisor IS NOT NULL THEN
    v_is_locked := false;
    v_lock_reason := 'SUPERVISOR_CONFIRMED';
    v_can_replace := false;
    v_requires_admin := true;
    
  -- During or after shift (not confirmed yet) → SUPERVISOR CAN REPLACE
  ELSIF NOW() >= (v_shift.shift_date + v_shift.shift_start_time::TIME) THEN
    v_is_locked := false;
    v_lock_reason := NULL;
    v_can_replace := true;
    v_requires_admin := false;
    
  -- Before shift start → FREELY REPLACE
  ELSE
    v_is_locked := false;
    v_lock_reason := NULL;
    v_can_replace := true;
    v_requires_admin := false;
  END IF;
  
  RETURN jsonb_build_object(
    'shift_instance_id', p_shift_instance_id,
    'is_locked', v_is_locked,
    'lock_reason', v_lock_reason,
    'can_replace', v_can_replace,
    'requires_admin', v_requires_admin,
    'locked_at', v_shift.locked_at,
    'confirmed_by_supervisor', v_shift.confirmed_by_supervisor,
    'confirmed_at', v_shift.confirmed_at,
    'shift_end_time', v_shift_end_time,
    'time_since_end', v_time_since_end
  );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION get_shift_lock_status IS 
'Determines if shift ownership can be changed and by whom';

-- ========================================
-- 3. PROTECTED TRANSFER FUNCTION
-- ========================================

CREATE OR REPLACE FUNCTION transfer_shift_ownership_protected(
  p_shift_instance_id UUID,
  p_new_profile_id UUID,
  p_changed_by UUID,
  p_change_reason TEXT DEFAULT 'GUARD_REPLACEMENT',
  p_change_note TEXT DEFAULT NULL,
  p_admin_override BOOLEAN DEFAULT false
)
RETURNS JSONB AS $$
DECLARE
  v_shift shift_instances;
  v_old_profile_id UUID;
  v_lock_status JSONB;
  v_user_role TEXT;
BEGIN
  -- Get shift instance
  SELECT * INTO v_shift FROM shift_instances WHERE id = p_shift_instance_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'SHIFT_NOT_FOUND');
  END IF;
  
  -- Get lock status
  v_lock_status := get_shift_lock_status(p_shift_instance_id);
  
  -- Get user role
  SELECT role INTO v_user_role FROM users WHERE id = p_changed_by;
  
  -- ========================================
  -- VALIDATION: TIME WINDOW
  -- ========================================
  
  -- Hard locked (12h+ after shift end)
  IF (v_lock_status->>'is_locked')::BOOLEAN 
     AND (v_lock_status->>'lock_reason') = 'TIME_WINDOW_EXPIRED' THEN
    
    -- Create exception
    INSERT INTO attendance_exceptions (
      attendance_id,
      organization_id,
      guard_id,
      shift_instance_id,
      exception_type,
      exception_message,
      exception_details,
      attendance_date,
      shift_start_date,
      resolution_status
    )
    VALUES (
      NULL,
      v_shift.organization_id,
      (SELECT linked_auth_user FROM workforce_profiles WHERE id = p_new_profile_id),
      p_shift_instance_id,
      'LATE_REPLACEMENT_ATTEMPT',
      'Replacement attempted after 12-hour lock window',
      jsonb_build_object(
        'attempted_by', p_changed_by,
        'attempted_at', NOW(),
        'lock_status', v_lock_status,
        'time_since_end', v_lock_status->>'time_since_end'
      ),
      v_shift.shift_date,
      v_shift.shift_date,
      'PENDING'
    );
    
    RETURN jsonb_build_object(
      'success', false,
      'error', 'TIME_WINDOW_EXPIRED',
      'message', 'Cannot replace shift after 12-hour lock window',
      'lock_status', v_lock_status,
      'requires', 'ADMIN_OVERRIDE_FUNCTION'
    );
  END IF;
  
  -- ========================================
  -- VALIDATION: REQUIRES ADMIN
  -- ========================================
  
  IF (v_lock_status->>'requires_admin')::BOOLEAN THEN
    -- Check if user is admin or has override
    IF v_user_role NOT IN ('ADMIN', 'SUPER_ADMIN') AND NOT p_admin_override THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'ADMIN_REQUIRED',
        'message', 'Shift confirmed by supervisor - only ADMIN can replace',
        'lock_status', v_lock_status
      );
    END IF;
  END IF;
  
  -- ========================================
  -- PERFORM TRANSFER
  -- ========================================
  
  v_old_profile_id := v_shift.current_owner_profile_id;
  
  -- Update shift instance
  UPDATE shift_instances
  SET
    previous_owner_profile_id = v_old_profile_id,
    current_owner_profile_id = p_new_profile_id,
    assigned_profile_id = p_new_profile_id,
    status = 'REASSIGNED',
    ownership_transferred_at = NOW(),
    ownership_transferred_by = p_changed_by,
    updated_at = NOW()
  WHERE id = p_shift_instance_id;
  
  -- Log ownership change
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
    previous_status,
    new_status
  )
  VALUES (
    p_shift_instance_id,
    v_shift.organization_id,
    v_shift.unit_id,
    v_shift.shift_date,
    v_old_profile_id,
    p_new_profile_id,
    p_change_reason,
    p_change_note,
    p_changed_by,
    v_shift.status,
    'REASSIGNED'
  );
  
  -- Invalidate old owner's attendance
  UPDATE attendance
  SET validation_status = 'OPERATIONAL_ONLY', updated_at = NOW()
  WHERE shift_instance_id = p_shift_instance_id
    AND guard_id = (SELECT linked_auth_user FROM workforce_profiles WHERE id = v_old_profile_id)
    AND validation_status = 'VALID_FOR_PAYROLL';
  
  RETURN jsonb_build_object(
    'success', true,
    'shift_instance_id', p_shift_instance_id,
    'old_owner_profile_id', v_old_profile_id,
    'new_owner_profile_id', p_new_profile_id,
    'status', 'REASSIGNED',
    'admin_override_used', p_admin_override
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION transfer_shift_ownership_protected IS 
'Time-window protected transfer: FREE before shift, SUPERVISOR during shift, ADMIN after confirmation, BLOCKED after 12h';

-- ========================================
-- 4. ADMIN OVERRIDE FUNCTION
-- ========================================

CREATE OR REPLACE FUNCTION admin_override_shift_ownership(
  p_shift_instance_id UUID,
  p_new_profile_id UUID,
  p_admin_user_id UUID,
  p_override_reason TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_admin_role TEXT;
BEGIN
  -- Verify admin
  SELECT role INTO v_admin_role FROM users WHERE id = p_admin_user_id;
  
  IF v_admin_role NOT IN ('ADMIN', 'SUPER_ADMIN') THEN
    RETURN jsonb_build_object('success', false, 'error', 'PERMISSION_DENIED');
  END IF;
  
  IF p_override_reason IS NULL OR LENGTH(p_override_reason) < 10 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'OVERRIDE_REASON_REQUIRED',
      'message', 'Admin override requires detailed reason (min 10 characters)'
    );
  END IF;
  
  -- Call transfer with admin override
  RETURN transfer_shift_ownership_protected(
    p_shift_instance_id,
    p_new_profile_id,
    p_admin_user_id,
    'ADMINISTRATIVE_CHANGE',
    p_override_reason,
    true  -- admin_override = true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION admin_override_shift_ownership IS 
'ADMIN ONLY: Override time-window locks with mandatory reason';

-- ========================================
-- 5. SHIFT CONFIRMATION FUNCTION
-- ========================================

CREATE OR REPLACE FUNCTION confirm_shift_attendance(
  p_shift_instance_id UUID,
  p_supervisor_user_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_shift shift_instances;
  v_supervisor_role TEXT;
BEGIN
  -- Get shift
  SELECT * INTO v_shift FROM shift_instances WHERE id = p_shift_instance_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'SHIFT_NOT_FOUND');
  END IF;
  
  -- Check supervisor role
  SELECT role INTO v_supervisor_role FROM users WHERE id = p_supervisor_user_id;
  
  IF v_supervisor_role NOT IN ('SUPERVISOR', 'SITE_SUPERVISOR', 'FIELD_OFFICER', 'ADMIN', 'SUPER_ADMIN') THEN
    RETURN jsonb_build_object('success', false, 'error', 'INSUFFICIENT_PERMISSIONS');
  END IF;
  
  -- Update shift
  UPDATE shift_instances
  SET
    status = 'CONFIRMED',
    confirmed_by_supervisor = p_supervisor_user_id,
    confirmed_at = NOW(),
    updated_at = NOW()
  WHERE id = p_shift_instance_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'shift_instance_id', p_shift_instance_id,
    'status', 'CONFIRMED',
    'confirmed_by', p_supervisor_user_id,
    'confirmed_at', NOW(),
    'note', 'Further replacements require ADMIN approval'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION confirm_shift_attendance IS 
'Supervisor confirms attendance - locks shift to ADMIN-only replacements';

-- ========================================
-- 6. WRONG SHIFT DETECTION
-- ========================================

CREATE OR REPLACE FUNCTION check_shift_assignment(
  p_profile_id UUID,
  p_shift_instance_id UUID,
  p_attendance_date DATE,
  p_check_in_time TIMESTAMPTZ
)
RETURNS JSONB AS $$
DECLARE
  v_shift shift_instances;
  v_profile_unit UUID;
  v_shift_window_start TIMESTAMPTZ;
  v_shift_window_end TIMESTAMPTZ;
  v_is_valid BOOLEAN := true;
  v_mismatch_reason TEXT;
BEGIN
  -- Get shift
  SELECT * INTO v_shift FROM shift_instances WHERE id = p_shift_instance_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'is_valid', false,
      'mismatch_reason', 'SHIFT_NOT_FOUND'
    );
  END IF;
  
  -- Get profile's assigned unit
  SELECT current_unit_id INTO v_profile_unit
  FROM workforce_profiles
  WHERE id = p_profile_id;
  
  -- Check 1: Unit match
  IF v_profile_unit IS NOT NULL AND v_profile_unit != v_shift.unit_id THEN
    v_is_valid := false;
    v_mismatch_reason := format('Profile assigned to different unit (expected: %s, actual: %s)', 
      v_shift.unit_id, v_profile_unit);
  END IF;
  
  -- Check 2: Date match
  IF p_attendance_date != v_shift.shift_date THEN
    v_is_valid := false;
    v_mismatch_reason := format('Date mismatch (shift: %s, attendance: %s)', 
      v_shift.shift_date, p_attendance_date);
  END IF;
  
  -- Check 3: Time window (allow +/- 2 hours grace period)
  v_shift_window_start := v_shift.shift_date + v_shift.shift_start_time::TIME - INTERVAL '2 hours';
  v_shift_window_end := v_shift.shift_date + v_shift.shift_start_time::TIME + INTERVAL '14 hours';
  
  IF p_check_in_time < v_shift_window_start OR p_check_in_time > v_shift_window_end THEN
    v_is_valid := false;
    v_mismatch_reason := format('Check-in outside shift window (shift: %s, check-in: %s)', 
      v_shift.shift_start_time, p_check_in_time::TIME);
  END IF;
  
  RETURN jsonb_build_object(
    'is_valid', v_is_valid,
    'mismatch_reason', v_mismatch_reason,
    'shift_unit_id', v_shift.unit_id,
    'profile_unit_id', v_profile_unit,
    'shift_date', v_shift.shift_date,
    'attendance_date', p_attendance_date,
    'shift_window_start', v_shift_window_start,
    'shift_window_end', v_shift_window_end,
    'check_in_time', p_check_in_time
  );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION check_shift_assignment IS 
'Validates profile is assigned to correct unit and time window matches roster';

-- ========================================
-- 7. ENHANCED UPSERT WITH SHIFT VALIDATION
-- ========================================

CREATE OR REPLACE FUNCTION upsert_attendance_v3(
  p_organization_id UUID,
  p_guard_id UUID,
  p_profile_id UUID,
  p_shift_instance_id UUID,
  p_shift_start_date DATE,
  p_attendance_date DATE,
  p_check_in_time TIMESTAMPTZ,
  p_check_out_time TIMESTAMPTZ,
  p_verification_mode TEXT,
  p_location_coords GEOGRAPHY,
  p_face_verified BOOLEAN,
  p_metadata JSONB,
  p_created_by_user_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_identity_key TEXT;
  v_existing_attendance attendance;
  v_shift shift_instances;
  v_shift_validation JSONB;
  v_is_current_owner BOOLEAN;
  v_attendance_id UUID;
  v_validation_status TEXT;
  v_exception_type TEXT;
  v_exception_message TEXT;
BEGIN
  -- ========================================
  -- SHIFT VALIDATION
  -- ========================================
  
  IF p_shift_instance_id IS NOT NULL THEN
    -- Validate shift assignment
    v_shift_validation := check_shift_assignment(
      p_profile_id,
      p_shift_instance_id,
      p_attendance_date,
      p_check_in_time
    );
    
    -- Get shift
    SELECT * INTO v_shift FROM shift_instances WHERE id = p_shift_instance_id;
    
    -- Check 1: Shift mismatch
    IF NOT (v_shift_validation->>'is_valid')::BOOLEAN THEN
      v_validation_status := 'OPERATIONAL_ONLY';
      v_exception_type := 'SHIFT_MISMATCH';
      v_exception_message := v_shift_validation->>'mismatch_reason';
      
    -- Check 2: Ownership
    ELSIF v_shift.current_owner_profile_id != p_profile_id THEN
      v_validation_status := 'OPERATIONAL_ONLY';
      v_exception_type := 'OWNERSHIP_INVALID';
      v_exception_message := 'Not current shift owner';
      
    ELSE
      v_validation_status := 'VALID_FOR_PAYROLL';
    END IF;
    
    -- Create attendance
    INSERT INTO attendance (
      organization_id,
      guard_id,
      shift_instance_id,
      shift_start_date,
      attendance_date,
      check_in_time,
      check_out_time,
      verification_mode,
      location_coords,
      face_verified,
      metadata,
      validation_status,
      created_by_user_id
    )
    VALUES (
      p_organization_id,
      p_guard_id,
      p_shift_instance_id,
      p_shift_start_date,
      p_attendance_date,
      p_check_in_time,
      p_check_out_time,
      p_verification_mode,
      p_location_coords,
      p_face_verified,
      p_metadata,
      v_validation_status,
      p_created_by_user_id
    )
    ON CONFLICT (attendance_identity_key) 
    WHERE validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
    DO NOTHING
    RETURNING id INTO v_attendance_id;
    
    -- Create exception if validation failed
    IF v_validation_status = 'OPERATIONAL_ONLY' THEN
      INSERT INTO attendance_exceptions (
        attendance_id,
        organization_id,
        guard_id,
        shift_instance_id,
        exception_type,
        exception_message,
        exception_details,
        attendance_date,
        shift_start_date,
        resolution_status
      )
      VALUES (
        v_attendance_id,
        p_organization_id,
        p_guard_id,
        p_shift_instance_id,
        v_exception_type,
        v_exception_message,
        v_shift_validation,
        p_attendance_date,
        p_shift_start_date,
        'PENDING'
      );
    END IF;
    
    RETURN jsonb_build_object(
      'success', true,
      'action', CASE WHEN v_validation_status = 'VALID_FOR_PAYROLL' THEN 'INSERTED' ELSE 'EXCEPTION_CREATED' END,
      'attendance_id', v_attendance_id,
      'validation_status', v_validation_status,
      'is_payable', v_validation_status = 'VALID_FOR_PAYROLL',
      'exception_type', v_exception_type
    );
  END IF;
  
  RETURN jsonb_build_object('success', false, 'error', 'SHIFT_INSTANCE_REQUIRED');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION upsert_attendance_v3 IS 
'SHIFT-VALIDATED UPSERT: Checks ownership + unit assignment + time window';

-- ========================================
-- 8. SAFE PAYROLL AGGREGATION
-- ========================================

CREATE OR REPLACE FUNCTION aggregate_work_units_confirmed_only(p_period_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_period payroll_periods;
  v_guard_id UUID;
  v_present_count DECIMAL;
  v_units_created INTEGER := 0;
BEGIN
  SELECT * INTO v_period FROM payroll_periods WHERE id = p_period_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'PERIOD_NOT_FOUND');
  END IF;
  
  FOR v_guard_id IN
    SELECT DISTINCT a.guard_id
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    WHERE a.payroll_period_id = p_period_id
      AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
      -- CRITICAL: Only count confirmed shifts
      AND (si.confirmed_by_supervisor IS NOT NULL OR si.status = 'AUTO_CONFIRMED')
  LOOP
    -- Count only CONFIRMED shifts
    SELECT COUNT(DISTINCT si.id) INTO v_present_count
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    WHERE a.payroll_period_id = p_period_id
      AND a.guard_id = v_guard_id
      AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
      AND (si.confirmed_by_supervisor IS NOT NULL OR si.status = 'AUTO_CONFIRMED');
    
    INSERT INTO payroll_work_units (
      payroll_period_id,
      guard_id,
      organization_id,
      present_days,
      aggregation_status
    )
    VALUES (p_period_id, v_guard_id, v_period.organization_id, v_present_count, 'DRAFT')
    ON CONFLICT (payroll_period_id, guard_id) DO UPDATE SET present_days = EXCLUDED.present_days;
    
    v_units_created := v_units_created + 1;
  END LOOP;
  
  RETURN jsonb_build_object('success', true, 'work_units_created', v_units_created);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION aggregate_work_units_confirmed_only IS 
'PAYROLL SAFETY: Only counts shifts with confirmed_by_supervisor OR auto_confirmed';
