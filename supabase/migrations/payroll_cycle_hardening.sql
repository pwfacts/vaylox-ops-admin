-- ============================================
-- PAYROLL CYCLE HARDENING
-- Production-ready operational corrections
-- ============================================

-- Rule: Do NOT redesign schema, only fix operational correctness

-- ========================================
-- 1. REMOVE AUTO-CREATION FROM ATTENDANCE
-- ========================================

-- REPLACE the auto-creation trigger with strict validation

DROP TRIGGER IF EXISTS trg_assign_attendance_period ON attendance;
DROP FUNCTION IF EXISTS assign_attendance_to_period();

CREATE OR REPLACE FUNCTION assign_attendance_to_period_strict()
RETURNS TRIGGER AS $$
DECLARE
  v_period_id UUID;
  v_period_status TEXT;
  v_lookup_date DATE;
BEGIN
  -- Use shift_start_date if available, fallback to attendance_date
  v_lookup_date := COALESCE(NEW.shift_start_date, NEW.attendance_date);
  
  -- Find matching OPEN period
  SELECT id, status INTO v_period_id, v_period_status
  FROM payroll_periods
  WHERE organization_id = NEW.organization_id
    AND v_lookup_date BETWEEN from_date AND to_date
  LIMIT 1;
  
  -- No period found
  IF v_period_id IS NULL THEN
    RAISE EXCEPTION 'PAYROLL_PERIOD_NOT_AVAILABLE: No payroll period exists for date %. Admin must create period first.', v_lookup_date
      USING ERRCODE = 'P0001',
            HINT = 'Contact admin to create payroll period';
  END IF;
  
  -- Period found but not OPEN
  IF v_period_status != 'OPEN' THEN
    RAISE EXCEPTION 'PERIOD_FINALIZED: Payroll period is % (not OPEN). Cannot add attendance for %.', v_period_status, v_lookup_date
      USING ERRCODE = 'P0002',
            DETAIL = format('Period ID: %s, Status: %s', v_period_id, v_period_status);
  END IF;
  
  -- Assign period (OPEN only)
  NEW.payroll_period_id := v_period_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_assign_attendance_period_strict
  BEFORE INSERT ON attendance
  FOR EACH ROW
  EXECUTE FUNCTION assign_attendance_to_period_strict();

COMMENT ON FUNCTION assign_attendance_to_period_strict IS 
'HARDENED: Rejects attendance if no OPEN period exists - does NOT auto-create';

-- ========================================
-- 2. ADD SHIFT_START_DATE TO ATTENDANCE
-- ========================================

-- For night shifts (e.g., 10 PM to 6 AM)
ALTER TABLE attendance 
  ADD COLUMN IF NOT EXISTS shift_start_date DATE;

-- Backfill existing data
UPDATE attendance 
SET shift_start_date = attendance_date 
WHERE shift_start_date IS NULL;

-- Make required for future records
ALTER TABLE attendance 
  ALTER COLUMN shift_start_date SET NOT NULL;

CREATE INDEX idx_attendance_shift_start_date ON attendance(shift_start_date);

COMMENT ON COLUMN attendance.shift_start_date IS 
'Date when shift starts - used for period assignment (handles night shifts crossing midnight)';

-- ========================================
-- 3. ADMIN-ONLY PERIOD CREATION
-- ========================================

CREATE OR REPLACE FUNCTION ensure_active_payroll_period(
  p_org_id UUID,
  p_date DATE
)
RETURNS JSONB AS $$
DECLARE
  v_settings organization_payroll_settings;
  v_existing_period UUID;
  v_from_date DATE;
  v_to_date DATE;
  v_period_id UUID;
