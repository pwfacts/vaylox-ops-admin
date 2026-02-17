# PAYROLL REFACTOR: 3-LAYER MODEL (CORRECT)

## ARCHITECTURE CORRECTION

**Previous Implementation (WRONG):**
- Salary override affecting PF/PT calculations ❌
- Temporary payments modifying statutory deductions ❌

**New Implementation (CORRECT):**
- 3-layer separation of concerns ✅
- Contract salary for statutory compliance ✅
- Adjustments for temporary payments ✅

---

## 3-LAYER MODEL

```
┌─────────────────────────────────────────┐
│ LAYER 1: CONTRACT SALARY (Master Data) │
│ - Never changes per month               │
│ - Used for PF/PT/ESIC                   │
│ - Compliance reports                    │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│ LAYER 2: ATTENDANCE EARNINGS            │
│ - Calculated from attendance            │
│ - Uses working days rule                │
│ - earned_basic + ot_pay                 │
└─────────────────────────────────────────┘
                    ↓
┌─────────────────────────────────────────┐
│ LAYER 3: MONTHLY ADJUSTMENTS            │
│ - Allowances, bonuses, deductions       │
│ - Does NOT affect PF/PT                 │
│ - Only affects net pay                  │
└─────────────────────────────────────────┘
```

---

## LAYER 1: CONTRACT SALARY

**Source:** `guards.salary` (employee master data)

**Purpose:** Legal wage agreement - **NEVER CHANGES PER MONTH**

**Used For:**
```sql
-- PF Calculation (ALWAYS uses contract)
IF contract_basic >= 15000:
  pf = 15000 × 0.12 = 1800 (capped)
ELSE:
  pf = contract_basic × 0.12

-- PT Calculation (ALWAYS uses contract)
IF contract_basic >= 12000:
  pt = 200
ELSE:
  pt = 0

-- ESIC (future)
-- Compliance reports
```

**Fields:**
```sql
contract_basic NUMERIC       -- From guards.salary
contract_ot_basic NUMERIC    -- Can differ from basic (agency practice)
```

---

## LAYER 2: ATTENDANCE EARNINGS

**Calculated From:** Finalized shift instances

**Working Days Rule:**
```sql
-- Organization-level default
organizations.payroll_working_days_rule = 26 (or 27/30/31)

-- Unit-level override (optional)
units.working_days_override = 26
```

**Calculation:**
```sql
daily_rate = contract_basic / working_days_rule

earned_basic = daily_rate × (present_days + auto_present_days)

ot_pay = (contract_ot_basic / working_days_rule) × ot_days
```

**Example:**
```
contract_basic = 18000
working_days_rule = 26

daily_rate = 18000 / 26 = 692.31
present_days = 22
earned_basic = 692.31 × 22 = 15230.82
```

---

## LAYER 3: MONTHLY ADJUSTMENTS

**Table:** `payroll_adjustments`

**Purpose:** Handle temporary payments **WITHOUT** affecting PF/PT

### **Adjustment Types:**

1. **ALLOWANCE** - Conveyance, mobile, etc.
2. **BONUS** - Performance, festival bonus
3. **DEDUCTION** - Misc deduction
4. **RECOVERY** - Advance recovery, loan repayment
5. **CORRECTION** - Admin correction
6. **CLIENT_EXTRA** - Client-specific extra payment
7. **ROUNDING** - Rounding adjustment

### **Schema:**
```sql
CREATE TABLE payroll_adjustments (
  id UUID,
  payroll_calculation_id UUID,
  adjustment_type TEXT,  -- See types above
  label TEXT,            -- "Festival Bonus"
  amount NUMERIC,        -- +2500 (credit) or -500 (debit)
  note TEXT,
  created_by UUID,
  created_at TIMESTAMPTZ
)
```

### **Examples:**

