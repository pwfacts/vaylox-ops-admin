-- ============================================
-- PAYROLL SALARY OVERRIDE SYSTEM
-- Allows per-period salary adjustments without modifying employee master
-- ============================================

-- ========================================
-- 1. MODIFY PAYROLL_CALCULATIONS TABLE
-- ========================================

-- Add override fields and computed columns
ALTER TABLE payroll_calculations 
  ADD COLUMN IF NOT EXISTS basic_override NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS ot_basic_snapshot NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS ot_basic_override NUMERIC(10, 2);

-- Add computed effective values
ALTER TABLE payroll_calculations
  ADD COLUMN IF NOT EXISTS effective_basic NUMERIC(10, 2) 
    GENERATED ALWAYS AS (COALESCE(basic_override, basic_snapshot)) STORED,
  ADD COLUMN IF NOT EXISTS effective_ot_basic NUMERIC(10, 2)
    GENERATED ALWAYS AS (COALESCE(ot_basic_override, ot_basic_snapshot)) STORED;

-- Add override metadata
ALTER TABLE payroll_calculations
  ADD COLUMN IF NOT EXISTS override_applied BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS override_applied_by UUID REFERENCES users(id),
  ADD COLUMN IF NOT EXISTS override_applied_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS override_reason TEXT;

COMMENT ON COLUMN payroll_calculations.basic_override IS 
'Monthly basic salary override - does not modify employee master data';

COMMENT ON COLUMN payroll_calculations.ot_basic_override IS 
'Monthly OT basic override - separate from regular basic';

COMMENT ON COLUMN payroll_calculations.effective_basic IS 
'Computed: COALESCE(basic_override, basic_snapshot) - actual value used for payroll';

COMMENT ON COLUMN payroll_calculations.effective_ot_basic IS 
'Computed: COALESCE(ot_basic_override, ot_basic_snapshot) - actual OT base used';

-- ========================================
-- 2. PAYROLL OVERRIDE AUDIT LOG
-- ========================================

CREATE TABLE IF NOT EXISTS payroll_override_audit (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  -- Target
  calculation_id UUID NOT NULL REFERENCES payroll_calculations(id),
  payroll_period_id UUID NOT NULL REFERENCES payroll_periods(id),
  guard_id UUID NOT NULL REFERENCES guards(id),
  
  -- Change details
  field_name TEXT NOT NULL CHECK (field_name IN ('basic_override', 'ot_basic_override')),
  old_value NUMERIC(10, 2),
  new_value NUMERIC(10, 2),
  
  -- Audit metadata
  changed_by UUID NOT NULL REFERENCES users(id),
  changed_at TIMESTAMPTZ DEFAULT NOW(),
  reason TEXT,
  
  -- Context
  period_status_at_change TEXT,
  settlement_locked_at_change BOOLEAN
);

CREATE INDEX idx_payroll_override_audit_calculation ON payroll_override_audit(calculation_id);
CREATE INDEX idx_payroll_override_audit_period ON payroll_override_audit(payroll_period_id);
CREATE INDEX idx_payroll_override_audit_guard ON payroll_override_audit(guard_id);
CREATE INDEX idx_payroll_override_audit_changed_by ON payroll_override_audit(changed_by);

COMMENT ON TABLE payroll_override_audit IS 
'Audit trail for all payroll salary override changes';

