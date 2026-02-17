# 3-STAGE PAYROLL SYSTEM

## ARCHITECTURE OVERVIEW

```
Stage 1: Work Unit Aggregation
           ↓
Stage 2: Calculation Snapshot (IMMUTABLE)
           ↓
Stage 3: Settlement Layer (Mutable until locked)
```

---

## STAGE 1: WORK UNIT AGGREGATION

**Table:** `payroll_work_units`

**Purpose:** Count work days from finalized shift instances - **NO MONEY CALCULATIONS**

**Columns:**
- `present_days` - Normal confirmed attendance
- `auto_present_days` - Auto-confirmed (supervisor inactive)
- `replacement_days` - Days worked as replacement
- `ot_days` - Overtime days
- `included_shift_instances` - Array of shift IDs (audit trail)
- `aggregation_status` - DRAFT, FINALIZED

**Source:** Only shift_instances with status:
- `CONFIRMED`
- `AUTO_CONFIRMED`
- `PAYROLL_LOCKED`

**Function:** `aggregate_work_units(period_id, org_id)`

**Example:**
```sql
-- Guard worked 22 days in February
SELECT * FROM payroll_work_units WHERE guard_id = 'guard-1';

{
  present_days: 20.0,
  auto_present_days: 2.0,  -- Supervisor didn't confirm 2 days
  replacement_days: 0.0,
  ot_days: 0.5
}
```

---

## STAGE 2: CALCULATION SNAPSHOT

**Table:** `payroll_calculations`

**Purpose:** Freeze salary calculations based on work units - **IMMUTABLE AFTER CREATION**

### **Snapshot Values:**
- `basic_snapshot` - Guard's salary at snapshot time
- `days_in_month` - Calendar days (28, 30, or 31)
- `daily_rate` = basic_snapshot / days_in_month

### **Earnings:**
- `earned_basic` = daily_rate × (present_days + auto_present_days)
- `ot_pay` = daily_rate × ot_days
- `total_earned` = earned_basic + ot_pay

### **Statutory Deductions:**

#### **PF (Provident Fund - 12%):**
```sql
IF basic_snapshot >= 15000:
  pf_amount = 15000 * 0.12 = 1800 (capped)
ELSE:
  pf_amount = earned_basic * 0.12
```

#### **PT (Professional Tax):**
```sql
IF total_earned >= 12000:
  pt_amount = 200
ELSE:
  pt_amount = 0
```

### **Immutability:**
- `calculation_locked` - **ALWAYS TRUE**
- Attendance changes after snapshot **DO NOT** affect calculations
- If salary changes, old calculations remain unchanged

**Function:** `generate_payroll_calculations(period_id, generated_by)`

**Example:**
```sql
-- Calculation frozen for Guard 1
SELECT * FROM payroll_calculations WHERE guard_id = 'guard-1';

{
  basic_snapshot: 18000,
  days_in_month: 28,
  daily_rate: 642.86,
  present_days: 20.0,
  auto_present_days: 2.0,
  earned_basic: 14142.92,  -- 642.86 × 22
  ot_pay: 321.43,          -- 642.86 × 0.5
  total_earned: 14464.35,
  pf_amount: 1800,         -- Capped at 15000 base
  pt_amount: 200,          -- Earned >= 12000
  calculation_locked: true,
  snapshot_at: '2026-02-28T12:00:00Z'
}
```

---

## STAGE 3: SETTLEMENT LAYER

**Table:** `payroll_settlements`

**Purpose:** Handle deductions, adjustments, and payment tracking - **MUTABLE UNTIL LOCKED**

### **Copied from Calculation:**
- `total_earned`
- `pf_amount`
- `pt_amount`

### **Manual Deductions:**
- `advance_deduction` - Salary advance repayment
- `canteen_deduction` - Canteen charges
- `uniform_deduction` - Uniform cost recovery
- `other_deduction` - Misc deductions
- `hold_amount` - Amount on hold (disputes, legal)

### **Manual Additions:**
- `bonus` - Performance bonus, festival bonus
- `allowance` - Conveyance, mobile, etc.

### **Final Calculation (Auto-computed):**
```sql
total_deductions = pf_amount + pt_amount + advance_deduction + 
                   canteen_deduction + uniform_deduction + 
                   other_deduction + hold_amount

final_payable = total_earned + bonus + allowance - total_deductions
```

### **Payment Tracking:**
- `payment_mode` - BANK_TRANSFER, CASH, CHEQUE, UPI
- `payment_status` - PENDING, PROCESSING, PAID, FAILED, ON_HOLD
- `payment_reference` - Transaction ID, cheque number
- `payment_date`

### **Settlement Status:**
- `settlement_locked` - Locked when payroll period closed
- `locked_at`, `locked_by`

