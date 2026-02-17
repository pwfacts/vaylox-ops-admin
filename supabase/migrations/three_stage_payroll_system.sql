-- ============================================
-- 3-STAGE PAYROLL SYSTEM
-- Stage 1: Work Unit Aggregation (counts only)
-- Stage 2: Calculation Snapshot (immutable earnings)
-- Stage 3: Settlement Layer (deductions + payment)
-- ============================================

-- ========================================
-- STAGE 1: WORK UNIT AGGREGATION
-- ========================================

CREATE TABLE IF NOT EXISTS payroll_work_units (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Period and guard
  payroll_period_id UUID NOT NULL REFERENCES payroll_periods(id),
  guard_id UUID NOT NULL REFERENCES guards(id),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  
  -- Work day counts (NO MONEY, just counts)
  present_days DECIMAL(5, 2) DEFAULT 0,        -- Normal confirmed attendance
  auto_present_days DECIMAL(5, 2) DEFAULT 0,   -- Auto-confirmed (supervisor inactive)
  replacement_days DECIMAL(5, 2) DEFAULT 0,    -- Days worked as replacement
  ot_days DECIMAL(5, 2) DEFAULT 0,             -- Overtime days
  
  -- Source shift instances
  included_shift_instances UUID[],              -- Array of shift_instance IDs
  
  -- Aggregation metadata
  aggregated_at TIMESTAMPTZ DEFAULT NOW(),
  aggregation_status TEXT DEFAULT 'DRAFT' CHECK (aggregation_status IN (
    'DRAFT',        -- Work units calculated but not finalized
    'FINALIZED'     -- Locked, ready for calculation
  )),
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(payroll_period_id, guard_id)
);

CREATE INDEX idx_payroll_work_units_period ON payroll_work_units(payroll_period_id);
CREATE INDEX idx_payroll_work_units_guard ON payroll_work_units(guard_id);
CREATE INDEX idx_payroll_work_units_status ON payroll_work_units(aggregation_status);

COMMENT ON TABLE payroll_work_units IS 
'Stage 1: Work unit aggregation - counts only, no money calculations';

COMMENT ON COLUMN payroll_work_units.auto_present_days IS 
'Days auto-confirmed due to supervisor inactivity - flagged for audit';

-- ========================================
-- STAGE 2: CALCULATION SNAPSHOT
-- ========================================

CREATE TABLE IF NOT EXISTS payroll_calculations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Link to work units
  work_unit_id UUID NOT NULL REFERENCES payroll_work_units(id),
  payroll_period_id UUID NOT NULL REFERENCES payroll_periods(id),
  guard_id UUID NOT NULL REFERENCES guards(id),
  
  -- Salary snapshot (IMMUTABLE)
  basic_snapshot DECIMAL(10, 2) NOT NULL,      -- Salary at snapshot time
  days_in_month INTEGER NOT NULL,              -- Calendar days in month
  
  -- Calculated rates (IMMUTABLE)
  daily_rate DECIMAL(10, 2) NOT NULL,          -- basic_snapshot / days_in_month
  
  -- Earnings (IMMUTABLE)
  earned_basic DECIMAL(10, 2) NOT NULL,        -- daily_rate * present_days
  ot_pay DECIMAL(10, 2) DEFAULT 0,             -- daily_rate * ot_days
  total_earned DECIMAL(10, 2) NOT NULL,        -- earned_basic + ot_pay
  
  -- Statutory deductions (IMMUTABLE based on snapshot)
  pf_amount DECIMAL(10, 2) DEFAULT 0,          -- Provident Fund (12% logic)
  pt_amount DECIMAL(10, 2) DEFAULT 0,          -- Professional Tax (threshold logic)
  
  -- Work unit counts (copied for audit)
  present_days DECIMAL(5, 2) NOT NULL,
  auto_present_days DECIMAL(5, 2) DEFAULT 0,
  replacement_days DECIMAL(5, 2) DEFAULT 0,
  ot_days DECIMAL(5, 2) DEFAULT 0,
  
  -- Snapshot metadata
  snapshot_at TIMESTAMPTZ DEFAULT NOW(),
  snapshot_by UUID REFERENCES users(id),
  calculation_locked BOOLEAN DEFAULT true,     -- ALWAYS true after creation
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(payroll_period_id, guard_id)
);