-- ========================================
-- 3. UPDATE PAYROLL CALCULATION LOGIC
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
  v_basic_snapshot NUMERIC;
  v_ot_basic_snapshot NUMERIC;
  v_days_in_month INTEGER;
  v_daily_rate NUMERIC;
  v_ot_daily_rate NUMERIC;
  v_earned_basic NUMERIC;
  v_ot_pay NUMERIC;
  v_total_earned NUMERIC;
  v_pf NUMERIC;
  v_pt NUMERIC;
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
    
    -- OT basic defaults to same as basic (can be overridden separately)
    v_ot_basic_snapshot := v_basic_snapshot;
    
    -- Calculate daily rates (using snapshot, overrides applied later if needed)
    v_daily_rate := v_basic_snapshot / v_days_in_month;
    v_ot_daily_rate := v_ot_basic_snapshot / v_days_in_month;
    
    -- Calculate earned basic
    v_earned_basic := v_daily_rate * (v_work_unit.present_days + v_work_unit.auto_present_days);
    
    -- Calculate OT pay
    v_ot_pay := v_ot_daily_rate * v_work_unit.ot_days;
   
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
    
    -- Create calculation with override fields (initially NULL)
    INSERT INTO payroll_calculations (
      work_unit_id,
      payroll_period_id,
      guard_id,
      basic_snapshot,
      ot_basic_snapshot,
      basic_override,
      ot_basic_override,
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
      calculation_locked,
      override_applied
    )
    VALUES (
      v_work_unit.id,
      p_period_id,
      v_work_unit.guard_id,
      v_basic_snapshot,
      v_ot_basic_snapshot,
      NULL,  -- No override initially
      NULL,  -- No OT override initially
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
      true,
      false  -- No override applied yet
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

-- ========================================
-- 4. APPLY SALARY OVERRIDE FUNCTION
-- ========================================

CREATE OR REPLACE FUNCTION apply_payroll_override(
  p_calculation_id UUID,
  p_basic_override NUMERIC DEFAULT NULL,
  p_ot_basic_override NUMERIC DEFAULT NULL,
  p_admin_user_id UUID,
  p_reason TEXT
)
RETURNS JSONB AS $$
DECLARE
  v_calculation payroll_calculations;
  v_period payroll_periods;
  v_settlement payroll_settlements;
  v_admin_role TEXT;
  v_old_basic_override NUMERIC;
  v_old_ot_basic_override NUMERIC;
  v_new_daily_rate NUMERIC;
  v_new_ot_daily_rate NUMERIC;
  v_new_earned_basic NUMERIC;
  v_new_ot_pay NUMERIC;
  v_new_total_earned NUMERIC;
  v_new_pf NUMERIC;
  v_new_pt NUMERIC;
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
      'message', format('Period status is %s - overrides only allowed when OPEN', v_period.status)
    );
  END IF;
  
  -- Check if settlement is locked
  SELECT * INTO v_settlement 
  FROM payroll_settlements 
  WHERE calculation_id = p_calculation_id;
  
  IF v_settlement.settlement_locked THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'SETTLEMENT_LOCKED',
      'message', 'Settlement is locked - cannot modify overrides'
    );
  END IF;
  
  -- Verify user is ADMIN
  SELECT role INTO v_admin_role
  FROM users
  WHERE id = p_admin_user_id;
  
  IF v_admin_role != 'ADMIN' AND v_admin_role != 'SUPER_ADMIN' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'PERMISSION_DENIED',
      'message', 'Only ADMIN users can apply salary overrides'
    );
  END IF;
  
  -- Store old values for audit
  v_old_basic_override := v_calculation.basic_override;
  v_old_ot_basic_override := v_calculation.ot_basic_override;
  
  -- Calculate new values using effective amounts
  v_new_daily_rate := COALESCE(p_basic_override, v_calculation.basic_snapshot) / v_calculation.days_in_month;
  v_new_ot_daily_rate := COALESCE(p_ot_basic_override, v_calculation.ot_basic_snapshot) / v_calculation.days_in_month;
  
  v_new_earned_basic := v_new_daily_rate * (v_calculation.present_days + v_calculation.auto_present_days);
  v_new_ot_pay := v_new_ot_daily_rate * v_calculation.ot_days;
  v_new_total_earned := v_new_earned_basic + v_new_ot_pay;
  
  -- Recalculate PF using effective basic
  IF COALESCE(p_basic_override, v_calculation.basic_snapshot) >= 15000 THEN
    v_new_pf := 15000 * 0.12;
  ELSE
    v_new_pf := v_new_earned_basic * 0.12;
  END IF;
  
  -- Recalculate PT
  IF v_new_total_earned >= 12000 THEN
    v_new_pt := 200;
  ELSE
    v_new_pt := 0;
  END IF;
  
  -- Update calculation with overrides
  UPDATE payroll_calculations
  SET
    basic_override = p_basic_override,
    ot_basic_override = p_ot_basic_override,
    daily_rate = v_new_daily_rate,
    earned_basic = v_new_earned_basic,
    ot_pay = v_new_ot_pay,
    total_earned = v_new_total_earned,
    pf_amount = v_new_pf,
    pt_amount = v_new_pt,
    override_applied = (p_basic_override IS NOT NULL OR p_ot_basic_override IS NOT NULL),
    override_applied_by = p_admin_user_id,
    override_applied_at = NOW(),
    override_reason = p_reason,
    updated_at = NOW()
  WHERE id = p_calculation_id;
  
  -- Audit log for basic override
  IF p_basic_override IS DISTINCT FROM v_old_basic_override THEN
    INSERT INTO payroll_override_audit (
      calculation_id,
      payroll_period_id,
      guard_id,
      field_name,
      old_value,
      new_value,
      changed_by,
      reason,
      period_status_at_change,
      settlement_locked_at_change
    )
    VALUES (
      p_calculation_id,
      v_calculation.payroll_period_id,
      v_calculation.guard_id,
      'basic_override',
      v_old_basic_override,
      p_basic_override,
      p_admin_user_id,
      p_reason,
      v_period.status,
      v_settlement.settlement_locked
    );
  END IF;
  
  -- Audit log for OT override
  IF p_ot_basic_override IS DISTINCT FROM v_old_ot_basic_override THEN
    INSERT INTO payroll_override_audit (
      calculation_id,
      payroll_period_id,
      guard_id,
      field_name,
      old_value,
      new_value,
      changed_by,
      reason,
      period_status_at_change,
      settlement_locked_at_change
    )
    VALUES (
      p_calculation_id,
      v_calculation.payroll_period_id,
      v_calculation.guard_id,
      'ot_basic_override',
      v_old_ot_basic_override,
      p_ot_basic_override,
      p_admin_user_id,
      p_reason,
      v_period.status,
      v_settlement.settlement_locked
    );
  END IF;
  
  -- Update settlement total_earned
  UPDATE payroll_settlements
  SET
    total_earned = v_new_total_earned,
    pf_amount = v_new_pf,
    pt_amount = v_new_pt,
    updated_at = NOW()
  WHERE calculation_id = p_calculation_id;
  
  RETURN jsonb_build_object(
    'success', true,
    'calculation_id', p_calculation_id,
    'old_basic', v_calculation.basic_snapshot,
    'new_basic', COALESCE(p_basic_override, v_calculation.basic_snapshot),
    'old_total_earned', v_calculation.total_earned,
    'new_total_earned', v_new_total_earned,
    'override_applied', true
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION apply_payroll_override IS 
'Apply monthly salary override without modifying employee master data - ADMIN only, period must be OPEN';

-- ========================================
-- 5. REMOVE SALARY OVERRIDE FUNCTION
-- ========================================

CREATE OR REPLACE FUNCTION remove_payroll_override(
  p_calculation_id UUID,
  p_admin_user_id UUID,
  p_reason TEXT
)
RETURNS JSONB AS $$
BEGIN
  -- Simply set overrides to NULL (which reverts to snapshot values)
  RETURN apply_payroll_override(
    p_calculation_id,
    NULL,  -- Remove basic override
    NULL,  -- Remove OT override
    p_admin_user_id,
    p_reason
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION remove_payroll_override IS 
'Remove salary override and revert to snapshot values';

-- ========================================
-- 6. VIEW: PAYROLL WITH OVERRIDES
-- ========================================

CREATE OR REPLACE VIEW payroll_with_overrides AS
SELECT 
  pc.id AS calculation_id,
  pc.payroll_period_id,
  pp.month AS period_month,
  pp.year AS period_year,
  pc.guard_id,
  g.full_name AS guard_name,
  
  -- Snapshot values
  pc.basic_snapshot,
  pc.ot_basic_snapshot,
  
  -- Override values
  pc.basic_override,
  pc.ot_basic_override,
  
  -- Effective values (computed)
  pc.effective_basic,
  pc.effective_ot_basic,
  
  -- Override metadata
  pc.override_applied,
  pc.override_applied_by,
  pc.override_applied_at,
  pc.override_reason,
  u.email AS override_applied_by_email,
  
  -- Work units
  pc.present_days,
  pc.auto_present_days,
  pc.ot_days,
  
  -- Earnings
  pc.earned_basic,
  pc.ot_pay,
  pc.total_earned,
  
  -- Deductions
  pc.pf_amount,
  pc.pt_amount,
  
  -- Settlement
  ps.final_payable,
  ps.payment_status
FROM payroll_calculations pc
JOIN payroll_periods pp ON pp.id = pc.payroll_period_id
JOIN guards g ON g.id = pc.guard_id
LEFT JOIN users u ON u.id = pc.override_applied_by
LEFT JOIN payroll_settlements ps ON ps.calculation_id = pc.id;

COMMENT ON VIEW payroll_with_overrides IS 
'Payroll calculations with override information';

-- ========================================
-- 7. RLS POLICIES FOR OVERRIDES
-- ========================================

-- Only ADMIN can view/modify override fields
CREATE POLICY payroll_override_admin_only ON payroll_calculations
  FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM users
      WHERE id = auth.uid()
        AND role IN ('ADMIN', 'SUPER_ADMIN')
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM users
      WHERE id = auth.uid()
        AND role IN ('ADMIN', 'SUPER_ADMIN')
    )
  );

COMMENT ON POLICY payroll_override_admin_only ON payroll_calculations IS 
'Only ADMIN users can modify salary overrides';
