# PAYROLL CYCLE-BASED SYSTEM

## WHAT CHANGED

**BEFORE (Calendar Month Logic):**
```sql
WHERE attendance_date >= '2026-02-01' 
  AND attendance_date <= '2026-02-28'
```
❌ Hard-coded to calendar months  
❌ Cannot handle 26th-25th cycles  
❌ Month/year fields in payroll_periods

**AFTER (Cycle-Based Logic):**
```sql
WHERE payroll_period_id = 'period-uuid'
```
✅ Configurable cycle start day  
✅ Supports MONTHLY or CUSTOM_DAY  
✅ from_date/to_date in payroll_periods

---

## CONFIGURATION

### **Organization-Level Settings**

**Table:** `organization_payroll_settings`

```sql
CREATE TABLE organization_payroll_settings (
  organization_id UUID PRIMARY KEY,
  cycle_type TEXT,           -- 'MONTHLY' or 'CUSTOM_DAY'
  cycle_start_day INTEGER,   -- 1-28 (for CUSTOM_DAY)
  auto_generate_periods BOOLEAN DEFAULT true
);
```

**Examples:**

**Calendar month (1st to last day):**
```sql
INSERT INTO organization_payroll_settings (organization_id, cycle_type)
VALUES ('org-id', 'MONTHLY');
-- cycle_start_day = NULL
```

**26th to 25th cycle:**
```sql
INSERT INTO organization_payroll_settings 
  (organization_id, cycle_type, cycle_start_day)
VALUES ('org-id', 'CUSTOM_DAY', 26);

-- Periods:
-- 26 Jan → 25 Feb
-- 26 Feb → 25 Mar
-- 26 Mar → 25 Apr
```

**10th to 9th cycle:**
```sql
INSERT INTO organization_payroll_settings 
  (organization_id, cycle_type, cycle_start_day)
VALUES ('org-id', 'CUSTOM_DAY', 10);

-- Periods:
-- 10 Jan → 9 Feb
-- 10 Feb → 9 Mar
```

---

## PAYROLL PERIODS TABLE

**REPLACED Fields:**
```sql
-- OLD
month INTEGER
year INTEGER

-- NEW
from_date DATE
to_date DATE
```

**Status Workflow:**
```
OPEN → ATTENDANCE_FINALIZED → GENERATED → LOCKED
```

**Schema:**
```sql
CREATE TABLE payroll_periods (
  id UUID,
  organization_id UUID,
  from_date DATE,
  to_date DATE,
  status TEXT,  -- OPEN, ATTENDANCE_FINALIZED, GENERATED, LOCKED
  
  attendance_finalized_at TIMESTAMPTZ,
  generated_at TIMESTAMPTZ,
  locked_at TIMESTAMPTZ,
  
  -- Constraints:
  -- 1. No overlapping periods
  -- 2. Only one OPEN period per org
);
```

---

## ATTENDANCE LINKAGE

**New Field:** `attendance.payroll_period_id`

**Automatic Assignment:**
```sql
-- Trigger assigns period on INSERT
CREATE TRIGGER trg_assign_attendance_period
  BEFORE INSERT ON attendance
  EXECUTE FUNCTION assign_attendance_to_period();

-- Logic:
1. Find period where attendance_date BETWEEN from_date AND to_date
2. If no period exists → auto-create OPEN period
3. Set attendance.payroll_period_id
```

**Example:**
```sql
-- Organization has CUSTOM_DAY cycle, start_day = 26

-- Insert attendance for Feb 10
INSERT INTO attendance (guard_id, attendance_date, ...)
VALUES ('guard-1', '2026-02-10', ...);

-- Auto-assigned to period: Jan 26 - Feb 25
-- payroll_period_id = 'period-uuid'
```

---

## WORKFLOW

### **Step 1: Create Organization Settings**

```sql
INSERT INTO organization_payroll_settings 
  (organization_id, cycle_type, cycle_start_day)
VALUES 
  ('org-id', 'CUSTOM_DAY', 26);
```

---

### **Step 2: Generate First Period**

```sql
SELECT generate_next_payroll_period('org-id');

-- Result:
{
  success: true,
  period_id: 'uuid',
  from_date: '2026-02-26',
  to_date: '2026-03-25',
  status: 'OPEN'
}
```

---

### **Step 3: Attendance Punching**