**Add ₹2500 Festival Bonus:**
```sql
SELECT add_payroll_adjustment(
  p_calculation_id := 'calc-123',
  p_adjustment_type := 'BONUS',
  p_label := 'Festival Bonus',
  p_amount := 2500,
  p_note := 'Diwali bonus - does not affect PF',
  p_created_by := 'admin-uuid'
);
```

**Add ₹500 Conveyance:**
```sql
SELECT add_payroll_adjustment(
  p_calculation_id := 'calc-123',
  p_adjustment_type := 'ALLOWANCE',
  p_label := 'Conveyance Allowance',
  p_amount := 500,
  p_note := 'Monthly conveyance',
  p_created_by := 'admin-uuid'
);
```

**Deduct ₹1000 Advance Recovery:**
```sql
SELECT add_payroll_adjustment(
  p_calculation_id := 'calc-123',
  p_adjustment_type := 'RECOVERY',
  p_label := 'Advance Recovery',
  p_amount := -1000,  -- Negative = deduction
  p_note := 'Loan installment',
  p_created_by := 'admin-uuid'
);
```

---

## FINAL PAY COMPUTATION

### **Step-by-Step:**

**1. Attendance Earnings (Layer 2):**
```sql
earned_basic = 15230.82
ot_pay = 1384.62
```

**2. Statutory Deductions (Layer 1 - Contract):**
```sql
-- Uses contract_basic = 18000 (NOT earned_basic)
pf_amount = 18000 × 0.12 = 2160 (contract basic < 15000 cap)
pt_amount = 200 (contract basic >= 12000)
```

**3. Adjustments (Layer 3):**
```sql
Adjustments:
  + Festival Bonus: 2500
  + Conveyance: 500
  - Advance Recovery: -1000

total_adjustments_credit = 3000
total_adjustments_debit = 1000
```

**4. Final Calculation:**
```sql
gross_earnings = earned_basic + ot_pay + total_adjustments_credit
               = 15230.82 + 1384.62 + 3000
               = 19615.44

total_deductions = pf_amount + pt_amount + total_adjustments_debit
                 = 2160 + 200 + 1000
                 = 3360

net_pay = gross_earnings - total_deductions
        = 19615.44 - 3360
        = 16255.44
```

---

## PAYSLIP BREAKDOWN

```
═══════════════════════════════════════════════════
EARNINGS
───────────────────────────────────────────────────
Contract Basic:                      ₹18,000.00
Working Days Rule:                   26 days
Present Days:                        22 days
Daily Rate:                          ₹692.31

Earned Basic:                        ₹15,230.82
Overtime Pay:                        ₹1,384.62
───────────────────────────────────────────────────
Sub-total (Attendance):              ₹16,615.44

ADJUSTMENTS
───────────────────────────────────────────────────
Festival Bonus:                      ₹2,500.00
Conveyance Allowance:                ₹500.00
───────────────────────────────────────────────────
Gross Earnings:                      ₹19,615.44

DEDUCTIONS
───────────────────────────────────────────────────
PF (12% on contract):                ₹2,160.00
PT:                                  ₹200.00
Advance Recovery:                    ₹1,000.00
───────────────────────────────────────────────────
Total Deductions:                    ₹3,360.00

═══════════════════════════════════════════════════
NET PAY:                             ₹16,255.44
═══════════════════════════════════════════════════
```

---

## KEY BUSINESS RULES

### **1. Permanent Salary Change:**
```
Workflow:
1. Update guards.salary (master data)
2. Delete old payroll calculations
3. Regenerate payroll
4. New PF/PT calculated on new salary
```

### **2. Temporary Payment:**
```
Workflow:
1. Generate payroll normally
2. Add adjustment (Layer 3)
3. PF/PT unchanged
4. Next month: No adjustment, back to normal
```

### **3. Correction Workflow:**
```
If calculation error:
  → Add adjustment (type: CORRECTION)
  → Document in note field
  → Audit trail maintained

If permanent salary wrong:
  → Update master data
  → Regenerate payroll
```

---

## WHAT CHANGED FROM OVERRIDE SYSTEM