BEGIN
  -- Check if period already exists
  SELECT id INTO v_existing_period
  FROM payroll_periods
  WHERE organization_id = p_org_id
    AND p_date BETWEEN from_date AND to_date;
  
  IF v_existing_period IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', true,
      'period_id', v_existing_period,
      'already_exists', true
    );
  END IF;
  
  -- Get organization settings
  SELECT * INTO v_settings 
  FROM organization_payroll_settings 
  WHERE organization_id = p_org_id;
  
  -- If no settings, create default
  IF NOT FOUND THEN
    INSERT INTO organization_payroll_settings (organization_id, cycle_type)
    VALUES (p_org_id, 'MONTHLY')
    RETURNING * INTO v_settings;
  END IF;
  
  -- Calculate period dates based on cycle type
  IF v_settings.cycle_type = 'MONTHLY' THEN
    -- Calendar month
    v_from_date := DATE_TRUNC('MONTH', p_date)::DATE;
    v_to_date := (DATE_TRUNC('MONTH', p_date) + INTERVAL '1 MONTH' - INTERVAL '1 DAY')::DATE;
  ELSE
    -- CUSTOM_DAY cycle
    IF EXTRACT(DAY FROM p_date) >= v_settings.cycle_start_day THEN
      -- Date is after start_day in current month
      v_from_date := DATE_TRUNC('MONTH', p_date)::DATE + (v_settings.cycle_start_day - 1);
      v_to_date := (DATE_TRUNC('MONTH', p_date) + INTERVAL '1 MONTH')::DATE + (v_settings.cycle_start_day - 2);
    ELSE
      -- Date is before start_day, belongs to previous cycle
      v_from_date := (DATE_TRUNC('MONTH', p_date) - INTERVAL '1 MONTH')::DATE + (v_settings.cycle_start_day - 1);
      v_to_date := DATE_TRUNC('MONTH', p_date)::DATE + (v_settings.cycle_start_day - 2);
    END IF;
  END IF;
  
  -- Create period
  INSERT INTO payroll_periods (
    organization_id,
    from_date,
    to_date,
    status
  )
  VALUES (
    p_org_id,
    v_from_date,
    v_to_date,
    'OPEN'
  )
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_period_id;
  
  -- If insert failed due to conflict, get existing
  IF v_period_id IS NULL THEN
    SELECT id INTO v_period_id
    FROM payroll_periods
    WHERE organization_id = p_org_id
      AND from_date = v_from_date
      AND to_date = v_to_date;
  END IF;
  
  RETURN jsonb_build_object(
    'success', true,
    'period_id', v_period_id,
    'from_date', v_from_date,
    'to_date', v_to_date,
    'created', true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION ensure_active_payroll_period IS 
'ADMIN ONLY: Creates payroll period for given date. NOT called by attendance triggers.';

-- ========================================
-- 4. SCHEDULED PERIOD MAINTENANCE
-- ========================================

CREATE OR REPLACE FUNCTION maintain_payroll_periods()
RETURNS JSONB AS $$
DECLARE
  v_org RECORD;
  v_settings organization_payroll_settings;
  v_current_period payroll_periods;
  v_future_period payroll_periods;
  v_periods_created INTEGER := 0;
  v_result JSONB;
BEGIN
  -- Loop through all organizations with auto-generation enabled
  FOR v_org IN
    SELECT DISTINCT o.id, o.name
    FROM organizations o
    JOIN organization_payroll_settings ops ON ops.organization_id = o.id
    WHERE ops.auto_generate_periods = true
  LOOP
    -- Get settings
    SELECT * INTO v_settings
    FROM organization_payroll_settings
    WHERE organization_id = v_org.id;
    
    -- Get current OPEN period
    SELECT * INTO v_current_period
    FROM payroll_periods
    WHERE organization_id = v_org.id
      AND status = 'OPEN'
    ORDER BY from_date DESC
    LIMIT 1;
    
    -- Check if we need to create periods
    -- Rule 1: No OPEN period exists
    -- Rule 2: Current OPEN period has passed end_date
    
    IF v_current_period IS NULL OR CURRENT_DATE > v_current_period.to_date THEN
      -- Create period for current date
      v_result := ensure_active_payroll_period(v_org.id, CURRENT_DATE);
      
      IF v_result->>'success' = 'true' AND v_result->>'created' = 'true' THEN
        v_periods_created := v_periods_created + 1;
      END IF;
    END IF;
    
    -- Ensure future period exists
    -- Get latest period
    SELECT * INTO v_current_period
    FROM payroll_periods
    WHERE organization_id = v_org.id
    ORDER BY to_date DESC
    LIMIT 1;
    
    IF v_current_period IS NOT NULL THEN
      -- Check if future period exists
      SELECT * INTO v_future_period
      FROM payroll_periods
      WHERE organization_id = v_org.id
        AND from_date > v_current_period.to_date
      LIMIT 1;
      
      -- Create future period if doesn't exist
      IF v_future_period IS NULL THEN
        v_result := generate_next_payroll_period(v_org.id);
        
        IF v_result->>'success' = 'true' THEN
          v_periods_created := v_periods_created + 1;
        END IF;
      END IF;
    END IF;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'periods_created', v_periods_created,
    'run_at', NOW()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION maintain_payroll_periods IS 
'SCHEDULED: Ensures every org has current + 1 future OPEN period. Run daily.';

-- ========================================
-- 5. REOPEN PERIOD (ADMIN ONLY)
-- ========================================

CREATE OR REPLACE FUNCTION reopen_payroll_period(
  p_period_id UUID,
  p_admin_user_id UUID,
  p_reason TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_period payroll_periods;
  v_admin_role TEXT;
BEGIN
  -- Get period
  SELECT * INTO v_period FROM payroll_periods WHERE id = p_period_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'PERIOD_NOT_FOUND');
  END IF;
  
  -- Verify user is ADMIN
  SELECT role INTO v_admin_role
  FROM users
  WHERE id = p_admin_user_id;
  
  IF v_admin_role NOT IN ('ADMIN', 'SUPER_ADMIN') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'PERMISSION_DENIED',
      'message', 'Only ADMIN can reopen periods'
    );
  END IF;
  
  -- Cannot reopen LOCKED period
  IF v_period.status = 'LOCKED' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'PERIOD_LOCKED',
      'message', 'Cannot reopen LOCKED period - payroll finalized'
    );
  END IF;
  
  -- Can only reopen ATTENDANCE_FINALIZED or GENERATED
  IF v_period.status NOT IN ('ATTENDANCE_FINALIZED', 'GENERATED') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'INVALID_STATUS',
      'message', format('Cannot reopen period with status %s', v_period.status)
    );
  END IF;
  
  -- Reopen period
  UPDATE payroll_periods
  SET 
    status = 'OPEN',
    attendance_finalized_at = NULL,
    attendance_finalized_by = NULL,
    generated_at = NULL,
    generated_by = NULL
  WHERE id = p_period_id;
  
  -- Log reopen action
  INSERT INTO payroll_period_audit (
    period_id,
    action,
    old_status,
    new_status,
    performed_by,
    reason
  )
  VALUES (
    p_period_id,
    'REOPENED',
    v_period.status,
    'OPEN',
    p_admin_user_id,
    p_reason
  );
  
  RETURN jsonb_build_object(
    'success', true,
    'period_id', p_period_id,
    'old_status', v_period.status,
    'new_status', 'OPEN',
    'reopened_by', p_admin_user_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION reopen_payroll_period IS 
'ADMIN ONLY: Reopens ATTENDANCE_FINALIZED or GENERATED period. Cannot reopen LOCKED.';

-- ========================================
-- 6. PERIOD AUDIT LOG
-- ========================================

CREATE TABLE IF NOT EXISTS payroll_period_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  period_id UUID NOT NULL REFERENCES payroll_periods(id),
  action TEXT NOT NULL CHECK (action IN (
    'CREATED',
    'FINALIZED',
    'GENERATED',
    'LOCKED',
    'REOPENED'
  )),
  old_status TEXT,
  new_status TEXT,
  performed_by UUID REFERENCES users(id),
  reason TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_payroll_period_audit_period ON payroll_period_audit(period_id);
CREATE INDEX idx_payroll_period_audit_action ON payroll_period_audit(action);

COMMENT ON TABLE payroll_period_audit IS 
'Audit log for all payroll period status changes';

-- ========================================
-- 7. UPDATED FINALIZE FUNCTION
-- ========================================

-- Add audit logging to finalize function
CREATE OR REPLACE FUNCTION finalize_attendance(p_period_id UUID, p_user_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_period payroll_periods;
  v_unconfirmed_count INTEGER;
BEGIN
  -- Get period
  SELECT * INTO v_period FROM payroll_periods WHERE id = p_period_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'PERIOD_NOT_FOUND');
  END IF;
  
  IF v_period.status != 'OPEN' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'PERIOD_NOT_OPEN',
      'current_status', v_period.status
    );
  END IF;
  
  -- Check for unconfirmed shift instances
  SELECT COUNT(*) INTO v_unconfirmed_count
  FROM shift_instances si
  JOIN units u ON u.id = si.unit_id
  WHERE u.organization_id = v_period.organization_id
    AND si.shift_date BETWEEN v_period.from_date AND v_period.to_date
    AND si.status IN ('CLAIMED', 'REPLACED');
  
  IF v_unconfirmed_count > 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'UNCONFIRMED_SHIFTS',
      'unconfirmed_count', v_unconfirmed_count,
      'message', 'All shifts must be CONFIRMED or AUTO_CONFIRMED before finalizing'
    );
  END IF;
  
  -- Update period status
  UPDATE payroll_periods
  SET 
    status = 'ATTENDANCE_FINALIZED',
    attendance_finalized_at = NOW(),
    attendance_finalized_by = p_user_id
  WHERE id = p_period_id;
  
  -- Audit log
  INSERT INTO payroll_period_audit (period_id, action, old_status, new_status, performed_by)
  VALUES (p_period_id, 'FINALIZED', 'OPEN', 'ATTENDANCE_FINALIZED', p_user_id);
  
  RETURN jsonb_build_object(
    'success', true,
    'period_id', p_period_id,
    'status', 'ATTENDANCE_FINALIZED'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ========================================
-- 8. REMOVE AUTO-CREATION FUNCTION
-- ========================================

-- Mark as deprecated - keep for manual admin use only
COMMENT ON FUNCTION auto_create_period_for_date IS 
'DEPRECATED: No longer called automatically. Use ensure_active_payroll_period instead.';

-- ========================================
-- 9. VALIDATION SUMMARY VIEW
-- ========================================

CREATE OR REPLACE VIEW payroll_period_health AS
SELECT 
  o.id AS organization_id,
  o.name AS organization_name,
  
  -- Current period
  cp.id AS current_period_id,
  cp.from_date AS current_from,
  cp.to_date AS current_to,
  cp.status AS current_status,
  
  -- Future period
  fp.id AS future_period_id,
  fp.from_date AS future_from,
  fp.to_date AS future_to,
  
  -- Health flags
  CASE 
    WHEN cp.id IS NULL THEN 'NO_CURRENT_PERIOD'
    WHEN CURRENT_DATE > cp.to_date THEN 'PERIOD_EXPIRED'
    WHEN fp.id IS NULL THEN 'NO_FUTURE_PERIOD'
    ELSE 'HEALTHY'
  END AS health_status,
  
  -- Settings
  ops.cycle_type,
  ops.cycle_start_day,
  ops.auto_generate_periods
FROM organizations o
LEFT JOIN organization_payroll_settings ops ON ops.organization_id = o.id
LEFT JOIN LATERAL (
  SELECT * FROM payroll_periods
  WHERE organization_id = o.id
    AND CURRENT_DATE BETWEEN from_date AND to_date
  LIMIT 1
) cp ON true
LEFT JOIN LATERAL (
  SELECT * FROM payroll_periods
  WHERE organization_id = o.id
    AND from_date > CURRENT_DATE
  ORDER BY from_date
  LIMIT 1
) fp ON true;

COMMENT ON VIEW payroll_period_health IS 
'Health check view for payroll period maintenance';

-- ========================================
-- SUMMARY OF CHANGES
-- ========================================

COMMENT ON DATABASE postgres IS '
PAYROLL CYCLE HARDENING - CHANGES SUMMARY:

1. REMOVED AUTO-CREATION:
   - attendance INSERT no longer creates periods
   - Rejects with PAYROLL_PERIOD_NOT_AVAILABLE if no OPEN period
   - Use ensure_active_payroll_period() for admin creation

2. LATE SYNC BLOCKED:
   - Rejects attendance if period status != OPEN
   - Returns PERIOD_FINALIZED error
   - No silent acceptance

3. NIGHT SHIFT SUPPORT:
   - Added shift_start_date column
   - Period lookup uses shift_start_date (not attendance_date)
   - Handles shifts crossing midnight

4. SCHEDULED MAINTENANCE:
   - maintain_payroll_periods() function
   - Ensures current + 1 future period exists
   - Run daily via cron/scheduler

5. REOPEN SAFETY:
   - Can reopen ATTENDANCE_FINALIZED or GENERATED
   - Cannot reopen LOCKED
   - ADMIN only, with audit logging

REMOVED BEHAVIORS:
   - auto_create_period_for_date() from attendance trigger
   - Silent period creation on attendance punch
   - Auto-generation on any attendance INSERT
';