```sql
-- Guards punch attendance as normal
-- Period assignment is automatic

-- Attendance on Mar 1
INSERT INTO attendance (..., attendance_date = '2026-03-01');
-- → Assigned to period Feb 26 - Mar 25

-- Attendance on Mar 26
INSERT INTO attendance (..., attendance_date = '2026-03-26');
-- → New period auto-created: Mar 26 - Apr 25
```

---

### **Step 4: Finalize Attendance**

```sql
SELECT finalize_attendance('period-id', 'admin-user-id');

-- Checks:
-- ✓ All shifts CONFIRMED or AUTO_CONFIRMED
-- ✓ No CLAIMED or REPLACED shifts remain

-- Effects:
-- 1. status → ATTENDANCE_FINALIZED
-- 2. Locks attendance edits
-- 3. Prevents new punches
```

**After finalization:**
- ❌ Cannot INSERT attendance
- ❌ Cannot UPDATE attendance
- ✅ Can generate payroll

---

### **Step 5: Generate Payroll**

```sql
-- Must use period_id, NOT month/year
SELECT aggregate_work_units_by_period('period-id');
SELECT generate_payroll_calculations_v2('period-id', 'org-id', 'admin-id');

-- Calculations done
-- status → GENERATED
```

---

### **Step 6: Lock Payroll**

```sql
UPDATE payroll_periods 
SET status = 'LOCKED', locked_at = NOW()
WHERE id = 'period-id';

-- Auto-generates next period (if auto_generate_periods = true)
-- New OPEN period created: Mar 26 - Apr 25
```

---

## AUTOMATIC PERIOD GENERATION

### **26th to 25th Example:**

**Configuration:**
```sql
cycle_type = 'CUSTOM_DAY'
cycle_start_day = 26
```

**Period Calculation:**
```
Attendance Date: Feb 10
↓
Extract day: 10
↓
10 < 26 → belongs to PREVIOUS cycle
↓
Period: Jan 26 - Feb 25
```

**Attendance Date: Feb 28**
```
Extract day: 28
↓
28 >= 26 → belongs to CURRENT cycle
↓
Period: Feb 26 - Mar 25
```

**Calendar:**
```
Jan:  ... 26 27 28 29 30 31  |← Period 1 starts
Feb:  1  2  ... 24 25        |← Period 1 ends
      26 27 28 29            |← Period 2 starts
Mar:  1  2  ... 24 25        |← Period 2 ends
      26 27 28 29 30 31      |← Period 3 starts
```

---

## QUERIES TO REPLACE

### **❌ OLD (Month-Based):**

```sql
-- Aggregate work units
SELECT * FROM attendance
WHERE organization_id = 'org-id'
  AND EXTRACT(MONTH FROM attendance_date) = 2
  AND EXTRACT(YEAR FROM attendance_date) = 2026;

-- Payroll generation
aggregate_work_units(
  'period-id',
  'org-id',
  DATE '2026-02-01',  -- start_date
  DATE '2026-02-28'   -- end_date
);
```

---

### **✅ NEW (Period-Based):**

```sql
-- Aggregate work units
SELECT * FROM attendance
WHERE payroll_period_id = 'period-id';

-- Payroll generation
aggregate_work_units_by_period('period-id');
```

---

## FUNCTIONS

### **1. `generate_next_payroll_period(org_id)`**

**Creates next period based on cycle settings**

**MONTHLY:**
```sql
last_period.to_date = 2026-01-31
→ next period: 2026-02-01 to 2026-02-28
```

**CUSTOM_DAY (26):**
```sql
last_period.to_date = 2026-02-25
→ next period: 2026-02-26 to 2026-03-25
```

---

### **2. `finalize_attendance(period_id, user_id)`**

**Locks attendance for period**

**Validations:**
- Period must be OPEN
- All shift_instances must be CONFIRMED or AUTO_CONFIRMED
- No CLAIMED or REPLACED shifts allowed

**Effect:**
```sql
status → ATTENDANCE_FINALIZED
attendance_finalized_at → NOW()
```

---

### **3. `aggregate_work_units_by_period(period_id)`**

**REFACTORED from `aggregate_work_units`**

**Changed:**
```sql
-- OLD
WHERE attendance_date >= p_period_start
  AND attendance_date <= p_period_end

-- NEW
WHERE payroll_period_id = p_period_id
```

