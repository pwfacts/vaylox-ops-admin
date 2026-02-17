-- ============================================
-- EVIDENCE AUTHENTICITY VALIDATION
-- Verify photo evidence is real and not manipulated/reused
-- ============================================

-- 1. VALIDATE PHOTO AUTHENTICITY
CREATE OR REPLACE FUNCTION validate_photo_authenticity(
  p_task_id UUID,
  p_photo_metadata JSONB
)
RETURNS JSONB AS $$
DECLARE
  v_task attendance_verification_tasks;
  v_attendance attendance;
  v_unit units;
  v_shift_start TIMESTAMPTZ;
  v_shift_end TIMESTAMPTZ;
  v_captured_at TIMESTAMPTZ;
  v_captured_lat DECIMAL;
  v_captured_lng DECIMAL;
  v_device_fingerprint TEXT;
  v_file_hash TEXT;
  
  v_validity_status TEXT := 'VALID';
  v_validation_flags TEXT[] := ARRAY[]::TEXT[];
  
  v_time_valid BOOLEAN;
  v_location_valid BOOLEAN;
  v_device_valid BOOLEAN;
  v_reuse_valid BOOLEAN;
  
  v_distance_km DECIMAL;
  v_unit_radius_km DECIMAL;
  v_reuse_count INTEGER;
