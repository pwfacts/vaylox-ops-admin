-- ============================================
-- ATTENDANCE IDEMPOTENCY ENFORCEMENT
-- Database-level duplicate prevention
-- ============================================

-- Goal: ONE guard = ONE payable attendance per shift
-- Protection against: race conditions, offline sync, supervisor duplicates

-- ========================================
-- 1. ATTENDANCE IDENTITY KEY
-- ========================================

-- Add identity key column (generated from business key)
ALTER TABLE attendance
  ADD COLUMN IF NOT EXISTS attendance_identity_key TEXT GENERATED ALWAYS AS (
    organization_id::text || '|' || 
    guard_id::text || '|' || 
    shift_start_date::text || '|' || 
    COALESCE(shift_instance_id::text, 'MANUAL')
  ) STORED;

CREATE INDEX idx_attendance_identity_key ON attendance(attendance_identity_key);

COMMENT ON COLUMN attendance.attendance_identity_key IS 
'Unique business key: org|guard|shift_date|shift - prevents duplicate payable attendance';

-- ========================================
-- 2. UNIQUE CONSTRAINT (IDEMPOTENCY)
-- ========================================

-- Only one VALID attendance per identity key
-- OPERATIONAL_ONLY records can duplicate (they are excluded from payroll)
CREATE UNIQUE INDEX idx_attendance_identity_unique 
  ON attendance(attendance_identity_key)
  WHERE validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED');

COMMENT ON INDEX idx_attendance_identity_unique IS 
'Enforces: ONE guard = ONE payable attendance per shift (database level)';

-- ========================================
-- 3. ATTENDANCE MERGE LOGS
-- ========================================

CREATE TABLE IF NOT EXISTS attendance_merge_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Target attendance (kept)
  target_attendance_id UUID NOT NULL REFERENCES attendance(id),
  attendance_identity_key TEXT NOT NULL,
  
  -- Source that was merged (not inserted)
  source_verification_mode TEXT,
  source_check_in_time TIMESTAMPTZ,
  source_location_coords GEOGRAPHY,
  source_metadata JSONB,
  
  -- Merge decision
  merge_reason TEXT NOT NULL,
  priority_comparison TEXT,  -- e.g., 'LIVE_VERIFIED > OFFLINE_LOCAL'
  
  -- Action taken
  target_updated BOOLEAN DEFAULT false,
  fields_updated TEXT[],
  
  -- Metadata
  merged_at TIMESTAMPTZ DEFAULT NOW(),
  merged_by_user_id UUID REFERENCES users(id),
  
  -- Context
  organization_id UUID NOT NULL REFERENCES organizations(id),
  guard_id UUID NOT NULL REFERENCES guards(id),
  shift_start_date DATE NOT NULL
);

CREATE INDEX idx_attendance_merge_logs_target ON attendance_merge_logs(target_attendance_id);
CREATE INDEX idx_attendance_merge_logs_identity ON attendance_merge_logs(attendance_identity_key);
CREATE INDEX idx_attendance_merge_logs_guard ON attendance_merge_logs(guard_id, shift_start_date);
CREATE INDEX idx_attendance_merge_logs_org ON attendance_merge_logs(organization_id);

COMMENT ON TABLE attendance_merge_logs IS 
'Audit trail for attendance merge operations - tracks duplicate attempts';

-- ========================================
-- 4. VERIFICATION MODE PRIORITY
-- ========================================

CREATE OR REPLACE FUNCTION get_verification_mode_priority(p_mode TEXT)
RETURNS INTEGER AS $$
BEGIN
  RETURN CASE p_mode
    WHEN 'LIVE_VERIFIED' THEN 100      -- Highest: Real-time with GPS + Face
    WHEN 'DELAYED_SYNC' THEN 75        -- High: Captured with verification, synced later
    WHEN 'OFFLINE_LOCAL' THEN 50       -- Medium: Offline capture
    WHEN 'MANUAL' THEN 25              -- Low: Manual supervisor entry
    ELSE 0                             -- Unknown
  END;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

COMMENT ON FUNCTION get_verification_mode_priority IS 
'Priority rules: LIVE_VERIFIED > DELAYED_SYNC > OFFLINE_LOCAL > MANUAL';