### **OLD (Salary Override - WRONG):**
```sql
basic_override = 20000
effective_basic = 20000

-- WRONG: PF calculated on override
pf = 20000 × 0.12 = 2400  ❌
```

**Problem:** Temporary payment affecting statutory deductions

---

### **NEW (Adjustments - CORRECT):**
```sql
contract_basic = 18000
adjustment = +2000 (BONUS)

-- CORRECT: PF calculated on contract
pf = 18000 × 0.12 = 2160  ✅

gross_earnings = earned_basic + adjustment
net_pay = gross_earnings - pf
```

**Result:** Temporary payment does NOT affect PF/PT

---

## WORKING DAYS RULE

### **Configuration:**

**Organization Level (Default):**
```sql
UPDATE organizations 
SET payroll_working_days_rule = 26
WHERE id = 'org-id';
```

**Unit Level (Override):**
```sql
UPDATE units 
SET working_days_override = 30
WHERE id = 'unit-id';
```

### **Usage:**
```sql
-- Unit override takes precedence
working_days_rule = COALESCE(
  units.working_days_override,
  organizations.payroll_working_days_rule,
  26  -- System default
)

daily_rate = contract_basic / working_days_rule
```

---

## API FUNCTIONS

### **1. Generate Payroll:**
```sql
SELECT generate_payroll_calculations_v2(
  p_period_id := 'period-id',
  p_org_id := 'org-id',
  p_generated_by := 'admin-id'
);
```

### **2. Add Adjustment:**
```sql
SELECT add_payroll_adjustment(
  p_calculation_id := 'calc-id',
  p_adjustment_type := 'BONUS',
  p_label := 'Festival Bonus',
  p_amount := 2500,
  p_note := 'Diwali 2026',
  p_created_by := 'admin-id'
);
```

### **3. Remove Adjustment:**
```sql
SELECT remove_payroll_adjustment(
  p_adjustment_id := 'adj-id',
  p_user_id := 'admin-id'
);
```

---

## UI WORKFLOW

### **Payroll Screen:**

**Before (Override - WRONG):**
```
[Override Salary] → Changes PF/PT ❌
```

**After (Adjustments - CORRECT):**
```
[Add Adjustment] → Opens popup:
  - Type: [BONUS/ALLOWANCE/DEDUCTION/etc.]
  - Label: [Festival Bonus]
  - Amount: [2500]
  - Note: [Reason]
  - [Save]

Adjustments List:
  - Festival Bonus: +₹2,500
  - Conveyance: +₹500
  - Advance Recovery: -₹1,000
  [Remove] buttons
```

---

## MIGRATION FROM OLD SYSTEM

**If override fields exist:**
```sql
-- Overrides marked as DEPRECATED
-- Convert existing overrides to adjustments:

INSERT INTO payroll_adjustments (
  payroll_calculation_id,
  adjustment_type,
  label,
  amount,
  note
)
SELECT 
  id,
  'CORRECTION',
  'Migrated from salary override',
  basic_override - basic_snapshot,
  override_reason
FROM payroll_calculations
WHERE basic_override IS NOT NULL
  AND basic_override != basic_snapshot;

-- Then clear overrides
UPDATE payroll_calculations 
SET basic_override = NULL, ot_basic_override = NULL;
```

---

## COMPLIANCE GUARANTEE

**PF/PT Always Use Contract Salary:**
```sql
-- Even if 10 adjustments added
-- PF/PT calculation NEVER changes

pf = f(contract_basic)  -- ONLY
pt = f(contract_basic)  -- ONLY

adjustments → affect net_pay → NOT statutory
```

---

## FILES

- `supabase/migrations/payroll_refactor_3layer.sql` - Refactored implementation
- `docs/PAYROLL_3LAYER_MODEL.md` - This documentation

---

**Result:** Security agency can give temporary payments without affecting statutory compliance. PF/PT always calculated on contract salary. Adjustments don't modify master data.