CREATE INDEX idx_payroll_calculations_period ON payroll_calculations(payroll_period_id);
CREATE INDEX idx_payroll_calculations_guard ON payroll_calculations(guard_id);
CREATE INDEX idx_payroll_calculations_work_unit ON payroll_calculations(work_unit_id);

COMMENT ON TABLE payroll_calculations IS 
'Stage 2: Immutable calculation snapshot - wage calculations frozen at generation time';

COMMENT ON COLUMN payroll_calculations.calculation_locked IS 
'Always true - calculations never modified after creation';

-- ========================================
-- STAGE 3: SETTLEMENT LAYER
-- ========================================

CREATE TABLE IF NOT EXISTS payroll_settlements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Link to calculation
  calculation_id UUID NOT NULL REFERENCES payroll_calculations(id),
  payroll_period_id UUID NOT NULL REFERENCES payroll_periods(id),
  guard_id UUID NOT NULL REFERENCES guards(id),
  
  -- Copy from calculation (for convenience)
  total_earned DECIMAL(10, 2) NOT NULL,
  pf_amount DECIMAL(10, 2) DEFAULT 0,
  pt_amount DECIMAL(10, 2) DEFAULT 0,
  
  -- Manual deductions/adjustments
  advance_deduction DECIMAL(10, 2) DEFAULT 0,
  canteen_deduction DECIMAL(10, 2) DEFAULT 0,
  uniform_deduction DECIMAL(10, 2) DEFAULT 0,
  other_deduction DECIMAL(10, 2) DEFAULT 0,
  hold_amount DECIMAL(10, 2) DEFAULT 0,          -- Amount put on hold (disputes)
  
  -- Manual additions
  bonus DECIMAL(10, 2) DEFAULT 0,
  allowance DECIMAL(10, 2) DEFAULT 0,
  
  -- Final calculation
  total_deductions DECIMAL(10, 2) GENERATED ALWAYS AS (
    pf_amount + pt_amount + advance_deduction + canteen_deduction + 
    uniform_deduction + other_deduction + hold_amount
  ) STORED,
  
  final_payable DECIMAL(10, 2) GENERATED ALWAYS AS (
    total_earned + bonus + allowance - (
      pf_amount + pt_amount + advance_deduction + canteen_deduction + 
      uniform_deduction + other_deduction + hold_amount
    )
  ) STORED,
  
  -- Payment details
  payment_mode TEXT CHECK (payment_mode IN ('BANK_TRANSFER', 'CASH', 'CHEQUE', 'UPI')),
  payment_status TEXT DEFAULT 'PENDING' CHECK (payment_status IN (
    'PENDING',      -- Not yet paid
    'PROCESSING',   -- Payment initiated
    'PAID',         -- Successfully paid
    'FAILED',       -- Payment failed
    'ON_HOLD'       -- Payment held (disputes, etc.)
  )),
  payment_reference TEXT,                        -- Bank transaction ID, cheque number, etc.
  payment_date TIMESTAMPTZ,
  
  -- Settlement status
  settlement_locked BOOLEAN DEFAULT false,       -- Locked when payroll closed
  locked_at TIMESTAMPTZ,
  locked_by UUID REFERENCES users(id),
  
  -- Notes
  settlement_notes TEXT,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(payroll_period_id, guard_id)
);

CREATE INDEX idx_payroll_settlements_period ON payroll_settlements(payroll_period_id);
CREATE INDEX idx_payroll_settlements_guard ON payroll_settlements(guard_id);
CREATE INDEX idx_payroll_settlements_calculation ON payroll_settlements(calculation_id);
CREATE INDEX idx_payroll_settlements_status ON payroll_settlements(payment_status);

COMMENT ON TABLE payroll_settlements IS 
'Stage 3: Settlement layer - deductions, adjustments, and payment tracking';

-- ========================================
-- FUNCTION: AGGREGATE WORK UNITS
-- ========================================