-- ========================================
-- 5. UPSERT ATTENDANCE FUNCTION
-- ========================================

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
  v_identity_key TEXT;
  v_existing_attendance attendance;
  v_existing_priority INTEGER;
  v_new_priority INTEGER;
  v_should_update BOOLEAN;
  v_fields_updated TEXT[] := ARRAY[]::TEXT[];
  v_result_action TEXT;
  v_attendance_id UUID;
BEGIN
  -- Calculate identity key
  v_identity_key := p_organization_id::text || '|' || 
                    p_guard_id::text || '|' || 
                    p_shift_start_date::text || '|' || 
                    COALESCE(p_shift_instance_id::text, 'MANUAL');
  
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
      'is_duplicate', false
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
    
    -- Update check-in time if new priority higher
    IF p_check_in_time IS NOT NULL AND p_check_in_time != v_existing_attendance.check_in_time THEN
      UPDATE attendance
      SET check_in_time = p_check_in_time
      WHERE id = v_existing_attendance.id;
      v_fields_updated := array_append(v_fields_updated, 'check_in_time');
    END IF;
    
    -- Update verification mode
    UPDATE attendance
    SET verification_mode = p_verification_mode
    WHERE id = v_existing_attendance.id;
    v_fields_updated := array_append(v_fields_updated, 'verification_mode');
    
    -- Update location if provided
    IF p_location_coords IS NOT NULL THEN
      UPDATE attendance
      SET location_coords = p_location_coords
      WHERE id = v_existing_attendance.id;
      v_fields_updated := array_append(v_fields_updated, 'location_coords');
    END IF;
    
    -- Update face verification
    IF p_face_verified = true AND v_existing_attendance.face_verified = false THEN
      UPDATE attendance
      SET face_verified = p_face_verified
      WHERE id = v_existing_attendance.id;
      v_fields_updated := array_append(v_fields_updated, 'face_verified');
    END IF;
    
    v_result_action := 'MERGED_UPDATED';
    
  ELSIF v_new_priority = v_existing_priority THEN
    -- Same priority - keep earliest check-in time
    IF p_check_in_time IS NOT NULL AND 
       (v_existing_attendance.check_in_time IS NULL OR p_check_in_time < v_existing_attendance.check_in_time) THEN
      UPDATE attendance
      SET check_in_time = p_check_in_time
      WHERE id = v_existing_attendance.id;
      v_fields_updated := array_append(v_fields_updated, 'check_in_time');
      v_should_update := true;
    END IF;
    
    v_result_action := CASE WHEN v_should_update THEN 'MERGED_UPDATED' ELSE 'MERGED_IGNORED' END;
    
  ELSE
    -- New priority lower - ignore new attempt
    v_result_action := 'MERGED_IGNORED';
  END IF;
  
  -- ========================================
  -- LOG MERGE ATTEMPT
  -- ========================================
  
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
  
  -- ========================================
  -- LOG AS EXCEPTION (for monitoring)
  -- ========================================
  
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
    v_existing_attendance.id,
    p_organization_id,
    p_guard_id,
    p_shift_instance_id,
    'DUPLICATE_ATTENDANCE',
    format('Duplicate attendance attempt merged - action: %s', v_result_action),
    jsonb_build_object(
      'existing_verification_mode', v_existing_attendance.verification_mode,
      'new_verification_mode', p_verification_mode,
      'existing_priority', v_existing_priority,
      'new_priority', v_new_priority,
      'action_taken', v_result_action,
      'fields_updated', v_fields_updated
    ),
    p_attendance_date,
    p_shift_start_date,
    'RESOLVED',  -- Auto-resolved (merged, not error)
    'SYSTEM_AUTO'
  )
  ON CONFLICT DO NOTHING;  -- Don't create duplicate exception records
  
  RETURN jsonb_build_object(
    'action', v_result_action,
    'attendance_id', v_existing_attendance.id,
    'identity_key', v_identity_key,
    'is_duplicate', true,
    'existing_priority', v_existing_priority,
    'new_priority', v_new_priority,
    'target_updated', v_should_update,
    'fields_updated', v_fields_updated
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION upsert_attendance IS 
'IDEMPOTENT: Inserts new attendance or merges into existing based on priority rules';

-- ========================================
-- 6. SAFE PAYROLL AGGREGATION
-- ========================================

-- Ensure payroll always counts DISTINCT attendance_identity_key
CREATE OR REPLACE FUNCTION aggregate_work_units_by_period_idempotent(p_period_id UUID)
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
  v_duplicate_count INTEGER := 0;
BEGIN
  -- Get period
  SELECT * INTO v_period FROM payroll_periods WHERE id = p_period_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'PERIOD_NOT_FOUND');
  END IF;
  
  -- Count duplicates (for reporting)
  SELECT COUNT(*) INTO v_duplicate_count
  FROM attendance_merge_logs
  WHERE organization_id = v_period.organization_id
    AND shift_start_date BETWEEN v_period.from_date AND v_period.to_date;
  
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
    -- Count DISTINCT attendance by identity_key (idempotent)
    SELECT COUNT(DISTINCT a.attendance_identity_key) INTO v_present_count
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    WHERE a.payroll_period_id = p_period_id
      AND a.guard_id = v_guard_id
      AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
      AND si.status = 'CONFIRMED'
      AND si.auto_confirm_reason IS NULL;
    
    -- Auto-present days (DISTINCT)
    SELECT COUNT(DISTINCT a.attendance_identity_key) INTO v_auto_present_count
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    WHERE a.payroll_period_id = p_period_id
      AND a.guard_id = v_guard_id
      AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
      AND si.status = 'AUTO_CONFIRMED';
    
    -- Replacement days (DISTINCT)
    SELECT COUNT(DISTINCT a.attendance_identity_key) INTO v_replacement_count
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    JOIN guard_replacements gr ON gr.replacement_profile_id = (
      SELECT id FROM workforce_profiles WHERE linked_auth_user = (
        SELECT id FROM guards WHERE id = v_guard_id LIMIT 1
      )
    )
    WHERE a.payroll_period_id = p_period_id
      AND a.guard_id = v_guard_id
      AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
      AND si.status IN ('CONFIRMED', 'AUTO_CONFIRMED', 'PAYROLL_LOCKED');
    
    -- OT days (future)
    v_ot_count := 0;
    
    -- Collect shift IDs (DISTINCT by identity_key)
    SELECT array_agg(DISTINCT si.id) INTO v_shift_ids
    FROM (
      SELECT DISTINCT ON (a.attendance_identity_key) si.id, a.attendance_identity_key
      FROM attendance a
      JOIN shift_instances si ON si.id = a.shift_instance_id
      WHERE a.payroll_period_id = p_period_id
        AND a.guard_id = v_guard_id
        AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
        AND si.status IN ('CONFIRMED', 'AUTO_CONFIRMED', 'PAYROLL_LOCKED')
      ORDER BY a.attendance_identity_key, a.created_at
    ) si;
    
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
    'duplicate_merges', v_duplicate_count,
    'period_id', p_period_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION aggregate_work_units_by_period_idempotent IS 
