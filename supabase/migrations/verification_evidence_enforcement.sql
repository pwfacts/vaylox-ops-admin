-- ============================================
-- VERIFICATION ENFORCEMENT: EVIDENCE-BASED RESOLUTION
-- Requires proof based on severity before allowing resolution
-- ============================================

-- 1. CHECK RESOLUTION REQUIREMENTS
CREATE OR REPLACE FUNCTION check_task_resolution_requirements(
  p_task_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_task attendance_verification_tasks;
  v_requirements TEXT[] := ARRAY[]::TEXT[];
  v_optional TEXT[] := ARRAY[]::TEXT[];
BEGIN
  -- Get task
  SELECT * INTO v_task
  FROM attendance_verification_tasks
  WHERE id = p_task_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'error', 'TASK_NOT_FOUND'
    );
  END IF;
  
  -- Base requirement: resolution note
  v_requirements := array_append(v_requirements, 'resolution_note');
  
  -- Trust score based requirements
  IF v_task.trust_score < 30 THEN
    -- Very low trust: photo mandatory
    v_requirements := array_append(v_requirements, 'photo_reference');
    v_optional := ARRAY['location', 'device_match'];
    
  ELSIF v_task.trust_score < 50 THEN
    -- Low trust: at least one evidence
    v_requirements := array_append(v_requirements, 'at_least_one_evidence');
    v_optional := ARRAY['location', 'device_match', 'photo_reference'];
  END IF;
  
  -- Reason code specific requirements
  IF v_task.reason_code = 'TIME_DRIFT' THEN
    v_requirements := array_append(v_requirements, 'corrected_timestamp');
  END IF;
  
  IF v_task.reason_code = 'OFFLINE_EXCESS' THEN
    v_requirements := array_append(v_requirements, 'supervisor_remark_min_15_chars');
  END IF;
  
  RETURN jsonb_build_object(
    'task_id', p_task_id,
    'trust_score', v_task.trust_score,
    'reason_code', v_task.reason_code,
    'required', v_requirements,
    'optional', v_optional,
    'min_note_length', CASE 
      WHEN v_task.reason_code = 'OFFLINE_EXCESS' THEN 15
      ELSE 1
    END
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION check_task_resolution_requirements IS 
'Check evidence requirements for resolving a verification task based on trust score and reason';

-- 2. VALIDATE EVIDENCE
CREATE OR REPLACE FUNCTION validate_resolution_evidence(
  p_task_id UUID,
  p_note TEXT,
  p_evidence JSONB
)
RETURNS JSONB AS $$
DECLARE
  v_task attendance_verification_tasks;
  v_requirements JSONB;
  v_missing TEXT[] := ARRAY[]::TEXT[];
  v_evidence_count INTEGER := 0;
  v_evidence_status TEXT;
BEGIN
  -- Get task
  SELECT * INTO v_task
  FROM attendance_verification_tasks
  WHERE id = p_task_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'valid', false,
      'error', 'TASK_NOT_FOUND'
    );
  END IF;
  
  -- Get requirements
  v_requirements := check_task_resolution_requirements(p_task_id);
  
  -- Check resolution note
  IF p_note IS NULL OR LENGTH(TRIM(p_note)) < 1 THEN
    v_missing := array_append(v_missing, 'resolution_note');
  END IF;
  
  -- Check minimum note length for OFFLINE_EXCESS
  IF v_task.reason_code = 'OFFLINE_EXCESS' AND LENGTH(TRIM(p_note)) < 15 THEN
    RETURN jsonb_build_object(
      'valid', false,
      'error', 'SUPERVISOR_REMARK_TOO_SHORT',
      'message', 'Supervisor remark must be at least 15 characters for offline excess cases',
      'required_length', 15,
      'provided_length', LENGTH(TRIM(p_note))
    );
  END IF;
  
  -- Check trust score based requirements
  IF v_task.trust_score < 30 THEN
    -- Photo mandatory
    IF p_evidence IS NULL OR p_evidence->>'photo_reference' IS NULL THEN
      v_missing := array_append(v_missing, 'photo_reference');
    END IF;
    
  ELSIF v_task.trust_score < 50 THEN
    -- At least one evidence required
    IF p_evidence IS NOT NULL THEN
      IF p_evidence->>'location' IS NOT NULL THEN v_evidence_count := v_evidence_count + 1; END IF;
      IF p_evidence->>'device_match' IS NOT NULL THEN v_evidence_count := v_evidence_count + 1; END IF;
      IF p_evidence->>'photo_reference' IS NOT NULL THEN v_evidence_count := v_evidence_count + 1; END IF;
    END IF;
    
    IF v_evidence_count = 0 THEN
      RETURN jsonb_build_object(
        'valid', false,
        'error', 'INSUFFICIENT_EVIDENCE',
        'message', 'At least one evidence required: location, device_match, or photo_reference',
        'trust_score', v_task.trust_score
      );
    END IF;
  END IF;
  
  -- Check TIME_DRIFT requirement
  IF v_task.reason_code = 'TIME_DRIFT' THEN
    IF p_evidence IS NULL OR p_evidence->>'corrected_timestamp' IS NULL THEN
      v_missing := array_append(v_missing, 'corrected_timestamp');
    END IF;
  END IF;
  
  -- Determine evidence status
  IF array_length(v_missing, 1) > 0 THEN
    v_evidence_status := 'INSUFFICIENT';
  ELSIF v_evidence_count >= 2 OR (p_evidence IS NOT NULL AND jsonb_array_length(jsonb_object_keys(p_evidence)) >= 3) THEN
    v_evidence_status := 'COMPLETE';
  ELSE
    v_evidence_status := 'PARTIAL';
  END IF;
  
  -- Return validation result
  IF array_length(v_missing, 1) > 0 THEN
    RETURN jsonb_build_object(
      'valid', false,
      'error', 'MISSING_REQUIRED_EVIDENCE',
      'missing', v_missing,
      'requirements', v_requirements
    );
  ELSE
    RETURN jsonb_build_object(
      'valid', true,
      'evidence_status', v_evidence_status,
      'evidence_count', v_evidence_count
    );
  END IF;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION validate_resolution_evidence IS 
