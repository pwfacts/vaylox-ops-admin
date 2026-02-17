# PAYROLL SALARY OVERRIDE SYSTEM

## OVERVIEW

**Purpose:** Apply one-time monthly salary adjustments without modifying employee master data.

**Use Cases:**
- Temporary salary increase for a specific month
- Correction for incorrect master data (without changing master)
- Special allowances calculated as base override
- Different OT rates for specific periods

---

## SCHEMA CHANGES

### **payroll_calculations Table - New Fields:**

```sql
-- Original snapshot (from employee master)
basic_snapshot NUMERIC         -- Employee's base salary
ot_basic_snapshot NUMERIC      -- Base for OT calculation

-- Monthly overrides (NULL = use snapshot)
basic_override NUMERIC         -- Override for this period only
ot_basic_override NUMERIC      -- OT base override

-- Computed effective values (STORED)
effective_basic = COALESCE(basic_override, basic_snapshot)
effective_ot_basic = COALESCE(ot_basic_override, ot_basic_snapshot)

-- Override metadata
override_applied BOOLEAN
override_applied_by UUID
override_applied_at TIMESTAMPTZ
override_reason TEXT
```

---

## CALCULATION LOGIC

### **Without Override:**
```sql
basic_snapshot = 18000 (from employee master)
effective_basic = 18000

daily_rate = 18000 / 28 = 642.86
earned_basic = 642.86 × 22 days = 14142.92
```

### **With Override:**
```sql
basic_snapshot = 18000 (unchanged)
basic_override = 20000 (temporary increase)
effective_basic = 20000 (computed)

daily_rate = 20000 / 28 = 714.29
earned_basic = 714.29 × 22 days = 15714.38
```

**Next Month:**
- Override is NULL
- Reverts to basic_snapshot = 18000
- Employee master data **never modified**

---

## USAGE EXAMPLES

### **Example 1: Temporary Salary Increase**

**Scenario:** Guard gets ₹2000 increase for February only (festival bonus)

```sql
-- Apply override
SELECT apply_payroll_override(
  p_calculation_id := 'calc-123',
  p_basic_override := 20000,  -- Original was 18000
  p_ot_basic_override := NULL,
  p_admin_user_id := 'admin-uuid',
  p_reason := 'Festival bonus - February only'
);

-- Result:
{
  success: true,
  old_basic: 18000,
  new_basic: 20000,
  old_total_earned: 14142.92,
  new_total_earned: 15714.38
}
```

**Verification:**
```sql
SELECT 
  basic_snapshot,      -- 18000 (original)
  basic_override,      -- 20000 (override)
  effective_basic,     -- 20000 (computed)
  total_earned,        -- 15714.38 (recalculated)
  override_reason      -- 'Festival bonus...'
FROM payroll_calculations
WHERE id = 'calc-123';
```

---

### **Example 2: Different OT Rate**

**Scenario:** Guard works overtime at higher rate for special project

```sql
SELECT apply_payroll_override(
  p_calculation_id := 'calc-456',
  p_basic_override := NULL,        -- Keep regular basic same
  p_ot_basic_override := 25000,    -- Higher OT base
  p_admin_user_id := 'admin-uuid',
  p_reason := 'Special project OT rate'
);
```

**Calculation:**
```
Regular: daily_rate = 18000 / 28 = 642.86
OT: ot_daily_rate = 25000 / 28 = 892.86

earned_basic = 642.86 × 22 = 14142.92
ot_pay = 892.86 × 2 = 1785.72
total_earned = 15928.64
```

---

### **Example 3: Correction Without Changing Master**

**Scenario:** Salary in master is ₹15000 but should be ₹16000 this month

```sql
SELECT apply_payroll_override(
  p_calculation_id := 'calc-789',
  p_basic_override := 16000,
  p_ot_basic_override := NULL,
  p_admin_user_id := 'admin-uuid',
  p_reason := 'Correction: Master data update pending'
);
```

**Master Data:** Remains 15000 (unchanged)  
**Payroll:** Uses 16000 (override)  
**Next Month:** HR updates master to 16000, remove override

---

### **Example 4: Remove Override**

**Scenario:** Revert to original snapshot values

```sql
SELECT remove_payroll_override(
  p_calculation_id := 'calc-123',
  p_admin_user_id := 'admin-uuid',
  p_reason := 'Override no longer needed'
);
```

**Result:**
- `basic_override` → NULL
- `effective_basic` → Reverts to `basic_snapshot`
- Calculations recalculated
- Audit logged

---

## STATUTORY DEDUCTIONS

### **PF Calculation with Override:**

```sql
-- Without override
basic_snapshot = 18000
pf = 15000 × 0.12 = 1800 (capped)

-- With override
basic_override = 12000
effective_basic = 12000
pf = earned_basic × 0.12 = (12000/28 × 22) × 0.12 = 1131.43
```

**Rule:** PF uses `effective_basic` (override if present)

---

### **PT Calculation with Override:**

