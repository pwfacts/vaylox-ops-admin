-- ============================================
-- REPLACEMENT-AWARE SHIFT OWNERSHIP
-- shift_instances = single source of truth
-- ============================================

-- Goal: Only current shift owner can produce payable attendance
-- Previous owners blocked after replacement

-- ========================================
-- 1. ADD OWNERSHIP COLUMNS TO SHIFT_INSTANCES
-- ========================================

ALTER TABLE shift_instances
  ADD COLUMN IF NOT EXISTS current_owner_profile_id UUID REFERENCES workforce_profiles(id),
  ADD COLUMN IF NOT EXISTS previous_owner_profile_id UUID REFERENCES workforce_profiles(id),
  ADD COLUMN IF NOT EXISTS ownership_transferred_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS ownership_transferred_by UUID REFERENCES users(id);

-- Backfill current_owner from existing assigned_profile_id
UPDATE shift_instances
SET current_owner_profile_id = assigned_profile_id
WHERE current_owner_profile_id IS NULL 
  AND assigned_profile_id IS NOT NULL;

CREATE INDEX idx_shift_instances_current_owner ON shift_instances(current_owner_profile_id);
CREATE INDEX idx_shift_instances_previous_owner ON shift_instances(previous_owner_profile_id);

COMMENT ON COLUMN shift_instances.current_owner_profile_id IS 
'Current shift owner - ONLY this profile can create payable attendance';

COMMENT ON COLUMN shift_instances.previous_owner_profile_id IS 
'Previous owner before replacement - blocked from creating payable attendance';

-- ========================================
-- 2. SHIFT OWNERSHIP HISTORY TABLE
-- ========================================

CREATE TABLE IF NOT EXISTS shift_ownership_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Shift reference
  shift_instance_id UUID NOT NULL REFERENCES shift_instances(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES organizations(id),
  unit_id UUID NOT NULL REFERENCES units(id),
  shift_date DATE NOT NULL,
  
  -- Ownership change
  from_profile_id UUID REFERENCES workforce_profiles(id),
  to_profile_id UUID NOT NULL REFERENCES workforce_profiles(id),
  
  -- Change details
  change_reason TEXT CHECK (change_reason IN (
    'INITIAL_ASSIGNMENT',
    'GUARD_REPLACEMENT',
    'ADMINISTRATIVE_CHANGE',
    'AUTO_ASSIGNMENT',
    'EMERGENCY_REPLACEMENT'
  )),
  change_note TEXT,
  
  -- Metadata
  changed_by UUID REFERENCES users(id),
  changed_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Context
  previous_status TEXT,
  new_status TEXT
);

CREATE INDEX idx_shift_ownership_history_shift ON shift_ownership_history(shift_instance_id);
CREATE INDEX idx_shift_ownership_history_from ON shift_ownership_history(from_profile_id);
CREATE INDEX idx_shift_ownership_history_to ON shift_ownership_history(to_profile_id);
CREATE INDEX idx_shift_ownership_history_date ON shift_ownership_history(shift_date);

COMMENT ON TABLE shift_ownership_history IS 
'Audit trail for all shift ownership transfers - tracks replacements';

-- ========================================
-- 3. TRANSFER SHIFT OWNERSHIP FUNCTION
-- ========================================

