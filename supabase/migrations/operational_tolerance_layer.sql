-- ============================================
-- OPERATIONAL TOLERANCE LAYER
-- Prevent workflow blockage while maintaining accountability
-- ============================================

-- Goal: Protection without paralysis
-- Rules become warnings + audit trails, not blockers

-- ========================================
-- 1. ADD TOLERANCE TRACKING COLUMNS
-- ========================================

ALTER TABLE attendance
  ADD COLUMN IF NOT EXISTS has_warnings BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS warning_details JSONB,
  ADD COLUMN IF NOT EXISTS is_retroactive_change BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS retroactive_reason TEXT;

CREATE INDEX idx_attendance_warnings ON attendance(has_warnings) WHERE has_warnings = true;
CREATE INDEX idx_attendance_retroactive ON attendance(is_retroactive_change) WHERE is_retroactive_change = true;

COMMENT ON COLUMN attendance.has_warnings IS 
'True if attendance has warnings (shift mismatch, time issues) but still payable';

COMMENT ON COLUMN attendance.is_retroactive_change IS 
'True if attendance changed after 12h window (soft lock bypass)';

-- ========================================
-- 2. SILENT SUPERVISOR FALLBACK (24h Auto-Confirm)
-- ========================================

CREATE OR REPLACE FUNCTION auto_confirm_unconfirmed_shifts()
RETURNS JSONB AS $$
DECLARE
  v_shift RECORD;
  v_confirmed_count INTEGER := 0;
  v_shift_end_time TIMESTAMPTZ;
BEGIN
  -- Find unconfirmed shifts older than 24h after shift end
  FOR v_shift IN
    SELECT 
      si.*,
      (si.shift_date + si.shift_start_time::TIME + INTERVAL '12 hours') AS shift_end_time
    FROM shift_instances si
    WHERE si.status NOT IN ('CONFIRMED', 'AUTO_CONFIRMED', 'PAYROLL_LOCKED')
      AND si.confirmed_by_supervisor IS NULL
      AND EXISTS (
        SELECT 1 FROM attendance a
        WHERE a.shift_instance_id = si.id
          AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
      )
  LOOP
    v_shift_end_time := v_shift.shift_end_time;
    
    -- 24 hours after shift end without supervisor confirmation
    IF NOW() > v_shift_end_time + INTERVAL '24 hours' THEN
      -- Auto-confirm
      UPDATE shift_instances
      SET
        status = 'AUTO_CONFIRMED',
        auto_confirm_reason = 'SUPERVISOR_NO_ACTION',
        confirmed_at = NOW(),
        updated_at = NOW()
      WHERE id = v_shift.id;
      
      -- Log notification
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
        'SHIFT_AUTO_CONFIRMED',
        u.id,
        v_shift.id,
        'SHIFT_INSTANCE',
        'Shift Auto-Confirmed (Supervisor No Action)',
        format('Shift on %s auto-confirmed after 24h - supervisor did not confirm', v_shift.shift_date),
        'WARNING',
        jsonb_build_object(
          'shift_date', v_shift.shift_date,
          'unit_id', v_shift.unit_id,
          'hours_since_end', EXTRACT(EPOCH FROM (NOW() - v_shift_end_time)) / 3600
        )
      FROM users u
      WHERE u.organization_id = v_shift.organization_id
        AND u.role IN ('ADMIN', 'SUPER_ADMIN')
      LIMIT 1;
      
      v_confirmed_count := v_confirmed_count + 1;
    END IF;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'auto_confirmed_count', v_confirmed_count,
    'reason', 'SUPERVISOR_NO_ACTION'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION auto_confirm_unconfirmed_shifts IS 
'SILENT FALLBACK: Auto-confirms shifts 24h after end if supervisor did not confirm';

-- Create cron job for auto-confirmation (runs every 6 hours)
-- SELECT cron.schedule(
--   'auto-confirm-shifts',
--   '0 */6 * * *',
--   $$SELECT auto_confirm_unconfirmed_shifts()$$
-- );

-- ========================================
-- 3. SOFT LOCK (Allow Late Changes with Audit)
-- ========================================

CREATE OR REPLACE FUNCTION transfer_shift_ownership_tolerant(
  p_shift_instance_id UUID,
  p_new_profile_id UUID,
  p_changed_by UUID,
  p_change_reason TEXT DEFAULT 'GUARD_REPLACEMENT',
  p_change_note TEXT DEFAULT NULL,
  p_admin_note TEXT DEFAULT NULL  -- Required for retroactive changes
)
RETURNS JSONB AS $$
DECLARE
  v_shift shift_instances;
  v_old_profile_id UUID;
  v_lock_status JSONB;
  v_user_role TEXT;
  v_shift_end_time TIMESTAMPTZ;
  v_is_retroactive BOOLEAN := false;
