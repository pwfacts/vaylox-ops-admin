-- ============================================
-- PAYROLL CYCLE-BASED SYSTEM
-- Replaces fixed calendar months with configurable cycles
-- ============================================

-- Rule: Do NOT modify salary formulas, PF/PT logic, or shift ownership
-- Only replace month-based filtering with payroll_period_id

-- ========================================
-- 1. ORGANIZATION PAYROLL CYCLE CONFIG
-- ========================================

CREATE TABLE IF NOT EXISTS organization_payroll_settings (
  organization_id UUID PRIMARY KEY REFERENCES organizations(id),
  
  -- Cycle configuration
  cycle_type TEXT NOT NULL DEFAULT 'MONTHLY' CHECK (cycle_type IN ('MONTHLY', 'CUSTOM_DAY')),
  cycle_start_day INTEGER CHECK (cycle_start_day >= 1 AND cycle_start_day <= 28),
  
  -- Automation
  auto_generate_periods BOOLEAN DEFAULT true,
  
  -- Metadata
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Validation
  CONSTRAINT valid_custom_day CHECK (
    (cycle_type = 'MONTHLY' AND cycle_start_day IS NULL) OR
    (cycle_type = 'CUSTOM_DAY' AND cycle_start_day IS NOT NULL)
  )
);

CREATE INDEX idx_org_payroll_settings_org ON organization_payroll_settings(organization_id);

COMMENT ON TABLE organization_payroll_settings IS 
'Organization-level payroll cycle configuration - MONTHLY or CUSTOM_DAY (26th to 25th style)';

COMMENT ON COLUMN organization_payroll_settings.cycle_start_day IS 
'For CUSTOM_DAY: 1-28 allowed (safe across all months). Example: 26 = 26 Jan to 25 Feb';

-- ========================================
-- 2. REFACTOR PAYROLL_PERIODS TABLE
-- ========================================

-- Drop existing if needed, or alter
DROP TABLE IF EXISTS payroll_periods CASCADE;

CREATE TABLE payroll_periods (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  
  -- Period dates (REPLACES month/year)
  from_date DATE NOT NULL,
  to_date DATE NOT NULL,
  
  -- Period status workflow
  status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN (
    'OPEN',                    -- Attendance can be punched
    'ATTENDANCE_FINALIZED',    -- Attendance locked, ready for payroll generation
    'GENERATED',               -- Payroll calculated
    'LOCKED'                   -- Fully closed, immutable
  )),
  
  -- Workflow timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  attendance_finalized_at TIMESTAMPTZ,
  attendance_finalized_by UUID REFERENCES users(id),
  generated_at TIMESTAMPTZ,
  generated_by UUID REFERENCES users(id),
  locked_at TIMESTAMPTZ,
  locked_by UUID REFERENCES users(id),
  
  -- Constraints
  CONSTRAINT valid_date_range CHECK (to_date >= from_date),
  CONSTRAINT one_open_period_per_org UNIQUE (organization_id) WHERE (status = 'OPEN')
);

CREATE INDEX idx_payroll_periods_org ON payroll_periods(organization_id);
CREATE INDEX idx_payroll_periods_dates ON payroll_periods(organization_id, from_date, to_date);
CREATE INDEX idx_payroll_periods_status ON payroll_periods(status);

-- Prevent overlapping periods
CREATE UNIQUE INDEX idx_payroll_periods_no_overlap ON payroll_periods 
  USING GIST (organization_id, daterange(from_date, to_date, '[]'));

COMMENT ON TABLE payroll_periods IS 
'Payroll periods - replacing fixed calendar months with configurable cycles';

COMMENT ON CONSTRAINT one_open_period_per_org ON payroll_periods IS 
'Only one OPEN period allowed per organization at a time';

-- ========================================
-- 3. ATTENDANCE LINKAGE TO PERIOD
-- ========================================

-- Add payroll_period_id to attendance
ALTER TABLE attendance 
  ADD COLUMN IF NOT EXISTS payroll_period_id UUID REFERENCES payroll_periods(id);

CREATE INDEX idx_attendance_period ON attendance(payroll_period_id);

COMMENT ON COLUMN attendance.payroll_period_id IS 
'Links attendance to payroll period - determined by attendance_date between period dates';

-- ========================================
-- 4. AUTOMATIC PERIOD ASSIGNMENT TRIGGER
-- ========================================

CREATE OR REPLACE FUNCTION assign_attendance_to_period()
RETURNS TRIGGER AS $$
DECLARE
  v_period_id UUID;
