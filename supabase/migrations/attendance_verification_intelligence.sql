-- ============================================
-- ATTENDANCE VERIFICATION INTELLIGENCE LAYER
-- Trust score calculation for offline attendance
-- ============================================

-- 1. CALCULATE TRUST SCORE
CREATE OR REPLACE FUNCTION calculate_attendance_trust_score(
  p_verification_mode TEXT,
  p_sync_delay_seconds INTEGER,
  p_time_drift_seconds INTEGER DEFAULT 0,
  p_device_fingerprint TEXT DEFAULT NULL,
  p_has_gps_location BOOLEAN DEFAULT false,
  p_face_verified BOOLEAN DEFAULT false,
  p_face_match_score NUMERIC DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_base_score INTEGER;
  v_trust_score INTEGER;
  v_deductions JSONB := '[]'::JSONB;
  v_bonuses JSONB := '[]'::JSONB;
  v_flags TEXT[] := ARRAY[]::TEXT[];
BEGIN
  -- BASE SCORE by verification mode
  CASE p_verification_mode
    WHEN 'LIVE_VERIFIED' THEN
      v_base_score := 95;
    WHEN 'DELAYED_SYNC' THEN
      -- Calculate based on delay
      IF p_sync_delay_seconds IS NULL OR p_sync_delay_seconds < 60 THEN
        v_base_score := 90; -- < 1 minute
      ELSIF p_sync_delay_seconds < 300 THEN
        v_base_score := 85; -- < 5 minutes
      ELSIF p_sync_delay_seconds < 900 THEN
        v_base_score := 75; -- < 15 minutes
      ELSIF p_sync_delay_seconds < 3600 THEN
        v_base_score := 65; -- < 1 hour
      ELSE
        v_base_score := 55; -- > 1 hour
        v_flags := array_append(v_flags, 'LONG_SYNC_DELAY');
      END IF;
    WHEN 'OFFLINE_LOCAL' THEN
      v_base_score := 60;
      v_flags := array_append(v_flags, 'OFFLINE_PUNCH');
    WHEN 'MANUAL_OVERRIDE' THEN
      v_base_score := 25;
      v_flags := array_append(v_flags, 'MANUAL_ENTRY');
    ELSE
      v_base_score := 50; -- Unknown mode
  END CASE;
  
  v_trust_score := v_base_score;
  
  -- DEDUCTIONS
  
  -- Time drift deduction
  IF p_time_drift_seconds IS NOT NULL AND ABS(p_time_drift_seconds) > 60 THEN
    IF ABS(p_time_drift_seconds) > 300 THEN
      v_trust_score := v_trust_score - 15;
      v_deductions := v_deductions || jsonb_build_object(
        'reason', 'Large time drift',
        'value', -15,
        'drift_seconds', p_time_drift_seconds
      );
      v_flags := array_append(v_flags, 'TIME_DRIFT');
    ELSE
      v_trust_score := v_trust_score - 5;
      v_deductions := v_deductions || jsonb_build_object(
        'reason', 'Moderate time drift',
        'value', -5,
        'drift_seconds', p_time_drift_seconds
      );
    END IF;
  END IF;
  
  -- No device fingerprint
  IF p_device_fingerprint IS NULL THEN
    v_trust_score := v_trust_score - 10;
    v_deductions := v_deductions || jsonb_build_object(
      'reason', 'No device fingerprint',
      'value', -10
    );
    v_flags := array_append(v_flags, 'NO_DEVICE_ID');
  END IF;
  
  -- No GPS location
  IF NOT p_has_gps_location AND p_verification_mode != 'MANUAL_OVERRIDE' THEN
    v_trust_score := v_trust_score - 5;
    v_deductions := v_deductions || jsonb_build_object(
      'reason', 'No GPS location',
      'value', -5
    );
  END IF;
  
  -- BONUSES
  
  -- Face verification bonus
  IF p_face_verified THEN
    IF p_face_match_score IS NOT NULL AND p_face_match_score >= 0.9 THEN
      v_trust_score := v_trust_score + 5;
      v_bonuses := v_bonuses || jsonb_build_object(
        'reason', 'High-confidence face match',
        'value', 5,
        'match_score', p_face_match_score
      );
    ELSE
      v_trust_score := v_trust_score + 3;
      v_bonuses := v_bonuses || jsonb_build_object(
        'reason', 'Face verified',
        'value', 3
      );
    END IF;
  END IF;
  
  -- GPS location bonus
  IF p_has_gps_location THEN
    v_trust_score := v_trust_score + 2;
    v_bonuses := v_bonuses || jsonb_build_object(
      'reason', 'GPS location captured',
      'value', 2
    );
  END IF;
  
  -- Ensure score is within bounds
  v_trust_score := GREATEST(0, LEAST(100, v_trust_score));
  
  -- Return detailed result
  RETURN jsonb_build_object(
    'trust_score', v_trust_score,
    'base_score', v_base_score,
    'verification_mode', p_verification_mode,
    'deductions', v_deductions,
    'bonuses', v_bonuses,
    'flags', v_flags,
    'classification', CASE
      WHEN v_trust_score >= 80 THEN 'HIGH_TRUST'
      WHEN v_trust_score >= 60 THEN 'MEDIUM_TRUST'
      WHEN v_trust_score >= 40 THEN 'LOW_TRUST'
      ELSE 'VERY_LOW_TRUST'
    END
  );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION calculate_attendance_trust_score IS 
'Calculate trust score (0-100) for attendance record based on verification quality';

-- 2. AUTO-COMPUTE TRUST SCORE ON INSERT/UPDATE
CREATE OR REPLACE FUNCTION auto_compute_attendance_trust_score()
RETURNS TRIGGER AS $$
DECLARE
  v_result JSONB;
  v_sync_delay INTEGER;
  v_time_drift INTEGER;
BEGIN
  -- Only compute if verification_mode is set
  IF NEW.verification_mode IS NULL THEN
    RETURN NEW;
  END IF;
  
  -- Calculate sync delay
  IF NEW.device_timestamp IS NOT NULL AND NEW.server_received_timestamp IS NOT NULL THEN
    v_sync_delay := EXTRACT(EPOCH FROM (NEW.server_received_timestamp - NEW.device_timestamp))::INTEGER;
    NEW.sync_delay_seconds := v_sync_delay;
  ELSE
    v_sync_delay := NEW.sync_delay_seconds;
  END IF;
  
  -- Calculate time drift (if device_timestamp available)
  IF NEW.device_timestamp IS NOT NULL THEN
    v_time_drift := EXTRACT(EPOCH FROM (NOW() - NEW.device_timestamp - COALESCE(v_sync_delay, 0)))::INTEGER;
    NEW.time_drift_seconds := v_time_drift;
  ELSE
    v_time_drift := NEW.time_drift_seconds;
  END IF;
  
  -- Set server_received_timestamp if not set
  IF NEW.server_received_timestamp IS NULL THEN
    NEW.server_received_timestamp := NOW();
  END IF;
  
  -- Calculate trust score
  SELECT calculate_attendance_trust_score(
    NEW.verification_mode,
    v_sync_delay,
    v_time_drift,
    NEW.device_fingerprint,
    NEW.gps_location IS NOT NULL,
    COALESCE(NEW.face_verified, false),
    NEW.face_match_score
  ) INTO v_result;
  
  NEW.trust_score := (v_result->>'trust_score')::INTEGER;
  NEW.trust_score_details := v_result;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger
DROP TRIGGER IF EXISTS trigger_auto_compute_attendance_trust_score ON attendance;
CREATE TRIGGER trigger_auto_compute_attendance_trust_score
  BEFORE INSERT OR UPDATE OF verification_mode, device_timestamp, face_verified, face_match_score
  ON attendance
  FOR EACH ROW
  EXECUTE FUNCTION auto_compute_attendance_trust_score();

COMMENT ON TRIGGER trigger_auto_compute_attendance_trust_score ON attendance IS 
'Automatically compute trust score when attendance is created or verification data updated';

-- 3. VIEW: ATTENDANCE WITH VERIFICATION DETAILS
CREATE OR REPLACE VIEW attendance_with_verification AS
SELECT 
  a.*,
  g.full_name AS guard_name,
  g.employee_code,
  u.name AS unit_name,
  
  -- Verification details
  a.trust_score,
  a.verification_mode,
  (a.trust_score_details->>'classification')::TEXT AS trust_classification,
  a.sync_delay_seconds,
  a.time_drift_seconds,
  
  -- Human-readable sync delay
  CASE 
    WHEN a.sync_delay_seconds IS NULL THEN 'N/A'
    WHEN a.sync_delay_seconds < 60 THEN '< 1 minute'
    WHEN a.sync_delay_seconds < 300 THEN '< 5 minutes'
    WHEN a.sync_delay_seconds < 900 THEN '< 15 minutes'
    WHEN a.sync_delay_seconds < 3600 THEN '< 1 hour'
    ELSE '> 1 hour'
  END AS sync_delay_friendly,
  
  -- Flags
  (a.trust_score_details->'flags')::TEXT[] AS verification_flags,
  
  -- Verification timestamp  
  a.device_timestamp,
  a.server_received_timestamp,
  
  -- Present status (dispatch engine compatibility)
  CASE 
    WHEN a.check_in_time IS NOT NULL THEN true
    ELSE false
  END AS is_present,
  
  -- Verified status (for payroll - never auto-block)
  CASE
    WHEN a.approval_status = 'approved' THEN true
    WHEN a.trust_score >= 80 THEN true  -- High trust auto-approved
    ELSE false
  END AS is_verified_for_payroll,
  
  -- Warning flags for supervisors
  CASE
    WHEN a.trust_score < 40 THEN 'REVIEW_REQUIRED'
    WHEN a.trust_score < 60 THEN 'LOW_CONFIDENCE'
    WHEN a.verification_mode = 'OFFLINE_LOCAL' THEN 'OFFLINE_PUNCH'
    ELSE NULL
  END AS supervisor_alert
  
FROM attendance a
JOIN guards g ON g.id = a.guard_id
JOIN units u ON u.id = a.unit_id;

COMMENT ON VIEW attendance_with_verification IS 
'Attendance records with trust scores and verification intelligence';

-- 4. UPDATE EXISTING ATTENDANCE RECORDS (Set defaults)
UPDATE attendance
SET 
  verification_mode = CASE
    WHEN attendance_method = 'manual' THEN 'MANUAL_OVERRIDE'
    WHEN created_at IS NOT NULL AND NOW() - created_at > INTERVAL '5 minutes' THEN 'DELAYED_SYNC'
    ELSE 'LIVE_VERIFIED'
  END,
  device_timestamp = COALESCE(check_in_time, created_at),
  server_received_timestamp = COALESCE(created_at, NOW())
WHERE verification_mode IS NULL;

-- Trigger trust score calculation for existing records
UPDATE attendance
SET verification_mode = verification_mode  -- Triggers the auto-compute
WHERE trust_score IS NULL;
