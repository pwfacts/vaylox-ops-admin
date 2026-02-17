-- ============================================
-- PAYROLL REFACTOR: 3-LAYER MODEL
-- Security Agency Business Logic (Correct Implementation)
-- ============================================

-- LAYER 1: Contract Salary (Master Data)
-- LAYER 2: Attendance Earnings
-- LAYER 3: Monthly Adjustments

-- ========================================
-- CONFIGURATION: WORKING DAYS RULE
-- ========================================

-- Add organization-level working days configuration
ALTER TABLE organizations
  ADD COLUMN IF NOT EXISTS payroll_working_days_rule INTEGER DEFAULT 26 
    CHECK (payroll_working_days_rule IN (26, 27, 28, 30, 31));

COMMENT ON COLUMN organizations.payroll_working_days_rule IS 
'Working days divisor for daily rate calculation (26/27/30/31 per agency practice)';

-- Unit-level override (optional)
ALTER TABLE units
  ADD COLUMN IF NOT EXISTS working_days_override INTEGER 
    CHECK (working_days_override IN (26, 27, 28, 30, 31));

COMMENT ON COLUMN units.working_days_override IS 
'Unit-specific working days override (NULL = use organization default)';

-- ========================================
-- LAYER 3: PAYROLL ADJUSTMENTS TABLE
-- ========================================

CREATE TABLE IF NOT EXISTS payroll_adjustments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Links
  organization_id UUID NOT NULL REFERENCES organizations(id),
  payroll_calculation_id UUID NOT NULL REFERENCES payroll_calculations(id),
  guard_profile_id UUID NOT NULL REFERENCES workforce_profiles(id),
  payroll_period_id UUID NOT NULL REFERENCES payroll_periods(id),
  
  -- Adjustment details
  adjustment_type TEXT NOT NULL CHECK (adjustment_type IN (
    'ALLOWANCE',      -- Extra allowance (conveyance, mobile, etc.)
    'BONUS',          -- Performance/festival bonus
    'DEDUCTION',      -- Misc deduction
    'RECOVERY',       -- Advance recovery, loan repayment
    'CORRECTION',     -- Admin correction
    'CLIENT_EXTRA',   -- Client-specific extra payment
    'ROUNDING'        -- Rounding adjustment
  )),
  
  label TEXT NOT NULL,                    -- Display label (e.g., "Festival Bonus")
  amount NUMERIC(10, 2) NOT NULL,         -- Positive = credit, Negative = debit
  
  -- Metadata
  created_by UUID NOT NULL REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  note TEXT,
  
  -- Approval (optional)
  approved_by UUID REFERENCES users(id),
  approved_at TIMESTAMPTZ,
  approval_status TEXT DEFAULT 'PENDING' CHECK (approval_status IN ('PENDING', 'APPROVED', 'REJECTED'))
);

CREATE INDEX idx_payroll_adjustments_calculation ON payroll_adjustments(payroll_calculation_id);
CREATE INDEX idx_payroll_adjustments_period ON payroll_adjustments(payroll_period_id);
CREATE INDEX idx_payroll_adjustments_guard ON payroll_adjustments(guard_profile_id);
CREATE INDEX idx_payroll_adjustments_type ON payroll_adjustments(adjustment_type);

COMMENT ON TABLE payroll_adjustments IS 
'Layer 3: Monthly payment adjustments - DO NOT affect PF/PT, only net pay';

-- ========================================
-- REFACTOR: PAYROLL_CALCULATIONS
-- ========================================

-- Add contract salary tracking
ALTER TABLE payroll_calculations
  ADD COLUMN IF NOT EXISTS contract_basic NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS contract_ot_basic NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS working_days_rule INTEGER;

-- Mark override fields as deprecated (keep for audit/backward compat)
COMMENT ON COLUMN payroll_calculations.basic_override IS 
'DEPRECATED: Use payroll_adjustments instead. Kept for audit/correction only.';

COMMENT ON COLUMN payroll_calculations.ot_basic_override IS 
'DEPRECATED: Use payroll_adjustments instead. Kept for audit/correction only.';

COMMENT ON COLUMN payroll_calculations.contract_basic IS 
'Contract salary from employee master - USED FOR PF/PT calculation';

COMMENT ON COLUMN payroll_calculations.contract_ot_basic IS 
'Contract OT base - may differ from basic per agency practice';

COMMENT ON COLUMN payroll_calculations.working_days_rule IS 
'Working days divisor used for this calculation (26/27/30/31)';