BEGIN
  -- Find matching period for this attendance
  SELECT id INTO v_period_id
  FROM payroll_periods
  WHERE organization_id = NEW.organization_id
    AND NEW.attendance_date BETWEEN from_date AND to_date
  LIMIT 1;
  
  IF v_period_id IS NULL THEN
    -- No period exists - create OPEN period automatically if enabled
    SELECT id INTO v_period_id
    FROM auto_create_period_for_date(NEW.organization_id, NEW.attendance_date);
  END IF;
  
  NEW.payroll_period_id := v_period_id;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_assign_attendance_period
  BEFORE INSERT ON attendance
  FOR EACH ROW
  EXECUTE FUNCTION assign_attendance_to_period();

COMMENT ON FUNCTION assign_attendance_to_period IS 
'Automatically assigns attendance to correct payroll period based on date';

-- ========================================
-- 5. AUTO-CREATE PERIOD FOR DATE
-- ========================================

CREATE OR REPLACE FUNCTION auto_create_period_for_date(
  p_org_id UUID,
  p_date DATE
)
RETURNS UUID AS $$
DECLARE
  v_settings organization_payroll_settings;
  v_from_date DATE;
  v_to_date DATE;
  v_period_id UUID;
BEGIN
  -- Get organization settings
  SELECT * INTO v_settings 
  FROM organization_payroll_settings 
  WHERE organization_id = p_org_id;
  
  -- If no settings, use MONTHLY default
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
    -- Example: start_day = 26
    -- If date is Jan 15 → period is Dec 26 to Jan 25
    -- If date is Jan 28 → period is Jan 26 to Feb 25
    
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
  
  -- Create period if doesn't exist
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
  
  -- If already exists, get it
  IF v_period_id IS NULL THEN
    SELECT id INTO v_period_id
    FROM payroll_periods
    WHERE organization_id = p_org_id
      AND from_date = v_from_date
      AND to_date = v_to_date;
  END IF;
  
  RETURN v_period_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION auto_create_period_for_date IS 
'Auto-creates payroll period for given date based on organization cycle settings';

-- ========================================
-- 6. GENERATE NEXT PAYROLL PERIOD
-- ========================================

CREATE OR REPLACE FUNCTION generate_next_payroll_period(p_org_id UUID)
RETURNS JSONB AS $$
DECLARE
  v_settings organization_payroll_settings;
  v_last_period payroll_periods;
  v_from_date DATE;
  v_to_date DATE;
  v_new_period_id UUID;
BEGIN
  -- Get settings
  SELECT * INTO v_settings 
  FROM organization_payroll_settings 
  WHERE organization_id = p_org_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'NO_SETTINGS_FOUND');
  END IF;
  
  -- Get last period
  SELECT * INTO v_last_period
  FROM payroll_periods
  WHERE organization_id = p_org_id
  ORDER BY to_date DESC
  LIMIT 1;
  
  -- Calculate next period dates
  IF v_last_period IS NULL THEN
    -- First period - use current date
    RETURN auto_create_period_for_date(p_org_id, CURRENT_DATE);
  END IF;
  
  IF v_settings.cycle_type = 'MONTHLY' THEN
    -- Next calendar month
    v_from_date := (DATE_TRUNC('MONTH', v_last_period.to_date) + INTERVAL '1 MONTH')::DATE;
    v_to_date := (v_from_date + INTERVAL '1 MONTH' - INTERVAL '1 DAY')::DATE;
  ELSE
    -- CUSTOM_DAY: next cycle starts day after last period ends
    v_from_date := v_last_period.to_date + 1;
    
    -- Next period ends day before start_day of following month
    v_to_date := (DATE_TRUNC('MONTH', v_from_date) + INTERVAL '1 MONTH')::DATE + (v_settings.cycle_start_day - 2);
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
  RETURNING id INTO v_new_period_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'period_id', v_new_period_id,
    'from_date', v_from_date,
    'to_date', v_to_date
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION generate_next_payroll_period IS 
'Generates next payroll period based on organization cycle settings';

