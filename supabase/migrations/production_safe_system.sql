-- ============================================
-- PRODUCTION-SAFE ATTENDANCE SYSTEM
-- Zero blocking, full accountability through filtering
-- ============================================

-- SYSTEM LAWS COMPLIANCE:
-- ✅ Never block attendance capture
-- ✅ Filter at payroll, not at punch time
-- ✅ Additive only (extends existing)
-- ✅ Humans override algorithms
-- ✅ Monitor, don't enforce

-- ========================================
-- 1. PRODUCTION-SAFE ATTENDANCE CAPTURE
-- ========================================

CREATE OR REPLACE FUNCTION capture_attendance_safe(
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
  v_attendance_id UUID;
  v_shift shift_instances;
  v_validation_issues JSONB := '[]'::JSONB;
  v_initial_status TEXT := 'VALID_FOR_PAYROLL';
  v_warning_count INTEGER := 0;
BEGIN
  -- ========================================
  -- RULE: ALWAYS ACCEPT ATTENDANCE
  -- Validation creates warnings, never rejects
  -- ========================================
  
  -- Get shift (if provided)
  IF p_shift_instance_id IS NOT NULL THEN
    SELECT * INTO v_shift FROM shift_instances WHERE id = p_shift_instance_id;
  END IF;
  
  -- ========================================
  -- COLLECT VALIDATION ISSUES (DON'T BLOCK)
  -- ========================================
  
  -- Check 1: Ownership (collect issue, don't block)
  IF v_shift IS NOT NULL AND v_shift.current_owner_profile_id != p_profile_id THEN
    v_validation_issues := v_validation_issues || jsonb_build_object(
      'type', 'OWNERSHIP_MISMATCH',
      'severity', 'WARNING',
      'message', format('Profile %s not current owner (current: %s)', p_profile_id, v_shift.current_owner_profile_id),
      'blocks_payroll', false  -- Just a warning, still payable
    );
    v_warning_count := v_warning_count + 1;
  END IF;
  
  -- Check 2: Shift existence
  IF p_shift_instance_id IS NOT NULL AND v_shift IS NULL THEN
    v_validation_issues := v_validation_issues || jsonb_build_object(
      'type', 'SHIFT_NOT_FOUND',
      'severity', 'WARNING',
      'message', 'Shift instance not found',
      'blocks_payroll', false
    );
    v_warning_count := v_warning_count + 1;
  END IF;
  
  -- Check 3: Date mismatch
  IF v_shift IS NOT NULL AND p_attendance_date != v_shift.shift_date THEN
    v_validation_issues := v_validation_issues || jsonb_build_object(
      'type', 'DATE_MISMATCH',
      'severity', 'WARNING',
      'message', format('Attendance date %s != shift date %s', p_attendance_date, v_shift.shift_date),
      'blocks_payroll', false
    );
    v_warning_count := v_warning_count + 1;
  END IF;
  
  -- ========================================
  -- ALWAYS INSERT (NEVER REJECT)
  -- ========================================
  
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
    has_warnings,
    warning_details,
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
    v_initial_status,  -- Always VALID initially
    v_warning_count > 0,
    CASE WHEN v_warning_count > 0 THEN v_validation_issues ELSE NULL END,
    p_created_by_user_id
  )
  ON CONFLICT (attendance_identity_key) 
  WHERE validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
  DO UPDATE SET
    check_in_time = CASE 
      WHEN EXCLUDED.check_in_time < attendance.check_in_time 
      THEN EXCLUDED.check_in_time 
      ELSE attendance.check_in_time 
    END,
    updated_at = NOW()
  RETURNING id INTO v_attendance_id;
  
  -- ========================================
  -- LOG WARNINGS AS EXCEPTIONS (NON-BLOCKING)
  -- ========================================
  
  IF v_warning_count > 0 THEN
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
      resolution_status,
      resolution_source
    )
    VALUES (
      v_attendance_id,
      p_organization_id,
      p_guard_id,
      p_shift_instance_id,
      'VALIDATION_WARNINGS',
      format('%s validation warnings detected', v_warning_count),
      v_validation_issues,
      p_attendance_date,
      p_shift_start_date,
      'PENDING',
      NULL
    )
    ON CONFLICT DO NOTHING;
  END IF;
  
  RETURN jsonb_build_object(
    'success', true,
    'action', 'CAPTURED',
    'attendance_id', v_attendance_id,
    'validation_status', v_initial_status,
    'warnings', v_validation_issues,
    'warning_count', v_warning_count,
    'message', CASE 
      WHEN v_warning_count = 0 THEN 'Attendance captured successfully'
      ELSE format('Attendance captured with %s warnings (still payable)', v_warning_count)
    END
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION capture_attendance_safe IS 
'PRODUCTION-SAFE: NEVER rejects attendance. Captures with warnings. Validation done at payroll time.';

-- ========================================
-- 2. PRODUCTION-SAFE SHIFT TRANSFER
-- ========================================

CREATE OR REPLACE FUNCTION transfer_shift_safe(
  p_shift_instance_id UUID,
  p_new_profile_id UUID,
  p_changed_by UUID,
  p_change_reason TEXT DEFAULT 'GUARD_REPLACEMENT',
  p_change_note TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_shift shift_instances;
  v_old_profile_id UUID;
  v_shift_end_time TIMESTAMPTZ;
  v_is_retroactive BOOLEAN := false;
  v_warnings JSONB := '[]'::JSONB;
BEGIN
  -- ========================================
  -- RULE: ALWAYS ALLOW TRANSFER
  -- Time checks create warnings, never block
  -- ========================================
  
  SELECT * INTO v_shift FROM shift_instances WHERE id = p_shift_instance_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'SHIFT_NOT_FOUND');
  END IF;
  
  v_old_profile_id := v_shift.current_owner_profile_id;
  v_shift_end_time := v_shift.shift_date + v_shift.shift_start_time::TIME + INTERVAL '12 hours';
  
  -- ========================================
  -- COLLECT WARNINGS (DON'T BLOCK)
  -- ========================================
  
  -- Warning 1: Retroactive (after 12h)
  IF NOW() > v_shift_end_time + INTERVAL '12 hours' THEN
    v_is_retroactive := true;
    v_warnings := v_warnings || jsonb_build_object(
      'type', 'RETROACTIVE_TRANSFER',
      'severity', 'INFO',
      'message', format('Transfer %s hours after shift end', 
        ROUND(EXTRACT(EPOCH FROM (NOW() - v_shift_end_time)) / 3600::numeric, 1))
    );
  END IF;
  
  -- Warning 2: After supervisor confirmation
  IF v_shift.confirmed_by_supervisor IS NOT NULL THEN
    v_warnings := v_warnings || jsonb_build_object(
      'type', 'POST_CONFIRMATION_TRANSFER',
      'severity', 'INFO',
      'message', 'Transfer after supervisor confirmation'
    );
  END IF;
  
  -- Warning 3: Already locked
  IF v_shift.locked_at IS NOT NULL THEN
    v_warnings := v_warnings || jsonb_build_object(
      'type', 'LOCKED_SHIFT_TRANSFER',
      'severity', 'INFO',
      'message', format('Transfer on locked shift (reason: %s)', v_shift.lock_reason)
    );
  END IF;
  
  -- ========================================
  -- ALWAYS PERFORM TRANSFER
  -- ========================================
  
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
    CASE WHEN v_is_retroactive THEN 'RETROACTIVE_TRANSFER' ELSE p_change_reason END,
    p_change_note,
    p_changed_by,
    v_shift.status,
    'REASSIGNED'
  );
  
  -- Mark old owner attendance (if exists)
  UPDATE attendance
  SET 
    has_warnings = true,
    warning_details = COALESCE(warning_details, '[]'::JSONB) || jsonb_build_object(
      'type', 'OWNERSHIP_CHANGED',
      'message', 'Shift ownership transferred after attendance'
    ),
    is_retroactive_change = v_is_retroactive,
    retroactive_reason = p_change_note
  WHERE shift_instance_id = p_shift_instance_id
    AND guard_id = (SELECT linked_auth_user FROM workforce_profiles WHERE id = v_old_profile_id);
  
  RETURN jsonb_build_object(
    'success', true,
    'action', 'TRANSFERRED',
    'shift_instance_id', p_shift_instance_id,
    'old_owner_profile_id', v_old_profile_id,
    'new_owner_profile_id', p_new_profile_id,
    'is_retroactive', v_is_retroactive,
    'warnings', v_warnings,
    'message', CASE 
      WHEN jsonb_array_length(v_warnings) = 0 THEN 'Transfer successful'
      ELSE format('Transfer successful with %s warnings', jsonb_array_length(v_warnings))
    END
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION transfer_shift_safe IS 
'PRODUCTION-SAFE: NEVER blocks transfers. Time checks create warnings, not rejections.';

-- ========================================
-- 3. PAYROLL FILTERING (VALIDATION HERE, NOT AT PUNCH)
-- ========================================

CREATE OR REPLACE FUNCTION filter_payroll_attendance(p_period_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_period payroll_periods;
  v_total_attendance INTEGER;
  v_valid_attendance INTEGER;
  v_excluded_ownership INTEGER := 0;
  v_excluded_unconfirmed INTEGER := 0;
  v_excluded_critical INTEGER := 0;
  v_warnings_included INTEGER := 0;
BEGIN
  SELECT * INTO v_period FROM payroll_periods WHERE id = p_period_id;
  
  -- Count total
  SELECT COUNT(*) INTO v_total_attendance
  FROM attendance
  WHERE payroll_period_id = p_period_id;
  
  -- ========================================
  -- VALIDATION AT PAYROLL TIME (NOT PUNCH TIME)
  -- ========================================
  
  -- Mark attendance with critical ownership issues
  WITH ownership_checks AS (
    SELECT 
      a.id,
      si.current_owner_profile_id,
      wp.id AS attendance_profile_id
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    JOIN guards g ON g.id = a.guard_id
    LEFT JOIN workforce_profiles wp ON wp.linked_auth_user = g.id
    WHERE a.payroll_period_id = p_period_id
      AND a.validation_status = 'VALID_FOR_PAYROLL'
      AND si.current_owner_profile_id != wp.id
      AND NOT COALESCE(a.has_warnings, false)  -- Not already marked
  )
  UPDATE attendance a
  SET 
    validation_status = 'OPERATIONAL_ONLY',
    updated_at = NOW()
  FROM ownership_checks oc
  WHERE a.id = oc.id;
  
  GET DIAGNOSTICS v_excluded_ownership = ROW_COUNT;
  
  -- Mark unconfirmed shifts
  WITH unconfirmed_shifts AS (
    SELECT a.id
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    WHERE a.payroll_period_id = p_period_id
      AND a.validation_status = 'VALID_FOR_PAYROLL'
      AND si.confirmed_by_supervisor IS NULL
      AND si.status NOT IN ('AUTO_CONFIRMED', 'PAYROLL_LOCKED')
      AND NOW() < (si.shift_date + si.shift_start_time::TIME + INTERVAL '36 hours')  -- Give 36h grace
  )
  UPDATE attendance a
  SET 
    validation_status = 'OPERATIONAL_ONLY',
    updated_at = NOW()
  FROM unconfirmed_shifts us
  WHERE a.id = us.id;
  
  GET DIAGNOSTICS v_excluded_unconfirmed = ROW_COUNT;
  
  -- Count valid (including warnings)
  SELECT COUNT(*) INTO v_valid_attendance
  FROM attendance a
  LEFT JOIN shift_instances si ON si.id = a.shift_instance_id
  WHERE a.payroll_period_id = p_period_id
    AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
    AND (
      si.confirmed_by_supervisor IS NOT NULL 
      OR si.status IN ('AUTO_CONFIRMED', 'PAYROLL_LOCKED')
      OR si.id IS NULL  -- Manual attendance
    );
  
  -- Count warnings included
  SELECT COUNT(*) INTO v_warnings_included
  FROM attendance
  WHERE payroll_period_id = p_period_id
    AND validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
    AND has_warnings = true;
  
  RETURN jsonb_build_object(
    'success', true,
    'period_id', p_period_id,
    'total_attendance', v_total_attendance,
    'valid_for_payroll', v_valid_attendance,
    'excluded_ownership', v_excluded_ownership,
    'excluded_unconfirmed', v_excluded_unconfirmed,
    'warnings_included', v_warnings_included,
    'filtering_note', 'Validation done at payroll time, not capture time'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION filter_payroll_attendance IS 
'PAYROLL-TIME VALIDATION: Filters bad data that was allowed to enter. Never blocks capture.';

-- ========================================
-- 4. PRODUCTION-SAFE PAYROLL AGGREGATION
-- ========================================

CREATE OR REPLACE FUNCTION aggregate_payroll_safe(p_period_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_period payroll_periods;
  v_guard_id UUID;
  v_shift_count DECIMAL;
  v_units_created INTEGER := 0;
  v_filter_result JSONB;
BEGIN
  -- Filter first (validation at payroll time)
  v_filter_result := filter_payroll_attendance(p_period_id);
  
  SELECT * INTO v_period FROM payroll_periods WHERE id = p_period_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'PERIOD_NOT_FOUND');
  END IF;
  
  -- Aggregate only valid + confirmed
  FOR v_guard_id IN
    SELECT DISTINCT a.guard_id
    FROM attendance a
    LEFT JOIN shift_instances si ON si.id = a.shift_instance_id
    WHERE a.payroll_period_id = p_period_id
      AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
      AND (
        si.confirmed_by_supervisor IS NOT NULL
        OR si.status IN ('AUTO_CONFIRMED', 'PAYROLL_LOCKED')
        OR si.id IS NULL
      )
  LOOP
    -- Count distinct shifts
    SELECT COUNT(DISTINCT COALESCE(si.id, a.id)) INTO v_shift_count
    FROM attendance a
    LEFT JOIN shift_instances si ON si.id = a.shift_instance_id
    WHERE a.payroll_period_id = p_period_id
      AND a.guard_id = v_guard_id
      AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
      AND (
        si.confirmed_by_supervisor IS NOT NULL
        OR si.status IN ('AUTO_CONFIRMED', 'PAYROLL_LOCKED')
        OR si.id IS NULL
      );
    
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
      v_shift_count,
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
    'filter_result', v_filter_result,
    'note', 'Includes warnings, excludes only critical issues'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION aggregate_payroll_safe IS 
'PRODUCTION-SAFE: Filters at aggregation time. Includes warnings, excludes critical only.';

-- ========================================
-- 5. BACKWARD COMPATIBILITY WRAPPERS
-- ========================================

-- Wrapper for existing code calling upsert_attendance
CREATE OR REPLACE FUNCTION upsert_attendance(
  p_organization_id UUID,
  p_guard_id UUID,
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
  v_profile_id UUID;
BEGIN
  -- Get profile_id from guard_id
  SELECT id INTO v_profile_id
  FROM workforce_profiles
  WHERE linked_auth_user = p_guard_id
  LIMIT 1;
  
  -- Call production-safe version
  RETURN capture_attendance_safe(
    p_organization_id,
    p_guard_id,
    v_profile_id,
    p_shift_instance_id,
    p_shift_start_date,
    p_attendance_date,
    p_check_in_time,
    p_check_out_time,
    p_verification_mode,
    p_location_coords,
    p_face_verified,
    p_metadata,
    p_created_by_user_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION upsert_attendance IS 
'BACKWARD COMPATIBLE: Wraps capture_attendance_safe for existing code';

-- Wrapper for shift ownership transfer
CREATE OR REPLACE FUNCTION transfer_shift_ownership(
  p_shift_instance_id UUID,
  p_new_profile_id UUID,
  p_changed_by UUID,
  p_change_reason TEXT DEFAULT 'GUARD_REPLACEMENT',
  p_change_note TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
BEGIN
  RETURN transfer_shift_safe(
    p_shift_instance_id,
    p_new_profile_id,
    p_changed_by,
    p_change_reason,
    p_change_note
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION transfer_shift_ownership IS 
'BACKWARD COMPATIBLE: Wraps transfer_shift_safe for existing code';