CREATE OR REPLACE FUNCTION aggregate_work_units(
  p_period_id UUID,
  p_org_id UUID
)
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
  -- Get period details
  SELECT * INTO v_period FROM payroll_periods WHERE id = p_period_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'PERIOD_NOT_FOUND');
  END IF;
  
  -- Loop through each guard with attendance in period
  FOR v_guard_id IN
    SELECT DISTINCT a.guard_id
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    JOIN units u ON u.id = a.unit_id
    WHERE u.organization_id = p_org_id
      AND a.attendance_date >= v_period.start_date
      AND a.attendance_date <= v_period.end_date
      AND si.status IN ('CONFIRMED', 'AUTO_CONFIRMED', 'PAYROLL_LOCKED')
  LOOP
    -- Count present days (CONFIRMED only)
    SELECT COUNT(DISTINCT si.shift_date) INTO v_present_count
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    JOIN units u ON u.id = a.unit_id
    WHERE u.organization_id = p_org_id
      AND a.guard_id = v_guard_id
      AND a.attendance_date >= v_period.start_date
      AND a.attendance_date <= v_period.end_date
      AND si.status = 'CONFIRMED'
      AND si.auto_confirm_reason IS NULL;
    
    -- Count auto-present days (AUTO_CONFIRMED)
    SELECT COUNT(DISTINCT si.shift_date) INTO v_auto_present_count
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    JOIN units u ON u.id = a.unit_id
    WHERE u.organization_id = p_org_id
      AND a.guard_id = v_guard_id
      AND a.attendance_date >= v_period.start_date
      AND a.attendance_date <= v_period.end_date
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
    JOIN units u ON u.id = a.unit_id
    WHERE u.organization_id = p_org_id
      AND a.guard_id = v_guard_id
      AND a.attendance_date >= v_period.start_date
      AND a.attendance_date <= v_period.end_date
      AND si.status IN ('CONFIRMED', 'AUTO_CONFIRMED', 'PAYROLL_LOCKED');
    
    -- OT days (example: count as 0 for now - implement OT logic separately)
    v_ot_count := 0;
    
    -- Collect shift instance IDs
    SELECT array_agg(DISTINCT si.id) INTO v_shift_ids
    FROM attendance a
    JOIN shift_instances si ON si.id = a.shift_instance_id
    JOIN units u ON u.id = a.unit_id
    WHERE u.organization_id = p_org_id
      AND a.guard_id = v_guard_id
      AND a.attendance_date >= v_period.start_date
      AND a.attendance_date <= v_period.end_date
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
      p_org_id,
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

COMMENT ON FUNCTION aggregate_work_units IS 
'Stage 1: Aggregate work units from finalized shift instances - counts only, no money';

-- ========================================
-- FUNCTION: GENERATE PAYROLL CALCULATIONS
-- ========================================

CREATE OR REPLACE FUNCTION generate_payroll_calculations(
  p_period_id UUID,
  p_generated_by UUID
)
RETURNS JSONB AS $$
DECLARE
  v_period payroll_periods;
  v_work_unit payroll_work_units;
  v_guard guards;
  v_basic_snapshot DECIMAL;
  v_days_in_month INTEGER;
  v_daily_rate DECIMAL;
  v_earned_basic DECIMAL;
  v_ot_pay DECIMAL;
  v_total_earned DECIMAL;
  v_pf DECIMAL;
  v_pt DECIMAL;
  v_calculations_created INTEGER := 0;