BEGIN
  -- Get task and attendance
  SELECT * INTO v_task
  FROM attendance_verification_tasks
  WHERE id = p_task_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('error', 'TASK_NOT_FOUND');
  END IF;
  
  SELECT * INTO v_attendance
  FROM attendance
  WHERE id = v_task.attendance_id;
  
  -- Get unit
  SELECT * INTO v_unit
  FROM units
  WHERE id = v_attendance.unit_id;
  
  -- Extract metadata
  v_captured_at := (p_photo_metadata->>'captured_at')::TIMESTAMPTZ;
  v_captured_lat := (p_photo_metadata->>'captured_lat')::DECIMAL;
  v_captured_lng := (p_photo_metadata->>'captured_lng')::DECIMAL;
  v_device_fingerprint := p_photo_metadata->>'device_fingerprint';
  v_file_hash := p_photo_metadata->>'file_hash';
  
  -- Determine shift times (assuming 8-hour shifts)
  CASE v_attendance.shift
    WHEN 'morning' THEN
      v_shift_start := v_attendance.attendance_date + INTERVAL '8 hours';
      v_shift_end := v_attendance.attendance_date + INTERVAL '16 hours';
    WHEN 'afternoon' THEN
      v_shift_start := v_attendance.attendance_date + INTERVAL '16 hours';
      v_shift_end := v_attendance.attendance_date + INTERVAL '24 hours';
    WHEN 'night' THEN
      v_shift_start := v_attendance.attendance_date + INTERVAL '0 hours';
      v_shift_end := v_attendance.attendance_date + INTERVAL '8 hours';
    ELSE
      v_shift_start := v_attendance.attendance_date + INTERVAL '8 hours';
      v_shift_end := v_attendance.attendance_date + INTERVAL '16 hours';
  END CASE;
  
  -- ========================================
  -- TIME VALIDATION
  -- ========================================
  v_time_valid := v_captured_at >= (v_shift_start - INTERVAL '90 minutes')
    AND v_captured_at <= (v_shift_end + INTERVAL '90 minutes');
  
  IF NOT v_time_valid THEN
    v_validation_flags := array_append(v_validation_flags, 'TIME_OUT_OF_RANGE');
    v_validity_status := 'INVALID';
  END IF;
  
  -- ========================================
  -- LOCATION VALIDATION
  -- ========================================
  IF v_captured_lat IS NOT NULL AND v_captured_lng IS NOT NULL AND v_unit.latitude IS NOT NULL THEN
    -- Calculate distance using Haversine formula
    v_distance_km := (
      6371 * acos(
        cos(radians(v_unit.latitude)) * cos(radians(v_captured_lat)) *
        cos(radians(v_captured_lng) - radians(v_unit.longitude)) +
        sin(radians(v_unit.latitude)) * sin(radians(v_captured_lat))
      )
    );
    
    v_unit_radius_km := COALESCE(v_unit.radius, 0.5); -- Default 500m
    
    v_location_valid := v_distance_km <= v_unit_radius_km;
    
    IF NOT v_location_valid THEN
      v_validation_flags := array_append(v_validation_flags, 'LOCATION_OUT_OF_RANGE');
      IF v_validity_status != 'INVALID' THEN
        v_validity_status := 'SUSPICIOUS';
      END IF;
    END IF;
  ELSE
    v_validation_flags := array_append(v_validation_flags, 'NO_LOCATION_DATA');
    IF v_validity_status = 'VALID' THEN
      v_validity_status := 'SUSPICIOUS';
    END IF;
  END IF;
  
  -- ========================================
  -- DEVICE VALIDATION
  -- ========================================
  IF v_device_fingerprint IS NOT NULL THEN
    -- Check if device is trusted for this guard
    SELECT EXISTS (
      SELECT 1 FROM workforce_trusted_devices
      WHERE profile_id = (
        SELECT id FROM workforce_profiles
        WHERE linked_auth_user = (
          SELECT id FROM guards WHERE id = v_attendance.guard_id LIMIT 1
        )
      )
      AND device_fingerprint = v_device_fingerprint
      AND status = 'active'
    ) INTO v_device_valid;
    
    IF NOT v_device_valid THEN
      v_validation_flags := array_append(v_validation_flags, 'UNTRUSTED_DEVICE');
      IF v_validity_status = 'VALID' THEN
        v_validity_status := 'SUSPICIOUS';
      END IF;
    END IF;
  ELSE
    v_validation_flags := array_append(v_validation_flags, 'NO_DEVICE_DATA');
  END IF;
  
  -- ========================================
  -- REUSE CHECK
  -- ========================================
  IF v_file_hash IS NOT NULL THEN
    SELECT COUNT(*) INTO v_reuse_count
    FROM evidence_media_metadata
    WHERE file_hash = v_file_hash
      AND attendance_id != v_attendance.id;
    
    v_reuse_valid := v_reuse_count = 0;
    
    IF NOT v_reuse_valid THEN
      v_validation_flags := array_append(v_validation_flags, 'PHOTO_REUSED');
      v_validity_status := 'INVALID';
    END IF;
  ELSE
    v_validation_flags := array_append(v_validation_flags, 'NO_FILE_HASH');
  END IF;
  
  -- ========================================
  -- STORE VALIDATION RESULT
  -- ========================================
  INSERT INTO evidence_media_metadata (
    task_id,
    attendance_id,
    captured_at,
    captured_lat,
    captured_lng,
    device_fingerprint,
    file_hash,
    validity_status,
    validation_flags,
    time_validation,
    location_validation,
    device_validation,
    reuse_validation
  )
  VALUES (
    p_task_id,
    v_attendance.id,
    v_captured_at,
    v_captured_lat,
    v_captured_lng,
    v_device_fingerprint,
    v_file_hash,
    v_validity_status,
    v_validation_flags,
    jsonb_build_object(
      'valid', v_time_valid,
      'captured_at', v_captured_at,
      'shift_start', v_shift_start,
      'shift_end', v_shift_end,
      'within_window', v_time_valid
    ),
    jsonb_build_object(
      'valid', v_location_valid,
      'distance_km', v_distance_km,
      'allowed_radius_km', v_unit_radius_km,
      'captured_location', jsonb_build_object('lat', v_captured_lat, 'lng', v_captured_lng),
      'unit_location', jsonb_build_object('lat', v_unit.latitude, 'lng', v_unit.longitude)
    ),
    jsonb_build_object(
      'valid', v_device_valid,
      'device_fingerprint', v_device_fingerprint,
      'is_trusted', v_device_valid
    ),
    jsonb_build_object(
      'valid', v_reuse_valid,
      'file_hash', v_file_hash,
      'reuse_count', v_reuse_count
    )
  );
  
  RETURN jsonb_build_object(
    'validity_status', v_validity_status,
    'validation_flags', v_validation_flags,
    'time_valid', v_time_valid,
    'location_valid', COALESCE(v_location_valid, NULL),
    'device_valid', COALESCE(v_device_valid, NULL),
    'reuse_valid', COALESCE(v_reuse_valid, true),
    'requires_override', v_validity_status = 'INVALID'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION validate_photo_authenticity IS 
'Validate photo evidence authenticity - time, location, device, reuse checks';

-- 2. UPDATE RESOLVE VERIFICATION TASK WITH PHOTO VALIDATION
CREATE OR REPLACE FUNCTION resolve_verification_task(
  p_task_id UUID,
  p_action TEXT,
  p_note TEXT,
  p_resolved_by UUID,
  p_evidence JSONB DEFAULT NULL,
  p_photo_metadata JSONB DEFAULT NULL,
  p_override_reason TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_task attendance_verification_tasks;
  v_validation JSONB;
  v_photo_validation JSONB;
  v_resolver_role TEXT;
  v_decision_type TEXT := 'AUTOMATIC';
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
  
  -- Get resolver role
  SELECT ou.role INTO v_resolver_role
  FROM organization_users ou
  WHERE ou.user_id = p_resolved_by
    AND ou.organization_id = v_task.organization_id
  LIMIT 1;
  
  -- Validate evidence for VERIFIED/JUSTIFIED actions
  IF p_action IN ('VERIFIED', 'JUSTIFIED') THEN
    v_validation := validate_resolution_evidence(p_task_id, p_note, p_evidence);
    
    IF v_validation->>'valid' != 'true' THEN
      RETURN jsonb_build_object(
        'success', false,
        'error', v_validation->>'error',
        'message', v_validation->>'message',
        'missing', v_validation->'missing',
        'requirements', v_validation->'requirements'
      );
    END IF;
    
    -- Validate photo authenticity if photo provided
    IF p_evidence IS NOT NULL AND p_evidence->>'photo_reference' IS NOT NULL THEN
      IF p_photo_metadata IS NOT NULL THEN
        v_photo_validation := validate_photo_authenticity(p_task_id, p_photo_metadata);
        
        -- If photo is INVALID, require manual override
        IF v_photo_validation->>'validity_status' = 'INVALID' THEN
          IF p_override_reason IS NULL OR LENGTH(TRIM(p_override_reason)) < 20 THEN
            RETURN jsonb_build_object(
              'success', false,
              'error', 'INVALID_PHOTO_REQUIRES_OVERRIDE',
              'message', 'Photo evidence is invalid - manual override required with reason (min 20 chars)',
              'photo_validation', v_photo_validation,
              'override_reason_length', COALESCE(LENGTH(TRIM(p_override_reason)), 0),
              'required_length', 20
            );
          END IF;
          v_decision_type := 'MANUAL_OVERRIDE';
        END IF;
      END IF;
    END IF;
    
    -- Update task with evidence and photo validation
    UPDATE attendance_verification_tasks
    SET 
      status = p_action,
      resolved_at = NOW(),
      resolved_by = p_resolved_by,
      resolution_note = p_note,
      resolution_evidence = COALESCE(p_evidence, '{}'::JSONB),
      evidence_status = v_validation->>'evidence_status',
      verified_by_role = v_resolver_role,
      decision_type = v_decision_type,
      override_reason = p_override_reason
    WHERE id = p_task_id;
    
  ELSE
    -- REJECTED: no evidence required
    UPDATE attendance_verification_tasks
    SET 
      status = p_action,
      resolved_at = NOW(),
      resolved_by = p_resolved_by,
      resolution_note = p_note,
      verified_by_role = v_resolver_role,
      decision_type = 'AUTOMATIC'
    WHERE id = p_task_id;
  END IF;
  
  RETURN jsonb_build_object(
    'success', true,
    'task_id', p_task_id,
    'action', p_action,
    'attendance_id', v_task.attendance_id,
    'evidence_status', v_validation->>'evidence_status',
    'decision_type', v_decision_type,
    'photo_validation', v_photo_validation
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION resolve_verification_task IS 
'Resolve verification task with evidence and photo authenticity validation';

-- 3. GET PHOTO VALIDATION STATUS
CREATE OR REPLACE FUNCTION get_photo_validation_status(p_task_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_metadata evidence_media_metadata;
BEGIN
  SELECT * INTO v_metadata
  FROM evidence_media_metadata
  WHERE task_id = p_task_id
  ORDER BY created_at DESC
  LIMIT 1;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'has_validation', false
    );
  END IF;
  
  RETURN jsonb_build_object(
    'has_validation', true,
    'validity_status', v_metadata.validity_status,
    'validation_flags', v_metadata.validation_flags,
    'time_validation', v_metadata.time_validation,
    'location_validation', v_metadata.location_validation,
    'device_validation', v_metadata.device_validation,
    'reuse_validation', v_metadata.reuse_validation,
    'requires_override', v_metadata.validity_status = 'INVALID'
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION get_photo_validation_status IS 
'Get photo validation status for a verification task';