BEGIN
  -- Get shift instance
  SELECT * INTO v_shift FROM shift_instances WHERE id = p_shift_instance_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'SHIFT_NOT_FOUND');
  END IF;
  
  -- Calculate shift end
  v_shift_end_time := v_shift.shift_date + v_shift.shift_start_time::TIME + INTERVAL '12 hours';
  
  -- Get user role
  SELECT role INTO v_user_role FROM users WHERE id = p_changed_by;
  
  -- ========================================
  -- SOFT LOCK CHECK (12h after shift end)
  -- ========================================
  
  IF NOW() > v_shift_end_time + INTERVAL '12 hours' THEN
    -- This is a retroactive change
    v_is_retroactive := true;
    
    -- Require admin role
    IF v_user_role NOT IN ('ADMIN', 'SUPER_ADMIN') THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'RETROACTIVE_ADMIN_REQUIRED',
        'message', 'Change after 12h window requires ADMIN role',
        'is_retroactive', true
      );
    END IF;
    
    -- Require admin note
    IF p_admin_note IS NULL OR LENGTH(p_admin_note) < 10 THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'RETROACTIVE_NOTE_REQUIRED',
        'message', 'Retroactive change requires detailed admin note (min 10 chars)',
        'is_retroactive', true
      );
    END IF;
    
    -- ALLOW but mark as retroactive (SOFT LOCK)
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
    CASE WHEN v_is_retroactive THEN 'RETROACTIVE_CHANGE' ELSE p_change_reason END,
    p_admin_note,
    p_changed_by,
    v_shift.status,
    'REASSIGNED'
  );
  
  -- Mark old owner's attendance as retroactive if exists
  IF v_is_retroactive THEN
    UPDATE attendance
    SET 
      validation_status = 'OPERATIONAL_ONLY',
      is_retroactive_change = true,
      retroactive_reason = p_admin_note,
      updated_at = NOW()
    WHERE shift_instance_id = p_shift_instance_id
      AND guard_id = (SELECT linked_auth_user FROM workforce_profiles WHERE id = v_old_profile_id)
      AND validation_status = 'VALID_FOR_PAYROLL';
    
    -- Create audit exception
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
      resolution_source,
      liability_role
    )
    SELECT
      a.id,
      a.organization_id,
      a.guard_id,
      a.shift_instance_id,
      'RETROACTIVE_CHANGE',
      'Shift ownership changed after 12h window',
      jsonb_build_object(
        'old_owner_profile_id', v_old_profile_id,
        'new_owner_profile_id', p_new_profile_id,
        'admin_note', p_admin_note,
        'hours_after_shift', EXTRACT(EPOCH FROM (NOW() - v_shift_end_time)) / 3600
      ),
      a.attendance_date,
      a.shift_start_date,
      'RESOLVED',
      'SYSTEM_AUTO',
      'SUPERVISOR'
    FROM attendance a
    WHERE a.shift_instance_id = p_shift_instance_id
      AND a.is_retroactive_change = true
    ON CONFLICT DO NOTHING;
  ELSE
    -- Normal invalidation
    UPDATE attendance
    SET validation_status = 'OPERATIONAL_ONLY', updated_at = NOW()
    WHERE shift_instance_id = p_shift_instance_id
      AND guard_id = (SELECT linked_auth_user FROM workforce_profiles WHERE id = v_old_profile_id)
      AND validation_status = 'VALID_FOR_PAYROLL';
  END IF;
  
  RETURN jsonb_build_object(
    'success', true,
    'shift_instance_id', p_shift_instance_id,
    'old_owner_profile_id', v_old_profile_id,
    'new_owner_profile_id', p_new_profile_id,
    'status', 'REASSIGNED',
    'is_retroactive', v_is_retroactive,
    'message', CASE 
      WHEN v_is_retroactive THEN 'Retroactive change allowed - marked in audit trail'
      ELSE 'Transfer successful'
    END
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION transfer_shift_ownership_tolerant IS 
'SOFT LOCK: Allows late replacements with admin note + audit trail instead of blocking';

-- ========================================
-- 4. FORGIVING SHIFT MISMATCH
-- ========================================

CREATE OR REPLACE FUNCTION check_shift_assignment_tolerant(
  p_profile_id UUID,
  p_shift_instance_id UUID,
  p_attendance_date DATE,
  p_check_in_time TIMESTAMPTZ
)
RETURNS JSONB AS $$
DECLARE
  v_shift shift_instances;
  v_profile_unit UUID;
  v_profile_assignments RECORD;
  v_shift_window_start TIMESTAMPTZ;
  v_shift_window_end TIMESTAMPTZ;
  v_is_valid BOOLEAN := true;
  v_has_warnings BOOLEAN := false;
  v_mismatch_severity TEXT := 'NONE';
  v_mismatch_reason TEXT;
  v_warning_details JSONB := '[]'::JSONB;
BEGIN
  -- Get shift
  SELECT * INTO v_shift FROM shift_instances WHERE id = p_shift_instance_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'is_valid', false,
      'mismatch_severity', 'CRITICAL',
      'mismatch_reason', 'SHIFT_NOT_FOUND'
    );
  END IF;
  
  -- Get profile's current and recent assignments
  SELECT 
    wp.current_unit_id,
    array_agg(DISTINCT si2.unit_id) FILTER (WHERE si2.shift_date = p_attendance_date) AS same_day_units
  INTO v_profile_assignments
  FROM workforce_profiles wp
  LEFT JOIN shift_instances si2 ON si2.assigned_profile_id = wp.id
  WHERE wp.id = p_profile_id
  GROUP BY wp.id, wp.current_unit_id;
  
  v_profile_unit := v_profile_assignments.current_unit_id;
  
  -- ========================================
  -- FORGIVING UNIT CHECK
  -- ========================================
  
  IF v_profile_unit IS NOT NULL AND v_profile_unit != v_shift.unit_id THEN
    -- Check if guard has ANY assignment to this unit on same day
    IF v_shift.unit_id = ANY(v_profile_assignments.same_day_units) THEN
      -- DOWNGRADE TO WARNING (guard assigned to same unit on same day)
      v_mismatch_severity := 'WARNING';
      v_has_warnings := true;
      v_warning_details := v_warning_details || jsonb_build_object(
        'type', 'UNIT_MISMATCH_MINOR',
        'message', format('Profile primary unit: %s, shift unit: %s (but guard has shift in this unit today)', 
          v_profile_unit, v_shift.unit_id)
      );
    ELSE
      -- CRITICAL MISMATCH (guard not assigned to this unit at all)
      v_is_valid := false;
      v_mismatch_severity := 'CRITICAL';
      v_mismatch_reason := format('Profile assigned to different unit (expected: %s, actual: %s) and no shift in target unit', 
        v_shift.unit_id, v_profile_unit);
    END IF;
  END IF;
  
  -- ========================================
  -- DATE CHECK
  -- ========================================
  
  IF p_attendance_date != v_shift.shift_date THEN
    v_is_valid := false;
    v_mismatch_severity := 'CRITICAL';
    v_mismatch_reason := format('Date mismatch (shift: %s, attendance: %s)', 
      v_shift.shift_date, p_attendance_date);
  END IF;
  
  -- ========================================
  -- FORGIVING TIME WINDOW (±2h grace)
  -- ========================================
  
  v_shift_window_start := v_shift.shift_date + v_shift.shift_start_time::TIME - INTERVAL '2 hours';
  v_shift_window_end := v_shift.shift_date + v_shift.shift_start_time::TIME + INTERVAL '14 hours';
  
  IF p_check_in_time < v_shift_window_start OR p_check_in_time > v_shift_window_end THEN
    -- Outside window but not critical if close
    IF p_check_in_time >= v_shift_window_start - INTERVAL '1 hour' 
       AND p_check_in_time <= v_shift_window_end + INTERVAL '1 hour' THEN
      -- DOWNGRADE TO WARNING (within 1h of grace window)
      v_mismatch_severity := 'WARNING';
      v_has_warnings := true;
      v_warning_details := v_warning_details || jsonb_build_object(
        'type', 'TIME_WINDOW_MINOR',
        'message', format('Check-in slightly outside shift window: %s (shift: %s)', 
          p_check_in_time::TIME, v_shift.shift_start_time)
      );
    ELSE
      -- CRITICAL (way outside window)
      v_is_valid := false;
      v_mismatch_severity := 'CRITICAL';
      v_mismatch_reason := format('Check-in far outside shift window (shift: %s, check-in: %s)', 
        v_shift.shift_start_time, p_check_in_time::TIME);
    END IF;
  END IF;
  
  RETURN jsonb_build_object(
    'is_valid', v_is_valid,
    'has_warnings', v_has_warnings,
    'mismatch_severity', v_mismatch_severity,
    'mismatch_reason', v_mismatch_reason,
    'warning_details', v_warning_details,
    'shift_unit_id', v_shift.unit_id,
    'profile_unit_id', v_profile_unit,
    'profile_same_day_units', v_profile_assignments.same_day_units
  );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION check_shift_assignment_tolerant IS 