**Function:** `create_payroll_settlements(period_id)`

**Example:**
```sql
-- Settlement for Guard 1
SELECT * FROM payroll_settlements WHERE guard_id = 'guard-1';

{
  total_earned: 14464.35,
  pf_amount: 1800,
  pt_amount: 200,
  advance_deduction: 2000,
  canteen_deduction: 500,
  bonus: 1000,
  
  total_deductions: 4500,  -- Auto-calculated
  final_payable: 10964.35, -- Auto-calculated
  
  payment_mode: 'BANK_TRANSFER',
  payment_status: 'PENDING',
  settlement_locked: false
}
```

---

## PAYROLL GENERATION WORKFLOW

### **Complete Flow:**

```sql
-- Run complete payroll generation
SELECT run_payroll_generation(
  'period-id',
  'org-id',
  'admin-user-id'
);
```

**Internally executes:**

1. **`aggregate_work_units()`** → Counts work days from shift_instances
2. **`generate_payroll_calculations()`** → Snapshots salary and calculates earnings (IMMUTABLE)
3. **`create_payroll_settlements()`** → Creates settlement records for deductions/payment

---

## KEY GUARANTEES

### **1. Calculation Immutability**

**Scenario:** Guard salary changes mid-month

```
Feb 1: Salary = 18000
Feb 15: Salary increased to 20000
Feb 28: Payroll generated

Result: Calculation uses basic_snapshot = 18000 (value at generation time)
```

**Attendance changes after snapshot:**
```
Feb 28: Payroll generated (22 days present)
Mar 1: Supervisor retrospectively confirms 1 more day

Result: Calculation still shows 22 days (immutable)
        Manual adjustment needed if payment required
```

---

### **2. Audit Trail**

Every calculation includes:
- `included_shift_instances` - Exact shifts counted
- `snapshot_at` - When calculation performed
- `snapshot_by` - Who generated payroll
- `auto_present_days` - Days flagged for supervisor review

---

### **3. Statutory Compliance**

**PF Calculation:**
```
Guard A: basic_snapshot = 12000
  → pf = 12000 × 0.12 = 1440

Guard B: basic_snapshot = 18000
  → pf = 15000 × 0.12 = 1800 (capped)
```

**PT Calculation:**
```
Guard A: total_earned = 10000 → pt = 0
Guard B: total_earned = 14000 → pt = 200
```

---

## PAYROLL STATES

### **Work Units:**
- `DRAFT` - Can be recalculated
- `FINALIZED` - Used for calculation generation

### **Calculations:**
- Always `calculation_locked = true`
- **Never modified** after creation

### **Settlements:**
- `settlement_locked = false` - Can edit deductions/payments
- `settlement_locked = true` - Payroll period closed, immutable

---

## QUERYING EXAMPLES

### **Get Payroll Summary:**
```sql
SELECT 
  g.full_name,
  pc.basic_snapshot,
  pc.present_days,
  pc.auto_present_days,
  pc.earned_basic,
  pc.total_earned,
  ps.final_payable,
  ps.payment_status
FROM payroll_calculations pc
JOIN guards g ON g.id = pc.guard_id
JOIN payroll_settlements ps ON ps.calculation_id = pc.id
WHERE pc.payroll_period_id = 'period-id'
ORDER BY g.full_name;
```

### **Find Auto-Confirmed Days (Audit):**
```sql
SELECT 
  g.full_name,
  pc.auto_present_days,
  pc.total_earned
FROM payroll_calculations pc
JOIN guards g ON g.id = pc.guard_id
WHERE pc.payroll_period_id = 'period-id'
  AND pc.auto_present_days > 0
ORDER BY pc.auto_present_days DESC;
```

### **Pending Payments:**
```sql
SELECT 
  g.full_name,
  ps.final_payable,
  ps.payment_status
FROM payroll_settlements ps
JOIN guards g ON g.id = ps.guard_id
WHERE ps.payroll_period_id = 'period-id'
  AND ps.payment_status IN ('PENDING', 'PROCESSING')
ORDER BY ps.final_payable DESC;
```

---

## MODIFICATION RULES

| Stage | Can Modify? | When? |
|-------|-------------|-------|
| **Work Units** | ✅ Yes | Before finalization |
| **Calculations** | ❌ Never | Immutable after creation |
| **Settlements** | ✅ Yes | Before settlement_locked = true |

---

## FILES

- `supabase/migrations/three_stage_payroll_system.sql` - Complete implementation
- `docs/THREE_STAGE_PAYROLL.md` - This documentation

**Result:** Payroll calculations frozen at generation time. Attendance changes after snapshot do not affect calculations. Settlement layer handles deductions and payment tracking separately.