BEGIN
  -- Get period
  SELECT * INTO v_period FROM payroll_periods WHERE id = p_period_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'PERIOD_NOT_FOUND');
  END IF;
  
  -- Calculate days in month
  v_days_in_month := EXTRACT(DAY FROM (
    DATE_TRUNC('MONTH', v_period.end_date) + INTERVAL '1 MONTH' - INTERVAL '1 DAY'
  ))::INTEGER;
  
  -- Loop through work units
  FOR v_work_unit IN
    SELECT * FROM payroll_work_units
    WHERE payroll_period_id = p_period_id
      AND aggregation_status = 'DRAFT'
  LOOP
    -- Get guard salary snapshot
    SELECT * INTO v_guard FROM guards WHERE id = v_work_unit.guard_id;
    v_basic_snapshot := COALESCE(v_guard.salary, 0);
    
    -- Calculate daily rate
    v_daily_rate := v_basic_snapshot / v_days_in_month;
    
    -- Calculate earned basic (only present_days + auto_present_days count)
    v_earned_basic := v_daily_rate * (v_work_unit.present_days + v_work_unit.auto_present_days);
    
    -- Calculate OT pay
    v_ot_pay := v_daily_rate * v_work_unit.ot_days;
   
    -- Total earned
    v_total_earned := v_earned_basic + v_ot_pay;
    
    -- ========================================
    -- STATUTORY DEDUCTIONS
    -- ========================================
    
    -- PF: 12% on basic (capped at 15000 base)
    IF v_basic_snapshot >= 15000 THEN
      v_pf := 15000 * 0.12;
    ELSE
      v_pf := v_earned_basic * 0.12;
    END IF;
    
    -- PT: Professional Tax (threshold-based)
    IF v_total_earned >= 12000 THEN
      v_pt := 200;
    ELSE
      v_pt := 0;
    END IF;
    
    -- Create calculation (IMMUTABLE)
    INSERT INTO payroll_calculations (
      work_unit_id,
      payroll_period_id,
      guard_id,
      basic_snapshot,
      days_in_month,
      daily_rate,
      earned_basic,
      ot_pay,
      total_earned,
      pf_amount,
      pt_amount,
      present_days,
      auto_present_days,
      replacement_days,
      ot_days,
      snapshot_at,
      snapshot_by,
      calculation_locked
    )
    VALUES (
      v_work_unit.id,
      p_period_id,
      v_work_unit.guard_id,
      v_basic_snapshot,
      v_days_in_month,
      v_daily_rate,
      v_earned_basic,
      v_ot_pay,
      v_total_earned,
      v_pf,
      v_pt,
      v_work_unit.present_days,
      v_work_unit.auto_present_days,
      v_work_unit.replacement_days,
      v_work_unit.ot_days,
      NOW(),
      p_generated_by,
      true  -- Always locked
    );
    
    -- Mark work unit as finalized
    UPDATE payroll_work_units
    SET aggregation_status = 'FINALIZED', updated_at = NOW()
    WHERE id = v_work_unit.id;
    
    v_calculations_created := v_calculations_created + 1;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'calculations_created', v_calculations_created,
    'period_id', p_period_id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION generate_payroll_calculations IS 
'Stage 2: Generate immutable payroll calculations from work units';

-- ========================================
-- FUNCTION: CREATE SETTLEMENTS
-- ========================================

CREATE OR REPLACE FUNCTION create_payroll_settlements(
  p_period_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_calculation payroll_calculations;
  v_settlements_created INTEGER := 0;
BEGIN
  -- Create settlement for each calculation
  FOR v_calculation IN
    SELECT * FROM payroll_calculations
    WHERE payroll_period_id = p_period_id
  LOOP
    INSERT INTO payroll_settlements (
      calculation_id,
      payroll_period_id,
      guard_id,
      total_earned,
      pf_amount,
      pt_amount,
      payment_status
    )
    VALUES (
      v_calculation.id,
      p_period_id,
      v_calculation.guard_id,
      v_calculation.total_earned,
      v_calculation.pf_amount,
      v_calculation.pt_amount,
      'PENDING'
    )
    ON CONFLICT (payroll_period_id, guard_id) DO NOTHING;
    
    v_settlements_created := v_settlements_created + 1;
  END LOOP;
  
  RETURN jsonb_build_object(
    'success', true,
    'settlements_created', v_settlements_created
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION create_payroll_settlements IS 
'Stage 3: Create settlement records from calculations';

-- ========================================
-- PAYROLL GENERATION WORKFLOW
-- ========================================

CREATE OR REPLACE FUNCTION run_payroll_generation(
  p_period_id UUID,
  p_org_id UUID,
  p_generated_by UUID
)
RETURNS JSONB AS $$
DECLARE
  v_stage1 JSONB;
  v_stage2 JSONB;
  v_stage3 JSONB;
BEGIN
  -- Stage 1: Aggregate work units
  v_stage1 := aggregate_work_units(p_period_id, p_org_id);
  
  IF v_stage1->>'success' = 'false' THEN
    RETURN v_stage1;
  END IF;
  
  -- Stage 2: Generate calculations
  v_stage2 := generate_payroll_calculations(p_period_id, p_generated_by);
  
  IF v_stage2->>'success' = 'false' THEN
    RETURN v_stage2;
  END IF;
  
  -- Stage 3: Create settlements
  v_stage3 := create_payroll_settlements(p_period_id);
  
  IF v_stage3->>'success' = 'false' THEN
    RETURN v_stage3;
  END IF;
  
  RETURN jsonb_build_object(
    'success', true,
    'stage1', v_stage1,
    'stage2', v_stage2,
    'stage3', v_stage3
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION run_payroll_generation IS 
'Complete payroll generation: Stage 1 (work units) → Stage 2 (calculations) → Stage 3 (settlements)';