CREATE OR REPLACE FUNCTION transfer_shift_ownership(
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
  v_new_guard_id UUID;
BEGIN
  -- Get shift instance
  SELECT * INTO v_shift FROM shift_instances WHERE id = p_shift_instance_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'SHIFT_NOT_FOUND');
  END IF;
  
  -- Get current owner
  v_old_profile_id := v_shift.current_owner_profile_id;
  
  -- Cannot transfer if already owned by same profile
  IF v_old_profile_id = p_new_profile_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'ALREADY_OWNED',
      'message', 'Shift already owned by this profile'
    );
  END IF;
  
  -- Get new guard ID
  SELECT linked_auth_user INTO v_new_guard_id
  FROM workforce_profiles
  WHERE id = p_new_profile_id;
  
  -- ========================================
  -- UPDATE SHIFT INSTANCE
  -- ========================================
  
  UPDATE shift_instances
  SET
    previous_owner_profile_id = v_old_profile_id,
    current_owner_profile_id = p_new_profile_id,
    assigned_profile_id = p_new_profile_id,  -- Keep in sync
    status = 'REASSIGNED',
    ownership_transferred_at = NOW(),
    ownership_transferred_by = p_changed_by,
    updated_at = NOW()
  WHERE id = p_shift_instance_id;
  
  -- ========================================
  -- LOG OWNERSHIP CHANGE
  -- ========================================
  
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
  
  -- ========================================
  -- INVALIDATE OLD OWNER'S ATTENDANCE (if exists)
  -- ========================================
  
  -- Mark any existing attendance from old owner as OPERATIONAL_ONLY
  UPDATE attendance
  SET 
    validation_status = 'OPERATIONAL_ONLY',
    updated_at = NOW()
  WHERE shift_instance_id = p_shift_instance_id
    AND guard_id = (SELECT linked_auth_user FROM workforce_profiles WHERE id = v_old_profile_id)
    AND validation_status = 'VALID_FOR_PAYROLL';
  
  -- Create exception for invalidated attendance
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
    'OWNERSHIP_INVALID',
    'Shift ownership transferred - previous owner attendance invalidated',
    jsonb_build_object(
      'old_owner_profile_id', v_old_profile_id,
      'new_owner_profile_id', p_new_profile_id,
      'transfer_reason', p_change_reason,
      'transferred_by', p_changed_by
    ),
    a.attendance_date,
    a.shift_start_date,
    'RESOLVED',
    'SYSTEM_AUTO',
    'ADMIN'
  FROM attendance a
  WHERE a.shift_instance_id = p_shift_instance_id
    AND a.guard_id = (SELECT linked_auth_user FROM workforce_profiles WHERE id = v_old_profile_id)
    AND a.validation_status = 'OPERATIONAL_ONLY'
  ON CONFLICT DO NOTHING;
  
  RETURN jsonb_build_object(
    'success', true,
    'shift_instance_id', p_shift_instance_id,
    'old_owner_profile_id', v_old_profile_id,
    'new_owner_profile_id', p_new_profile_id,
    'status', 'REASSIGNED',
    'transferred_at', NOW()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION transfer_shift_ownership IS 
'Transfers shift ownership - invalidates previous owner attendance, only new owner can create payable';

-- ========================================
-- 4. UPDATE ATTENDANCE IDENTITY KEY
-- ========================================

-- Drop old identity key
ALTER TABLE attendance DROP COLUMN IF EXISTS attendance_identity_key;

-- Add new shift-based identity key
ALTER TABLE attendance
  ADD COLUMN IF NOT EXISTS attendance_identity_key TEXT GENERATED ALWAYS AS (
    organization_id::text || '|' || 
    COALESCE(shift_instance_id::text, 'MANUAL|' || guard_id::text || '|' || shift_start_date::text)
  ) STORED;

-- Drop old unique index
DROP INDEX IF EXISTS idx_attendance_identity_unique;

-- Create new unique index (shift-based, not guard-based)
CREATE UNIQUE INDEX idx_attendance_identity_unique_v2 
  ON attendance(attendance_identity_key)
  WHERE validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED');

CREATE INDEX idx_attendance_identity_key_v2 ON attendance(attendance_identity_key);

COMMENT ON COLUMN attendance.attendance_identity_key IS 
'Unique business key: org|shift_instance - ONE attendance per shift (not per guard)';

-- ========================================
-- 5. OWNERSHIP-AWARE UPSERT ATTENDANCE
-- ========================================

CREATE OR REPLACE FUNCTION upsert_attendance_v2(
  p_organization_id UUID,
  p_guard_id UUID,
  p_profile_id UUID,  -- NEW: Profile attempting to create attendance
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
  v_existing_priority INTEGER;
  v_new_priority INTEGER;
  v_should_update BOOLEAN;
  v_fields_updated TEXT[] := ARRAY[]::TEXT[];
  v_result_action TEXT;
  v_attendance_id UUID;
  v_is_current_owner BOOLEAN;
BEGIN
  -- ========================================
  -- OWNERSHIP VALIDATION
  -- ========================================
  
  IF p_shift_instance_id IS NOT NULL THEN
    -- Get shift instance
    SELECT * INTO v_shift FROM shift_instances WHERE id = p_shift_instance_id;
    
    IF NOT FOUND THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', 'SHIFT_NOT_FOUND',
        'message', 'Shift instance not found'
      );
    END IF;
    
    -- Check ownership
    v_is_current_owner := (v_shift.current_owner_profile_id = p_profile_id);
    
    IF NOT v_is_current_owner THEN
      -- Profile is NOT current owner - create non-payable attendance
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
        'OPERATIONAL_ONLY',  -- Not payable
        p_created_by_user_id
      )
      RETURNING id INTO v_attendance_id;
      
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
        v_attendance_id,
        p_organization_id,
        p_guard_id,
        p_shift_instance_id,
        'OWNERSHIP_INVALID',
        format('Guard is not current shift owner - shift owned by profile %s', v_shift.current_owner_profile_id),
        jsonb_build_object(
          'attempting_profile_id', p_profile_id,
          'current_owner_profile_id', v_shift.current_owner_profile_id,
          'previous_owner_profile_id', v_shift.previous_owner_profile_id,
          'is_previous_owner', v_shift.previous_owner_profile_id = p_profile_id
        ),
        p_attendance_date,
        p_shift_start_date,
        'PENDING'
      );
      
      -- Log as owner mismatch
      INSERT INTO attendance_merge_logs (
        target_attendance_id,
        attendance_identity_key,
        source_verification_mode,
        source_check_in_time,
        merge_reason,
        priority_comparison,
        target_updated,
        organization_id,
        guard_id,
        shift_start_date
      )
      VALUES (
        v_attendance_id,
        p_organization_id::text || '|' || p_shift_instance_id::text,
        p_verification_mode,
        p_check_in_time,
        'OWNER_MISMATCH - Not current shift owner',
        format('Profile %s attempted, but shift owned by %s', p_profile_id, v_shift.current_owner_profile_id),
        false,
        p_organization_id,
        p_guard_id,
        p_shift_start_date
      );
      
      RETURN jsonb_build_object(
        'success', true,
        'action', 'OWNERSHIP_INVALID',
        'attendance_id', v_attendance_id,
        'validation_status', 'OPERATIONAL_ONLY',
        'is_payable', false,
        'reason', 'Not current shift owner',
        'current_owner_profile_id', v_shift.current_owner_profile_id
      );
    END IF;
  END IF;
  
  -- ========================================
  -- IDENTITY KEY CALCULATION
  -- ========================================
  
  v_identity_key := p_organization_id::text || '|' || 
                    COALESCE(p_shift_instance_id::text, 'MANUAL|' || p_guard_id::text || '|' || p_shift_start_date::text);
  
  -- ========================================
  -- CHECK FOR EXISTING VALID ATTENDANCE
  -- ========================================
  
  SELECT * INTO v_existing_attendance
  FROM attendance
  WHERE attendance_identity_key = v_identity_key
    AND validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
  LIMIT 1;
  
  -- ========================================
  -- CASE 1: NO EXISTING ATTENDANCE - INSERT
  -- ========================================
  
  IF v_existing_attendance IS NULL THEN
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
      'VALID_FOR_PAYROLL',
      p_created_by_user_id
    )
    RETURNING id INTO v_attendance_id;
    
    RETURN jsonb_build_object(
      'action', 'INSERTED',
      'attendance_id', v_attendance_id,
      'identity_key', v_identity_key,
      'is_duplicate', false,
      'is_payable', true
    );
  END IF;
  
  -- ========================================
  -- CASE 2: EXISTING ATTENDANCE - MERGE LOGIC
  -- ========================================
  
  -- Get priorities
  v_existing_priority := get_verification_mode_priority(v_existing_attendance.verification_mode);
  v_new_priority := get_verification_mode_priority(p_verification_mode);
  
  v_should_update := false;
  
  -- Priority-based update decision
  IF v_new_priority > v_existing_priority THEN
    -- New source is higher priority - UPDATE
    v_should_update := true;
    
    -- Update check-in time
    IF p_check_in_time IS NOT NULL AND p_check_in_time != v_existing_attendance.check_in_time THEN
      UPDATE attendance SET check_in_time = p_check_in_time WHERE id = v_existing_attendance.id;
      v_fields_updated := array_append(v_fields_updated, 'check_in_time');
    END IF;
    
    -- Update verification mode
    UPDATE attendance SET verification_mode = p_verification_mode WHERE id = v_existing_attendance.id;
    v_fields_updated := array_append(v_fields_updated, 'verification_mode');
    
    -- Update location
    IF p_location_coords IS NOT NULL THEN
      UPDATE attendance SET location_coords = p_location_coords WHERE id = v_existing_attendance.id;
      v_fields_updated := array_append(v_fields_updated, 'location_coords');
    END IF;
    
    -- Update face verification
    IF p_face_verified = true AND v_existing_attendance.face_verified = false THEN
      UPDATE attendance SET face_verified = p_face_verified WHERE id = v_existing_attendance.id;
      v_fields_updated := array_append(v_fields_updated, 'face_verified');
    END IF;
    
    v_result_action := 'MERGED_UPDATED';
    
  ELSIF v_new_priority = v_existing_priority THEN
    -- Same priority - keep earliest check-in time
    IF p_check_in_time IS NOT NULL AND 
       (v_existing_attendance.check_in_time IS NULL OR p_check_in_time < v_existing_attendance.check_in_time) THEN
      UPDATE attendance SET check_in_time = p_check_in_time WHERE id = v_existing_attendance.id;
      v_fields_updated := array_append(v_fields_updated, 'check_in_time');
      v_should_update := true;
    END IF;
    
    v_result_action := CASE WHEN v_should_update THEN 'MERGED_UPDATED' ELSE 'MERGED_IGNORED' END;
    
  ELSE
    -- New priority lower - ignore
    v_result_action := 'MERGED_IGNORED';
  END IF;
  
  -- Log merge
  INSERT INTO attendance_merge_logs (
    target_attendance_id,
    attendance_identity_key,
    source_verification_mode,
    source_check_in_time,
    source_location_coords,
    source_metadata,
    merge_reason,
    priority_comparison,
    target_updated,
    fields_updated,
    merged_by_user_id,
    organization_id,
    guard_id,
    shift_start_date
  )
  VALUES (
    v_existing_attendance.id,
    v_identity_key,
    p_verification_mode,
    p_check_in_time,
    p_location_coords,
    p_metadata,
    format('Duplicate attendance attempt - %s', v_result_action),
    format('%s (%s) vs %s (%s)', 
      p_verification_mode, v_new_priority,
      v_existing_attendance.verification_mode, v_existing_priority
    ),
    v_should_update,
    v_fields_updated,
    p_created_by_user_id,
    p_organization_id,
    p_guard_id,
    p_shift_start_date
  );
  
  RETURN jsonb_build_object(
    'action', v_result_action,
    'attendance_id', v_existing_attendance.id,
    'identity_key', v_identity_key,
    'is_duplicate', true,
    'is_payable', true,
    'existing_priority', v_existing_priority,
    'new_priority', v_new_priority,
    'target_updated', v_should_update,
    'fields_updated', v_fields_updated
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION upsert_attendance_v2 IS 
'OWNERSHIP-AWARE UPSERT: Only current shift owner can create payable attendance';

-- ========================================
-- 6. SHIFT-BASED PAYROLL AGGREGATION
-- ========================================

CREATE OR REPLACE FUNCTION aggregate_work_units_by_period_shift_based(p_period_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_period payroll_periods;
  v_guard_id UUID;
  v_present_count DECIMAL;
  v_auto_present_count DECIMAL;
  v_replacement_count DECIMAL;
  v_ot_count DECIMAL;
  v_shift_ids UUID[];
  v_units_created INTEGER := 0;
  v_excluded_count INTEGER := 0;
BEGIN
  -- Get period
  SELECT * INTO v_period FROM payroll_periods WHERE id = p_period_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'PERIOD_NOT_FOUND');
  END IF;
  
  -- Loop through each guard
  FOR v_guard_id IN
    SELECT DISTINCT a.guard_id
    FROM attendance a
    WHERE a.payroll_period_id = p_period_id
      AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
      AND EXISTS (
        SELECT 1 FROM shift_instances si
        WHERE si.id = a.shift_instance_id
          AND si.status IN ('CONFIRMED', 'AUTO_CONFIRMED', 'PAYROLL_LOCKED')
      )
  LOOP
    -- Count DISTINCT shift_instance_id (not attendance_id)
    SELECT COUNT(DISTINCT si.id) INTO v_present_count
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    WHERE a.payroll_period_id = p_period_id
      AND a.guard_id = v_guard_id
      AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
      AND si.status = 'CONFIRMED'
      AND si.auto_confirm_reason IS NULL;
    
    -- Auto-present (DISTINCT shifts)
    SELECT COUNT(DISTINCT si.id) INTO v_auto_present_count
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    WHERE a.payroll_period_id = p_period_id
      AND a.guard_id = v_guard_id
      AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
      AND si.status = 'AUTO_CONFIRMED';
    
    -- Replacement (DISTINCT shifts)
    SELECT COUNT(DISTINCT si.id) INTO v_replacement_count
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    WHERE a.payroll_period_id = p_period_id
      AND a.guard_id = v_guard_id
      AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
      AND si.previous_owner_profile_id IS NOT NULL
      AND si.status IN ('CONFIRMED', 'AUTO_CONFIRMED', 'PAYROLL_LOCKED');
    
    v_ot_count := 0;
    
    -- Collect shift IDs (DISTINCT)
    SELECT array_agg(DISTINCT si.id) INTO v_shift_ids
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    WHERE a.payroll_period_id = p_period_id
      AND a.guard_id = v_guard_id
      AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
      AND si.status IN ('CONFIRMED', 'AUTO_CONFIRMED', 'PAYROLL_LOCKED');
    
    -- Insert work unit
    INSERT INTO payroll_work_units (
      payroll_period_id,
      guard_id,
      organization_id,
      present_days,
      auto_present_days,
      replacement_days,
      ot_days,
      included_shift_instances,
      aggregation_status
    )
    VALUES (
      p_period_id,
      v_guard_id,
      v_period.organization_id,
      COALESCE(v_present_count, 0),
      COALESCE(v_auto_present_count, 0),
      COALESCE(v_replacement_count, 0),
      COALESCE(v_ot_count, 0),
      v_shift_ids,
      'DRAFT'
    )
    ON CONFLICT (payroll_period_id, guard_id)
    DO UPDATE SET
      present_days = EXCLUDED.present_days,
      auto_present_days = EXCLUDED.auto_present_days,
      replacement_days = EXCLUDED.replacement_days,
      ot_days = EXCLUDED.ot_days,
      included_shift_instances = EXCLUDED.included_shift_instances,
      aggregated_at = NOW(),
      updated_at = NOW();
    
    v_units_created := v_units_created + 1;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'work_units_created', v_units_created,
    'period_id', p_period_id,
    'aggregation_method', 'SHIFT_BASED'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION aggregate_work_units_by_period_shift_based IS 
'SHIFT-BASED AGGREGATION: Counts DISTINCT shift_instance_id (not guard attendance)';