```sql
-- Without override
total_earned = 14142.92
pt = 200 (threshold met)

-- With override (lower)
total_earned = 9428.57
pt = 0 (below threshold)
```

---

## PERMISSIONS & VALIDATION

### **Who Can Apply Overrides:**
```sql
-- Only ADMIN or SUPER_ADMIN
SELECT role FROM users WHERE id = current_user_id;
-- Must return: 'ADMIN' or 'SUPER_ADMIN'
```

### **When Can Overrides Be Applied:**

**✅ Allowed:**
```sql
payroll_period.status = 'OPEN'
payroll_settlements.settlement_locked = false
```

**❌ Blocked:**
```sql
payroll_period.status = 'CLOSED' 
  → Error: 'PERIOD_NOT_OPEN'

payroll_settlements.settlement_locked = true
  → Error: 'SETTLEMENT_LOCKED'
```

---

## AUDIT TRAIL

### **payroll_override_audit Table:**

Every override change is logged:

```sql
SELECT * FROM payroll_override_audit 
WHERE calculation_id = 'calc-123'
ORDER BY changed_at DESC;
```

**Result:**
```
| field_name      | old_value | new_value | changed_by | reason          |
|-----------------|-----------|-----------|------------|-----------------|
| basic_override  | NULL      | 20000     | admin-1    | Festival bonus  |
| basic_override  | 20000     | NULL      | admin-1    | Override remove |
```

**Audit Fields:**
- `calculation_id` - Which calculation
- `field_name` - 'basic_override' or 'ot_basic_override'
- `old_value` - Previous value
- `new_value` - New value
- `changed_by` - Admin user ID
- `changed_at` - Timestamp
- `reason` - Explanation
- `period_status_at_change` - Period status when changed
- `settlement_locked_at_change` - Lock status when changed

---

## REPORTING

### **View: payroll_with_overrides**

```sql
SELECT 
  guard_name,
  period_month,
  basic_snapshot,           -- Original
  basic_override,           -- Override (NULL if not overridden)
  effective_basic,          -- Actual used value
  override_applied,         -- Boolean flag
  override_reason,          -- Why overridden
  total_earned              -- Calculated total
FROM payroll_with_overrides
WHERE period_month = 2 AND period_year = 2026
  AND override_applied = true;
```

**Output:**
```
| guard_name | basic_snapshot | basic_override | effective_basic | override_reason     |
|------------|----------------|----------------|-----------------|---------------------|
| John Doe   | 18000          | 20000          | 20000           | Festival bonus      |
| Jane Smith | 15000          | 16000          | 16000           | Correction pending  |
```

---

### **Overrides Summary Report:**

```sql
SELECT 
  COUNT(*) AS total_overrides,
  SUM(effective_basic - basic_snapshot) AS total_override_amount,
  AVG(effective_basic - basic_snapshot) AS avg_override_amount
FROM payroll_calculations
WHERE payroll_period_id = 'period-feb-2026'
  AND override_applied = true;
```

---

## WORKFLOW

### **Step 1: Generate Payroll**
```sql
-- Standard payroll generation
SELECT run_payroll_generation('period-id', 'org-id', 'admin-id');

-- All calculations use snapshot values initially
-- basic_override = NULL
-- effective_basic = basic_snapshot
```

---

### **Step 2: Apply Overrides (If Needed)**
```sql
-- Admin reviews and applies overrides
SELECT apply_payroll_override(
  'calc-id',
  20000,  -- New basic
  NULL,   -- Keep OT base same
  'admin-id',
  'Reason for override'
);

-- Calculations automatically recalculated
-- Settlement updated
```

---

### **Step 3: Review & Approve**
```sql
-- Check overrides before closing
SELECT * FROM payroll_with_overrides
WHERE override_applied = true
  AND payroll_period_id = 'period-id';

-- Admin approves or reverts overrides
```

---

### **Step 4: Close Payroll**
```sql
-- Close period (locks settlements)
UPDATE payroll_periods SET status = 'CLOSED';

-- Overrides now locked
-- Cannot modify after this point
```

---

## IMPORTANT RULES

### **✅ DO:**
- Apply overrides only for valid business reasons
- Document reason in `override_reason` field
- Review audit trail before closing payroll
- Use overrides for temporary adjustments only

### **❌ DON'T:**
- Use overrides as permanent salary changes
- Modify overrides after period closes
- Apply overrides without proper authorization
- Forget to update employee master data if needed

---

## MIGRATION PATH

### **For Existing Payroll:**

If calculations already generated without override fields:

```sql
-- Schema is backward compatible
-- Existing records:
effective_basic = basic_snapshot (no override)
override_applied = false

-- Can apply overrides to existing calculations
-- (if period still OPEN)
```

---

## FILES

- `supabase/migrations/payroll_salary_override.sql` - Implementation
- `docs/PAYROLL_SALARY_OVERRIDE.md` - This documentation

---

**Result:** Monthly salary adjustments without touching employee master data. Full audit trail. Admin-only permissions. Locked after payroll period closes.