'IDEMPOTENT AGGREGATION: Uses DISTINCT attendance_identity_key to prevent double-counting';

-- ========================================
-- 7. DUPLICATE DETECTION REPORT
-- ========================================

CREATE OR REPLACE VIEW attendance_duplicate_report AS
SELECT 
  aml.shift_start_date,
  g.full_name AS guard_name,
  aml.attendance_identity_key,
  COUNT(*) AS merge_attempts,
  
  -- Priority breakdown
  json_agg(DISTINCT aml.source_verification_mode) AS attempted_modes,
  aml.priority_comparison,
  
  -- Target info
  a.verification_mode AS final_mode,
  a.check_in_time AS final_check_in,
  
  -- Update stats
  COUNT(*) FILTER (WHERE aml.target_updated = true) AS updates_applied,
  COUNT(*) FILTER (WHERE aml.target_updated = false) AS updates_ignored,
  
  MIN(aml.merged_at) AS first_attempt,
  MAX(aml.merged_at) AS last_attempt
FROM attendance_merge_logs aml
JOIN attendance a ON a.id = aml.target_attendance_id
JOIN guards g ON g.id = aml.guard_id
GROUP BY 
  aml.shift_start_date,
  g.full_name,
  aml.attendance_identity_key,
  aml.priority_comparison,
  a.verification_mode,
  a.check_in_time
HAVING COUNT(*) > 1
ORDER BY aml.shift_start_date DESC, COUNT(*) DESC;

COMMENT ON VIEW attendance_duplicate_report IS 
'Shows attendance records with multiple merge attempts - useful for monitoring duplicate sources';