'FORGIVING VALIDATION: Same unit/day = warning (payable), wrong unit = critical (not payable)';

-- ========================================
-- 5. TOLERANT UPSERT WITH WARNINGS
-- ========================================

CREATE OR REPLACE FUNCTION upsert_attendance_tolerant(
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
  v_shift shift_instances;
  v_shift_validation JSONB;
  v_attendance_id UUID;
  v_validation_status TEXT;
  v_exception_type TEXT;
  v_exception_message TEXT;
  v_has_warnings BOOLEAN := false;
  v_warning_details JSONB;
BEGIN
  IF p_shift_instance_id IS NOT NULL THEN
    -- Tolerant validation
    v_shift_validation := check_shift_assignment_tolerant(
      p_profile_id,
      p_shift_instance_id,
      p_attendance_date,
      p_check_in_time
    );
    
    SELECT * INTO v_shift FROM shift_instances WHERE id = p_shift_instance_id;
    
    -- Determine validation status
    IF NOT (v_shift_validation->>'is_valid')::BOOLEAN THEN
      -- CRITICAL mismatch - not payable
      v_validation_status := 'OPERATIONAL_ONLY';
      v_exception_type := 'SHIFT_MISMATCH';
      v_exception_message := v_shift_validation->>'mismatch_reason';
      
    ELSIF v_shift.current_owner_profile_id != p_profile_id THEN
      -- Ownership mismatch - not payable
      v_validation_status := 'OPERATIONAL_ONLY';
      v_exception_type := 'OWNERSHIP_INVALID';
      v_exception_message := 'Not current shift owner';
      
    ELSIF (v_shift_validation->>'has_warnings')::BOOLEAN THEN
      -- Has warnings but STILL VALID FOR PAYROLL
      v_validation_status := 'VALID_FOR_PAYROLL';
      v_has_warnings := true;
      v_warning_details := v_shift_validation->'warning_details';
      
    ELSE
      -- Clean validation
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
      v_validation_status,
      v_has_warnings,
      v_warning_details,
      p_created_by_user_id
    )
    ON CONFLICT (attendance_identity_key) 
    WHERE validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
    DO NOTHING
    RETURNING id INTO v_attendance_id;
    
    -- Create exception only for critical issues
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
      'action', CASE 
        WHEN v_validation_status = 'VALID_FOR_PAYROLL' AND NOT v_has_warnings THEN 'INSERTED'
        WHEN v_validation_status = 'VALID_FOR_PAYROLL' AND v_has_warnings THEN 'INSERTED_WITH_WARNINGS'
        ELSE 'EXCEPTION_CREATED'
      END,
      'attendance_id', v_attendance_id,
      'validation_status', v_validation_status,
      'is_payable', v_validation_status = 'VALID_FOR_PAYROLL',
      'has_warnings', v_has_warnings,
      'warning_details', v_warning_details,
      'exception_type', v_exception_type
    );
  END IF;
  
  RETURN jsonb_build_object('success', false, 'error', 'SHIFT_INSTANCE_REQUIRED');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION upsert_attendance_tolerant IS 