-- ========================================
-- 7. FINALIZE ATTENDANCE
-- ========================================

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
  
  RETURN jsonb_build_object(
    'success', true,
    'period_id', p_period_id,
    'status', 'ATTENDANCE_FINALIZED'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION finalize_attendance IS 
'Finalizes attendance for period - prevents further edits, ready for payroll generation';

-- ========================================
-- 8. PREVENT ATTENDANCE EDITS AFTER FINALIZATION
-- ========================================

CREATE OR REPLACE FUNCTION prevent_attendance_edit_if_finalized()
RETURNS TRIGGER AS $$
DECLARE
  v_period_status TEXT;
BEGIN
  -- Get period status
  SELECT status INTO v_period_status
  FROM payroll_periods
  WHERE id = NEW.payroll_period_id;
  
  IF v_period_status IN ('ATTENDANCE_FINALIZED', 'GENERATED', 'LOCKED') THEN
    RAISE EXCEPTION 'Cannot modify attendance - period status is %', v_period_status
      USING ERRCODE = 'P0001';
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_attendance_edit_finalized
  BEFORE UPDATE ON attendance
  FOR EACH ROW
  EXECUTE FUNCTION prevent_attendance_edit_if_finalized();

CREATE TRIGGER trg_prevent_attendance_insert_finalized
  BEFORE INSERT ON attendance
  FOR EACH ROW
  EXECUTE FUNCTION prevent_attendance_edit_if_finalized();

-- ========================================
-- 9. REFACTORED AGGREGATE WORK UNITS
-- ========================================

-- REPLACED: Month/year filtering with period_id filtering

CREATE OR REPLACE FUNCTION aggregate_work_units_by_period(p_period_id UUID)
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
BEGIN
  -- Get period
  SELECT * INTO v_period FROM payroll_periods WHERE id = p_period_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'PERIOD_NOT_FOUND');
  END IF;
  
  -- Must be finalized
  IF v_period.status NOT IN ('ATTENDANCE_FINALIZED', 'GENERATED') THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'ATTENDANCE_NOT_FINALIZED',
      'message', 'Attendance must be finalized before aggregating work units'
    );
  END IF;
  
  -- Loop through each guard with attendance in THIS PERIOD
  FOR v_guard_id IN
    SELECT DISTINCT a.guard_id
    FROM attendance a
    WHERE a.payroll_period_id = p_period_id  -- REPLACED: date range filtering
      AND EXISTS (
        SELECT 1 FROM shift_instances si
        WHERE si.id = a.shift_instance_id
          AND si.status IN ('CONFIRMED', 'AUTO_CONFIRMED', 'PAYROLL_LOCKED')
      )
  LOOP
    -- Count present days (CONFIRMED only)
    SELECT COUNT(DISTINCT si.shift_date) INTO v_present_count
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    WHERE a.payroll_period_id = p_period_id  -- REPLACED
      AND a.guard_id = v_guard_id
      AND si.status = 'CONFIRMED'
      AND si.auto_confirm_reason IS NULL;
    
    -- Count auto-present days
    SELECT COUNT(DISTINCT si.shift_date) INTO v_auto_present_count
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    WHERE a.payroll_period_id = p_period_id  -- REPLACED
      AND a.guard_id = v_guard_id
      AND si.status = 'AUTO_CONFIRMED';
    
    -- Count replacement days
    SELECT COUNT(DISTINCT si.shift_date) INTO v_replacement_count
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    JOIN guard_replacements gr ON gr.replacement_profile_id = (
      SELECT id FROM workforce_profiles WHERE linked_auth_user = (
        SELECT id FROM guards WHERE id = v_guard_id LIMIT 1
      )
    )
    WHERE a.payroll_period_id = p_period_id  -- REPLACED
      AND a.guard_id = v_guard_id
      AND si.status IN ('CONFIRMED', 'AUTO_CONFIRMED', 'PAYROLL_LOCKED');
    
    -- OT days (future implementation)
    v_ot_count := 0;
    
    -- Collect shift instance IDs
    SELECT array_agg(DISTINCT si.id) INTO v_shift_ids
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    WHERE a.payroll_period_id = p_period_id  -- REPLACED
      AND a.guard_id = v_guard_id
      AND si.status IN ('CONFIRMED', 'AUTO_CONFIRMED', 'PAYROLL_LOCKED');
    
    -- Insert or update work unit
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
    'period_id', p_period_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION aggregate_work_units_by_period IS 
'REFACTORED: Uses payroll_period_id instead of date ranges';

-- ========================================
-- 10. AUTO-GENERATE NEXT PERIOD ON LOCK
-- ========================================

CREATE OR REPLACE FUNCTION auto_generate_next_period_on_lock()
RETURNS TRIGGER AS $$
DECLARE
  v_settings organization_payroll_settings;
BEGIN
  -- Only trigger when status changes to LOCKED
  IF NEW.status = 'LOCKED' AND OLD.status != 'LOCKED' THEN
    -- Check if auto-generation enabled
    SELECT * INTO v_settings
    FROM organization_payroll_settings
    WHERE organization_id = NEW.organization_id;
    
    IF v_settings.auto_generate_periods THEN
      PERFORM generate_next_payroll_period(NEW.organization_id);
    END IF;
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_auto_generate_next_period
  AFTER UPDATE ON payroll_periods
  FOR EACH ROW
  EXECUTE FUNCTION auto_generate_next_period_on_lock();

COMMENT ON FUNCTION auto_generate_next_period_on_lock IS 
'Automatically generates next period when current period is locked';
