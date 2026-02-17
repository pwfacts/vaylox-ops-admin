-- ============================================
-- SESSION STATE MANAGEMENT FUNCTIONS
-- Run these AFTER creating the offline_attendance_queue table
-- ============================================

-- 1. UPDATE SESSION STATE
CREATE OR REPLACE FUNCTION update_session_state(
  p_profile_id UUID,
  p_device_fingerprint TEXT,
  p_new_state TEXT,
  p_reason TEXT DEFAULT NULL,
  p_restricted_until TIMESTAMPTZ DEFAULT NULL,
  p_shift_context JSONB DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_session workforce_session_states;
  v_allowed_ops TEXT[];
  v_blocked_ops TEXT[];
BEGIN
  -- Determine allowed/blocked operations based on state
  CASE p_new_state
    WHEN 'VERIFIED' THEN
      v_allowed_ops := ARRAY['attendance_punch', 'view_duty', 'approvals', 'edits', 'admin_actions'];
      v_blocked_ops := ARRAY[]::TEXT[];
    WHEN 'RESTRICTED' THEN
      v_allowed_ops := ARRAY['attendance_punch', 'view_duty'];
      v_blocked_ops := ARRAY['approvals', 'edits', 'admin_actions', 'coverage_override'];
    WHEN 'RECOVERY' THEN
      v_allowed_ops := ARRAY['attendance_punch', 'view_duty'];
      v_blocked_ops := ARRAY['approvals', 'edits', 'admin_actions', 'real_time_data'];
  END CASE;
  
  -- Upsert session state
  INSERT INTO workforce_session_states (
    profile_id,
    device_fingerprint,
    state,
    state_reason,
    previous_state,
    allowed_operations,
    blocked_operations,
    restricted_until,
    current_shift_id,
    current_unit_id,
    current_shift_end
  )
  VALUES (
    p_profile_id,
    p_device_fingerprint,
    p_new_state,
    p_reason,
    NULL, -- Will be set by UPDATE
    v_allowed_ops,
    v_blocked_ops,
    p_restricted_until,
    (p_shift_context->>'shift_id')::UUID,
    (p_shift_context->>'unit_id')::UUID,
    (p_shift_context->>'shift_end')::TIMESTAMPTZ
  )
  ON CONFLICT (profile_id, device_fingerprint)
  DO UPDATE SET
    previous_state = workforce_session_states.state,
    state = p_new_state,
    state_changed_at = NOW(),
    state_reason = p_reason,
    allowed_operations = v_allowed_ops,
    blocked_operations = v_blocked_ops,
    restricted_until = p_restricted_until,
    current_shift_id = (p_shift_context->>'shift_id')::UUID,
    current_unit_id = (p_shift_context->>'unit_id')::UUID,
    current_shift_end = (p_shift_context->>'shift_end')::TIMESTAMPTZ,
    updated_at = NOW()
  RETURNING * INTO v_session;
  
  RETURN jsonb_build_object(
    'success', true,
    'state', v_session.state,
    'previous_state', v_session.previous_state,
    'allowed_operations', v_session.allowed_operations,
    'blocked_operations', v_session.blocked_operations
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION update_session_state IS 
'Update session state (VERIFIED/RESTRICTED/RECOVERY) with operation permissions';

-- 2. CHECK IF OPERATION IS ALLOWED
CREATE OR REPLACE FUNCTION check_operation_allowed(
  p_profile_id UUID,
  p_device_fingerprint TEXT,
  p_operation TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_session workforce_session_states;
BEGIN
  SELECT * INTO v_session
  FROM workforce_session_states
  WHERE profile_id = p_profile_id
    AND device_fingerprint = p_device_fingerprint
  LIMIT 1;
  
  IF NOT FOUND THEN
    -- No session state = assume VERIFIED
    RETURN jsonb_build_object(
      'allowed', true,
      'state', 'VERIFIED',
      'reason', 'No session restrictions'
    );
  END IF;
  
  -- Check if operation is in allowed list
  IF p_operation = ANY(v_session.allowed_operations) THEN
    RETURN jsonb_build_object(
      'allowed', true,
      'state', v_session.state,
      'reason', format('Operation %s allowed in %s state', p_operation, v_session.state)
    );
  END IF;
  
  -- Check if explicitly blocked
  IF p_operation = ANY(v_session.blocked_operations) THEN
    RETURN jsonb_build_object(
      'allowed', false,
      'state', v_session.state,
      'reason', format('Operation %s blocked in %s state', p_operation, v_session.state),
      'message', CASE v_session.state
        WHEN 'RESTRICTED' THEN 'Please re-authenticate to perform this action'
        WHEN 'RECOVERY' THEN 'This action requires online connection'
        ELSE 'Operation not allowed'
      END
    );
  END IF;
  
  -- Default: allow if not explicitly blocked
  RETURN jsonb_build_object(
    'allowed', true,
    'state', v_session.state,
    'reason', 'Operation not explicitly blocked'
  );
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

COMMENT ON FUNCTION check_operation_allowed IS 
'Check if operation is allowed in current session state';

-- 3. CACHE OFFLINE CREDENTIAL
CREATE OR REPLACE FUNCTION cache_offline_credential(
  p_profile_id UUID,
  p_device_fingerprint TEXT,
  p_pin_hash TEXT,
  p_expiry_days INTEGER DEFAULT 7
)
RETURNS JSONB AS $$
DECLARE
  v_expires_at TIMESTAMPTZ;
BEGIN
  v_expires_at := NOW() + (p_expiry_days || ' days')::INTERVAL;
  
  UPDATE workforce_session_states
  SET 
    offline_credential_hash = p_pin_hash,
    offline_hash_expires_at = v_expires_at,
    offline_verification_count = 0,
    updated_at = NOW()
  WHERE profile_id = p_profile_id
    AND device_fingerprint = p_device_fingerprint;
  
  IF NOT FOUND THEN
    INSERT INTO workforce_session_states (
      profile_id,
      device_fingerprint,
      state,
      offline_credential_hash,
      offline_hash_expires_at
    )
    VALUES (
      p_profile_id,
      p_device_fingerprint,
      'VERIFIED',
      p_pin_hash,
      v_expires_at
    );
  END IF;
  
  RETURN jsonb_build_object(
    'success', true,
    'expires_at', v_expires_at,
    'max_verifications', 10
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION cache_offline_credential IS 
'Cache PIN hash for offline verification';

-- 4. VERIFY OFFLINE CREDENTIAL
CREATE OR REPLACE FUNCTION verify_offline_credential(
  p_profile_id UUID,
  p_device_fingerprint TEXT,
  p_pin TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_session workforce_session_states;
  v_pin_valid BOOLEAN;
BEGIN
  SELECT * INTO v_session
  FROM workforce_session_states
  WHERE profile_id = p_profile_id
    AND device_fingerprint = p_device_fingerprint
  LIMIT 1;
  
  IF NOT FOUND OR v_session.offline_credential_hash IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'NO_CACHED_CREDENTIAL',
      'message', 'No offline credential cached'
    );
  END IF;
  
  -- Check if expired
  IF v_session.offline_hash_expires_at < NOW() THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'CREDENTIAL_EXPIRED',
      'message', 'Cached credential expired - online login required'
    );
  END IF;
  
  -- Check if max verifications exceeded
  IF v_session.offline_verification_count >= v_session.max_offline_verifications THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'MAX_OFFLINE_VERIFICATIONS_EXCEEDED',
      'message', 'Maximum offline verifications reached - online login required'
    );
  END IF;
  
  -- Verify PIN
  v_pin_valid := verify_pin(p_pin, v_session.offline_credential_hash);
  
  IF NOT v_pin_valid THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'INVALID_PIN',
      'message', 'Invalid PIN'
    );
  END IF;
  
  -- Increment verification count
  UPDATE workforce_session_states
  SET 
    offline_verification_count = offline_verification_count + 1,
    last_verified_at = NOW(),
    verification_method = 'offline_pin',
    updated_at = NOW()
  WHERE profile_id = p_profile_id
    AND device_fingerprint = p_device_fingerprint;
  
  RETURN jsonb_build_object(
    'success', true,
    'verification_count', v_session.offline_verification_count + 1,
    'remaining_verifications', v_session.max_offline_verifications - (v_session.offline_verification_count + 1)
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION verify_offline_credential IS 
'Verify PIN against cached hash for offline mode';

-- 5. QUEUE OFFLINE ATTENDANCE
CREATE OR REPLACE FUNCTION queue_offline_attendance(
  p_profile_id UUID,
  p_device_fingerprint TEXT,
  p_attendance_data JSONB,
  p_operation_type TEXT,
  p_offline_pin_verified BOOLEAN DEFAULT false
)
RETURNS JSONB AS $$
DECLARE
  v_queue_id UUID;
BEGIN
  INSERT INTO offline_attendance_queue (
    profile_id,
    device_fingerprint,
    attendance_data,
    operation_type,
    verified_offline,
    offline_pin_hash_match
  )
  VALUES (
    p_profile_id,
    p_device_fingerprint,
    p_attendance_data,
    p_operation_type,
    true,
    p_offline_pin_verified
  )
  RETURNING id INTO v_queue_id;
  
  -- Add to pending sync operations
  UPDATE workforce_session_states
  SET 
    pending_sync_operations = pending_sync_operations || jsonb_build_object(
      'queue_id', v_queue_id,
      'operation', p_operation_type,
      'queued_at', NOW()
    ),
    updated_at = NOW()
  WHERE profile_id = p_profile_id
    AND device_fingerprint = p_device_fingerprint;
  
  RETURN jsonb_build_object(
    'success', true,
    'queue_id', v_queue_id,
    'message', 'Attendance queued for sync'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION queue_offline_attendance IS 
'Queue attendance punch for sync when offline';

-- 6. AUTO-UPGRADE SESSION STATE
CREATE OR REPLACE FUNCTION auto_upgrade_session_state(
  p_profile_id UUID,
  p_device_fingerprint TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_session workforce_session_states;
  v_upgraded BOOLEAN := false;
BEGIN
  SELECT * INTO v_session
  FROM workforce_session_states
  WHERE profile_id = p_profile_id
    AND device_fingerprint = p_device_fingerprint
  LIMIT 1;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('upgraded', false, 'reason', 'No session');
  END IF;
  
  -- RESTRICTED → VERIFIED if past restricted_until
  IF v_session.state = 'RESTRICTED' AND v_session.restricted_until IS NOT NULL THEN
    IF v_session.restricted_until < NOW() THEN
      PERFORM update_session_state(
        p_profile_id,
        p_device_fingerprint,
        'VERIFIED',
        'Restriction period ended'
      );
      v_upgraded := true;
    END IF;
  END IF;
  
  -- RECOVERY → RESTRICTED if online but not re-authenticated
  IF v_session.state = 'RECOVERY' AND v_session.supabase_session_valid = false THEN
    PERFORM update_session_state(
      p_profile_id,
      p_device_fingerprint,
      'RESTRICTED',
      'Came online without re-authentication',
      NOW() + INTERVAL '8 hours' -- Require re-auth within 8 hours
    );
    v_upgraded := true;
  END IF;
  
  RETURN jsonb_build_object(
    'upgraded', v_upgraded,
    'previous_state', v_session.state,
    'current_state', CASE WHEN v_upgraded THEN 'VERIFIED' ELSE v_session.state END
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION auto_upgrade_session_state IS 
'Automatically upgrade session state when conditions met';