-- Add adjustment totals (computed)
ALTER TABLE payroll_calculations
  ADD COLUMN IF NOT EXISTS total_adjustments_credit NUMERIC(10, 2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_adjustments_debit NUMERIC(10, 2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS gross_earnings NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS net_pay NUMERIC(10, 2);

COMMENT ON COLUMN payroll_calculations.gross_earnings IS 
'earned_basic + ot_pay + total_adjustments_credit';

COMMENT ON COLUMN payroll_calculations.net_pay IS 
'gross_earnings - (pf_amount + pt_amount + total_adjustments_debit)';

-- ========================================
-- REFACTORED: PAYROLL GENERATION
-- ========================================

CREATE OR REPLACE FUNCTION generate_payroll_calculations_v2(
  p_period_id UUID,
  p_org_id UUID,
  p_generated_by UUID
)
RETURNS JSONB AS $$
DECLARE
  v_period payroll_periods;
  v_work_unit payroll_work_units;
  v_guard guards;
  v_profile workforce_profiles;
  v_org organizations;
  
  -- Contract salary (LAYER 1)
  v_contract_basic NUMERIC;
  v_contract_ot_basic NUMERIC;
  
  -- Working days rule
  v_working_days_rule INTEGER;
  v_days_in_month INTEGER;
  
  -- Rates (LAYER 2)
  v_daily_rate NUMERIC;
  v_ot_daily_rate NUMERIC;
  
  -- Earnings (LAYER 2)
  v_earned_basic NUMERIC;
  v_ot_pay NUMERIC;
  
  -- Statutory (uses LAYER 1 contract)
  v_pf NUMERIC;
  v_pt NUMERIC;
  
  -- Totals
  v_gross_earnings NUMERIC;
  v_net_pay NUMERIC;
  
  v_calculations_created INTEGER := 0;
BEGIN
  -- Get period
  SELECT * INTO v_period FROM payroll_periods WHERE id = p_period_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'PERIOD_NOT_FOUND');
  END IF;
  
  -- Get organization
  SELECT * INTO v_org FROM organizations WHERE id = p_org_id;
  
  -- Calculate calendar days in month
  v_days_in_month := EXTRACT(DAY FROM (
    DATE_TRUNC('MONTH', v_period.end_date) + INTERVAL '1 MONTH' - INTERVAL '1 DAY'
  ))::INTEGER;
  
  -- Loop through work units
  FOR v_work_unit IN
    SELECT * FROM payroll_work_units
    WHERE payroll_period_id = p_period_id
      AND aggregation_status = 'DRAFT'
  LOOP
    -- Get guard and profile
    SELECT * INTO v_guard FROM guards WHERE id = v_work_unit.guard_id;
    
    SELECT * INTO v_profile 
    FROM workforce_profiles 
    WHERE linked_auth_user = (SELECT id FROM guards WHERE id = v_work_unit.guard_id LIMIT 1);
    
    -- ========================================
    -- LAYER 1: CONTRACT SALARY (from master)
    -- ========================================
    v_contract_basic := COALESCE(v_guard.salary, 0);
    v_contract_ot_basic := COALESCE(v_guard.salary, 0);  -- Default same, can differ
    
    -- Get working days rule (unit override or org default)
    SELECT COALESCE(u.working_days_override, v_org.payroll_working_days_rule, 26)
    INTO v_working_days_rule
    FROM units u
    WHERE u.id = v_work_unit.unit_id;
    
    -- ========================================
    -- LAYER 2: ATTENDANCE EARNINGS
    -- ========================================
    
    -- Calculate daily rates using working days rule
    v_daily_rate := v_contract_basic / v_working_days_rule;
    v_ot_daily_rate := v_contract_ot_basic / v_working_days_rule;
    
    -- Calculate earned basic (present + auto_present)
    v_earned_basic := v_daily_rate * (v_work_unit.present_days + v_work_unit.auto_present_days);
    
    -- Calculate OT pay
    v_ot_pay := v_ot_daily_rate * v_work_unit.ot_days;
   
    -- ========================================
    -- STATUTORY DEDUCTIONS (use CONTRACT_BASIC)
    -- ========================================
    
    -- PF: 12% on contract basic (capped at 15000)
    IF v_contract_basic >= 15000 THEN
      v_pf := 15000 * 0.12;
    ELSE
      -- Use contract basic for PF, not earned
      v_pf := v_contract_basic * 0.12;
    END IF;
    
    -- PT: Based on contract basic
    IF v_contract_basic >= 12000 THEN
      v_pt := 200;
    ELSE
      v_pt := 0;
    END IF;
    
    -- ========================================
    -- INITIAL TOTALS (before adjustments)
    -- ========================================
    v_gross_earnings := v_earned_basic + v_ot_pay;
    v_net_pay := v_gross_earnings - v_pf - v_pt;
    
    -- Create calculation
    INSERT INTO payroll_calculations (
      work_unit_id,
      payroll_period_id,
      guard_id,
      
      -- Contract salary (LAYER 1)
      contract_basic,
      contract_ot_basic,
      working_days_rule,
      
      -- Legacy fields (for backward compat)
      basic_snapshot,
      ot_basic_snapshot,
      days_in_month,
      
      -- Rates (LAYER 2)
      daily_rate,
      
      -- Earnings (LAYER 2)
      earned_basic,
      ot_pay,
      
      -- Statutory (uses LAYER 1)
      pf_amount,
      pt_amount,
      
      -- Totals
      total_earned,
      gross_earnings,
      net_pay,
      
      -- Work units
      present_days,
      auto_present_days,
      replacement_days,
      ot_days,
      
      -- Metadata
      snapshot_at,
      snapshot_by,
      calculation_locked,
      total_adjustments_credit,
      total_adjustments_debit
    )
    VALUES (
      v_work_unit.id,
      p_period_id,
      v_work_unit.guard_id,
      
      v_contract_basic,
      v_contract_ot_basic,
      v_working_days_rule,
      
      v_contract_basic,  -- Legacy
      v_contract_ot_basic,
      v_days_in_month,
      
      v_daily_rate,
      
      v_earned_basic,
      v_ot_pay,
      
      v_pf,
      v_pt,
      
      v_earned_basic + v_ot_pay,
      v_gross_earnings,
      v_net_pay,
      
      v_work_unit.present_days,
      v_work_unit.auto_present_days,
      v_work_unit.replacement_days,
      v_work_unit.ot_days,
      
      NOW(),
      p_generated_by,
      true,
      0,
      0
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

COMMENT ON FUNCTION generate_payroll_calculations_v2 IS 
'REFACTORED: 3-layer payroll - contract salary, attendance earnings, adjustments';

-- ========================================
-- FUNCTION: ADD PAYROLL ADJUSTMENT
-- ========================================

CREATE OR REPLACE FUNCTION add_payroll_adjustment(
  p_calculation_id UUID,
  p_adjustment_type TEXT,
  p_label TEXT,
  p_amount NUMERIC,
  p_note TEXT,
  p_created_by UUID
)
RETURNS JSONB AS $$
DECLARE
  v_calculation payroll_calculations;
  v_period payroll_periods;
  v_adjustment_id UUID;
  v_new_gross NUMERIC;
  v_new_net NUMERIC;
  v_total_credit NUMERIC;
  v_total_debit NUMERIC;
BEGIN
  -- Get calculation
  SELECT * INTO v_calculation FROM payroll_calculations WHERE id = p_calculation_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'CALCULATION_NOT_FOUND');
  END IF;
  
  -- Get period
  SELECT * INTO v_period FROM payroll_periods WHERE id = v_calculation.payroll_period_id;
  
  -- Verify period is OPEN
  IF v_period.status != 'OPEN' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'PERIOD_NOT_OPEN',
      'message', 'Cannot add adjustments to closed period'
    );
  END IF;
  
  -- Insert adjustment
  INSERT INTO payroll_adjustments (
    organization_id,
    payroll_calculation_id,
    guard_profile_id,
    payroll_period_id,
    adjustment_type,
    label,
    amount,
    created_by,
    note
  )
  VALUES (
    (SELECT organization_id FROM payroll_periods WHERE id = v_calculation.payroll_period_id),
    p_calculation_id,
    (SELECT id FROM workforce_profiles WHERE linked_auth_user = (
      SELECT id FROM guards WHERE id = v_calculation.guard_id LIMIT 1
    )),
    v_calculation.payroll_period_id,
    p_adjustment_type,
    p_label,
    p_amount,
    p_created_by,
    p_note
  )
  RETURNING id INTO v_adjustment_id;
  
  -- Recalculate totals
  SELECT 
    COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END), 0)
  INTO v_total_credit, v_total_debit
  FROM payroll_adjustments
  WHERE payroll_calculation_id = p_calculation_id;
  
  v_new_gross := v_calculation.earned_basic + v_calculation.ot_pay + v_total_credit;
  v_new_net := v_new_gross - v_calculation.pf_amount - v_calculation.pt_amount - v_total_debit;
  
  -- Update calculation
  UPDATE payroll_calculations
  SET
    total_adjustments_credit = v_total_credit,
    total_adjustments_debit = v_total_debit,
    gross_earnings = v_new_gross,
    net_pay = v_new_net,
    updated_at = NOW()
  WHERE id = p_calculation_id;
  
  -- Update settlement
  UPDATE payroll_settlements
  SET
    total_earned = v_new_gross,
    updated_at = NOW()
  WHERE calculation_id = p_calculation_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'adjustment_id', v_adjustment_id,
    'total_adjustments_credit', v_total_credit,
    'total_adjustments_debit', v_total_debit,
    'new_gross_earnings', v_new_gross,
    'new_net_pay', v_new_net
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION add_payroll_adjustment IS 
'Add monthly adjustment - does NOT affect PF/PT, only net pay';