**Salary formulas:** UNCHANGED ✅  
**PF/PT logic:** UNCHANGED ✅  
**Shift ownership:** UNCHANGED ✅

---

## STATUS WORKFLOW

```
┌──────┐
│ OPEN │ ← Attendance can be punched
└──┬───┘
   │ finalize_attendance()
   ↓
┌────────────────────────┐
│ ATTENDANCE_FINALIZED   │ ← Attendance locked
└──────────┬─────────────┘
           │ generate_payroll()
           ↓
┌───────────┐
│ GENERATED │ ← Payroll calculated
└─────┬─────┘
      │ lock_payroll()
      ↓
┌────────┐
│ LOCKED │ ← Fully closed
└────────┘
    │ (auto-generates next period)
    ↓
┌──────┐
│ OPEN │ ← New period
└──────┘
```

---

## VALIDATION RULES

### **1. No Overlapping Periods**
```sql
CREATE UNIQUE INDEX idx_payroll_periods_no_overlap 
  USING GIST (organization_id, daterange(from_date, to_date, '[]'));
```

**Effect:**
```sql
-- Cannot create:
Period 1: Feb 20 - Mar 20
Period 2: Mar 10 - Apr 10  ❌ OVERLAPS
```

---

### **2. One OPEN Period Per Org**
```sql
CONSTRAINT one_open_period_per_org 
  UNIQUE (organization_id) WHERE (status = 'OPEN')
```

**Effect:**
```sql
-- Cannot have:
Period 1: status = OPEN
Period 2: status = OPEN  ❌ DUPLICATE
```

---

### **3. Attendance Edit Prevention**
```sql
CREATE TRIGGER trg_prevent_attendance_edit_finalized
  BEFORE INSERT OR UPDATE ON attendance
  EXECUTE FUNCTION prevent_attendance_edit_if_finalized();
```

**Effect:**
```sql
-- If period.status IN ('ATTENDANCE_FINALIZED', 'GENERATED', 'LOCKED')
INSERT INTO attendance (...) → ❌ ERROR
UPDATE attendance SET ... → ❌ ERROR
```

---

## BACKWARD COMPATIBILITY

### **NOT MODIFIED:**
- ✅ Salary formulas
- ✅ PF/PT calculation logic
- ✅ Adjustments table
- ✅ Shift ownership locks
- ✅ Contract salary model
- ✅ Working days rule

### **MODIFIED:**
- ❌ `payroll_periods` table schema (month/year → from_date/to_date)
- ✅ `attendance` table (added payroll_period_id)
- ✅ Aggregation queries (date range → period_id)

---

## PRODUCTION SAFETY CHECKLIST

### **✅ Constraints:**
- [x] No overlapping periods per org
- [x] Only one OPEN period per org
- [x] Valid date ranges (to_date >= from_date)
- [x] cycle_start_day 1-28 only (safe across all months)

### **✅ Data Integrity:**
- [x] Automatic period assignment on attendance INSERT
- [x] Auto-create period if missing
- [x] Prevent attendance edits after finalization
- [x] Prevent payroll generation before finalization

### **✅ Automation:**
- [x] Auto-generate next period on lock
- [x] Configurable per organization
- [x] Trigger-based assignment

---

## EDGE CASES HANDLED

### **1. February (28/29 days)**
```
cycle_start_day = 30 → ❌ NOT ALLOWED (max 28)

Why: Feb doesn't have 30th
Safe: Use 28 or lower
```

---

### **2. First Attendance Punch**
```
No periods exist
↓
Attendance INSERT triggered
↓
auto_create_period_for_date() called
↓
Period created automatically
↓
Attendance assigned
```

---

### **3. Attendance Between Periods**
```
Period 1: Jan 26 - Feb 25
Period 2: Feb 26 - Mar 25

Attendance: Feb 25 → Period 1 ✅
Attendance: Feb 26 → Period 2 ✅
No gap
```

---

## FILES

- `supabase/migrations/payroll_cycle_system.sql` - Implementation
- `docs/PAYROLL_CYCLE_SYSTEM.md` - This documentation

---

**PRODUCTION SAFE:** ✅  
**REAL AGENCY READY:** ✅  
**26th-25th CYCLE:** ✅

**Result:** Agencies can configure ANY cycle start day (1-28). Payroll automatically follows the configured cycle. No more "our salary cycle is 26 to 25" requests.