'TOLERANT UPSERT: Warnings stay payable, only critical issues excluded';

-- ========================================
-- 6. PAYROLL TRUST MODEL
-- ========================================

CREATE OR REPLACE FUNCTION aggregate_work_units_trust_model(p_period_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_period payroll_periods;
  v_guard_id UUID;
  v_present_count DECIMAL;
  v_units_created INTEGER := 0;
  v_excluded_critical INTEGER := 0;
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
      -- INCLUDE: VALID_FOR_PAYROLL (with or without warnings)
      AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
      -- INCLUDE: All confirmed shifts (supervisor or auto)
      AND (si.confirmed_by_supervisor IS NOT NULL OR si.status = 'AUTO_CONFIRMED')
  LOOP
    -- Count shifts (trust model)
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
  
  -- Count excluded (critical only)
  SELECT COUNT(*) INTO v_excluded_critical
  FROM attendance a
  WHERE a.payroll_period_id = p_period_id
    AND a.validation_status = 'OPERATIONAL_ONLY';
  
  RETURN jsonb_build_object(
    'success', true,
    'work_units_created', v_units_created,
    'excluded_critical', v_excluded_critical,
    'trust_model', 'VALID_FOR_PAYROLL + AUTO_CONFIRMED',
    'note', 'Warnings included, only critical mismatches excluded'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION aggregate_work_units_trust_model IS 
'TRUST MODEL: Includes warnings, auto-confirmed. Excludes only REJECTED + UNRESOLVED_CRITICAL';