-- ========================================
-- FUNCTION: REMOVE PAYROLL ADJUSTMENT
-- ========================================

CREATE OR REPLACE FUNCTION remove_payroll_adjustment(
  p_adjustment_id UUID,
  p_user_id UUID
)
RETURNS JSONB AS $$
DECLARE
  v_adjustment payroll_adjustments;
  v_calculation_id UUID;
BEGIN
  -- Get adjustment
  SELECT * INTO v_adjustment FROM payroll_adjustments WHERE id = p_adjustment_id;
  
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'ADJUSTMENT_NOT_FOUND');
  END IF;
  
  v_calculation_id := v_adjustment.payroll_calculation_id;
  
  -- Delete adjustment
  DELETE FROM payroll_adjustments WHERE id = p_adjustment_id;
  
  -- Recalculate totals by calling update trigger
  PERFORM recalculate_payroll_totals(v_calculation_id);
  
  RETURN jsonb_build_object('success', true, 'calculation_id', v_calculation_id);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ========================================
-- HELPER: RECALCULATE TOTALS
-- ========================================

CREATE OR REPLACE FUNCTION recalculate_payroll_totals(p_calculation_id UUID)
RETURNS VOID AS $$
DECLARE
  v_calculation payroll_calculations;
  v_total_credit NUMERIC;
  v_total_debit NUMERIC;
  v_new_gross NUMERIC;
  v_new_net NUMERIC;