'Validate that resolution has required evidence based on trust score and reason code';

-- 3. UPDATE RESOLVE VERIFICATION TASK
CREATE OR REPLACE FUNCTION resolve_verification_task(
  p_task_id UUID,
  p_action TEXT,
  p_note TEXT,
  p_resolved_by UUID,
  p_evidence JSONB DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_task attendance_verification_tasks;
  v_validation JSONB;
  v_resolver_role TEXT;
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
    
    -- Update task with evidence
    UPDATE attendance_verification_tasks
    SET 
      status = p_action,
      resolved_at = NOW(),
      resolved_by = p_resolved_by,
      resolution_note = p_note,
      resolution_evidence = COALESCE(p_evidence, '{}'::JSONB),
      evidence_status = v_validation->>'evidence_status',
      verified_by_role = v_resolver_role
    WHERE id = p_task_id;
    
  ELSE
    -- REJECTED: no evidence required
    UPDATE attendance_verification_tasks
    SET 
      status = p_action,
      resolved_at = NOW(),
      resolved_by = p_resolved_by,
      resolution_note = p_note,
      verified_by_role = v_resolver_role
    WHERE id = p_task_id;
  END IF;
  
  RETURN jsonb_build_object(
    'success', true,
    'task_id', p_task_id,
    'action', p_action,
    'attendance_id', v_task.attendance_id,
    'evidence_status', v_validation->>'evidence_status'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION resolve_verification_task IS 
'Resolve verification task with evidence validation - enforces proof requirements';

-- 4. HELPER: GET EVIDENCE REQUIREMENTS FOR UI
CREATE OR REPLACE FUNCTION get_evidence_requirements_summary(
  p_org_id UUID,
  p_trust_score_min INTEGER DEFAULT 0,
  p_trust_score_max INTEGER DEFAULT 100
)
RETURNS TABLE (
  trust_range TEXT,
  required_evidence TEXT[],
  optional_evidence TEXT[],
  example_case TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT 
    '50-100'::TEXT,
    ARRAY['resolution_note']::TEXT[],
    ARRAY[]::TEXT[],
    'Simple case - note only'::TEXT
  WHERE p_trust_score_min <= 50 AND p_trust_score_max >= 50
  
  UNION ALL
  
  SELECT 
    '30-49'::TEXT,
    ARRAY['resolution_note', 'at_least_one_evidence']::TEXT[],
    ARRAY['location', 'device_match', 'photo_reference']::TEXT[],
    'Moderate case - note + one evidence'::TEXT
  WHERE p_trust_score_min <= 30 AND p_trust_score_max >= 30
  
  UNION ALL
  
  SELECT 
    '0-29'::TEXT,
    ARRAY['resolution_note', 'photo_reference']::TEXT[],
    ARRAY['location', 'device_match']::TEXT[],
    'Severe case - photo mandatory'::TEXT
  WHERE p_trust_score_min <= 29;
END;
$$ LANGUAGE plpgsql STABLE;

COMMENT ON FUNCTION get_evidence_requirements_summary IS 
'Get summary of evidence requirements by trust score range for UI display';