BEGIN
  SELECT * INTO v_calculation FROM payroll_calculations WHERE id = p_calculation_id;
  
  SELECT 
    COALESCE(SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END), 0),
    COALESCE(SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END), 0)
  INTO v_total_credit, v_total_debit
  FROM payroll_adjustments
  WHERE payroll_calculation_id = p_calculation_id;
  
  v_new_gross := v_calculation.earned_basic + v_calculation.ot_pay + v_total_credit;
  v_new_net := v_new_gross - v_calculation.pf_amount - v_calculation.pt_amount - v_total_debit;
  
  UPDATE payroll_calculations
  SET
    total_adjustments_credit = v_total_credit,
    total_adjustments_debit = v_total_debit,
    gross_earnings = v_new_gross,
    net_pay = v_new_net,
    updated_at = NOW()
  WHERE id = p_calculation_id;
  
  UPDATE payroll_settlements
  SET total_earned = v_new_gross, updated_at = NOW()
  WHERE calculation_id = p_calculation_id;
END;
$$ LANGUAGE plpgsql;

-- ========================================
-- VIEW: PAYROLL WITH ADJUSTMENTS
-- ========================================

CREATE OR REPLACE VIEW payroll_with_adjustments AS
SELECT 
  pc.id AS calculation_id,
  pc.payroll_period_id,
  pp.month,
  pp.year,
  pc.guard_id,
  g.full_name AS guard_name,
  
  -- LAYER 1: Contract Salary
  pc.contract_basic,
  pc.contract_ot_basic,
  pc.working_days_rule,
  
  -- LAYER 2: Attendance Earnings
  pc.present_days,
  pc.auto_present_days,
  pc.ot_days,
  pc.earned_basic,
  pc.ot_pay,
  
  -- LAYER 3: Adjustments
  pc.total_adjustments_credit,
  pc.total_adjustments_debit,
  
  -- Statutory (based on contract)
  pc.pf_amount,
  pc.pt_amount,
  
  -- Totals
  pc.gross_earnings,
  pc.net_pay,
  
  -- Settlement
  ps.payment_status
FROM payroll_calculations pc
JOIN payroll_periods pp ON pp.id = pc.payroll_period_id
JOIN guards g ON g.id = pc.guard_id
LEFT JOIN payroll_settlements ps ON ps.calculation_id = pc.id;

COMMENT ON VIEW payroll_with_adjustments IS 
'Payroll with 3-layer breakdown: contract salary, earnings, adjustments';
