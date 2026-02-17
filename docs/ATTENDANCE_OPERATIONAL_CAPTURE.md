# ATTENDANCE OPERATIONAL CAPTURE

## CRITICAL OPERATIONAL CHANGE

**NEVER block supervisor from marking attendance in real-world usage.**

---

## PROBLEM: BLOCKING BEHAVIOR

### **OLD (Unacceptable):**
```
Supervisor marks guard present
  ↓
Validation fails
  ↓
ERROR: PAYROLL_PERIOD_NOT_AVAILABLE
  ↓
Supervisor sees technical error ❌
Attendance not recorded ❌
Guard not marked present ❌
```

**Real-world impact:**
- Supervisor confused by technical errors
- Guard's attendance lost
- Field operations blocked
- Manual workarounds created

---

## SOLUTION: OPERATIONAL CAPTURE

### **NEW (Field-Ready):**
```
Supervisor marks guard present
  ↓
Validation detects issue
  ↓
Attendance recorded as OPERATIONAL_ONLY ✅
Exception logged for admin ✅
Supervisor sees warning (not error) ✅
  ↓
Admin reviews exceptions later
Admin resolves → converts to VALID_FOR_PAYROLL
```

**Real-world impact:**
- Supervisor can always mark attendance
- Guard's presence recorded immediately
- Field operations never blocked
- Admin resolves systematically

---

## ATTENDANCE STATUS STATES

### **Table:** `attendance`

**New Column:** `validation_status`

```sql
validation_status TEXT CHECK (validation_status IN (
  'VALID_FOR_PAYROLL',    -- Normal, included in payroll
  'OPERATIONAL_ONLY',     -- Has issues, excluded until resolved
  'RESOLVED'              -- Was exceptional, now admin-approved
))
```

### **State Flow:**

**Normal Path:**
```
INSERT attendance
  ↓
Validation passes
  ↓
validation_status = 'VALID_FOR_PAYROLL'
  ↓
Included in payroll ✅
```

**Exception Path:**
```
INSERT attendance
  ↓
Validation fails (no period / period finalized)
  ↓
validation_status = 'OPERATIONAL_ONLY'
Exception record created
  ↓
Admin reviews
Admin approves
  ↓
validation_status = 'RESOLVED'
  ↓
Included in payroll ✅
```

**Rejection Path:**
```
INSERT attendance
  ↓
Validation fails
  ↓
validation_status = 'OPERATIONAL_ONLY'
  ↓
Admin reviews
Admin rejects
  ↓
validation_status = 'OPERATIONAL_ONLY' (stays)
  ↓
Excluded from payroll ❌
```

---

## ATTENDANCE EXCEPTIONS TABLE

**Purpose:** Log all validation failures for admin review

```sql
CREATE TABLE attendance_exceptions (
  id UUID,
  attendance_id UUID,
  
  -- Exception type
  exception_type TEXT CHECK (
    'PAYROLL_PERIOD_NOT_AVAILABLE',
    'PERIOD_FINALIZED',
    'OWNERSHIP_INVALID',
    'REPLACED_SHIFT',
    'DUPLICATE_ATTENDANCE',
    'OTHER'
  ),
  
  exception_message TEXT,
  exception_details JSONB,
  
  -- Resolution
  resolution_status TEXT CHECK (
    'PENDING',      -- Awaiting admin
    'RESOLVED',     -- Admin approved
    'REJECTED',     -- Admin rejected
    'DUPLICATED'    -- Merged with another
  ),
  
  resolved_at TIMESTAMPTZ,
  resolved_by UUID,
  resolution_note TEXT,
  
  -- Admin override
  override_applied BOOLEAN,
  override_reason TEXT
);
```

---

## EXCEPTION TYPES

### **1. PAYROLL_PERIOD_NOT_AVAILABLE**

**Scenario:**
```
Supervisor marks attendance for Feb 15
No payroll period exists for Feb
```

**OLD (Blocked):**
```sql
ERROR: PAYROLL_PERIOD_NOT_AVAILABLE
HINT: Contact admin to create payroll period
```

**NEW (Captured):**
```sql
-- Attendance inserted
validation_status = 'OPERATIONAL_ONLY'

-- Exception logged
exception_type = 'PAYROLL_PERIOD_NOT_AVAILABLE'
exception_message = 'No payroll period exists for 2026-02-15'

-- Supervisor sees
WARNING: Attendance recorded. Admin must create payroll period.
```

---

### **2. PERIOD_FINALIZED**

**Scenario:**
```
Feb 28: Admin finalizes Feb period
Mar 5: Guard's offline data syncs (Feb 15 attendance)
```

**OLD (Blocked):**
```sql
ERROR: PERIOD_FINALIZED
DETAIL: Period status is ATTENDANCE_FINALIZED
```

**NEW (Captured):**
```sql
-- Attendance inserted
validation_status = 'OPERATIONAL_ONLY'

-- Exception logged
exception_type = 'PERIOD_FINALIZED'
exception_message = 'Period is ATTENDANCE_FINALIZED for 2026-02-15'

-- Sync succeeds with warning
WARNING: Late attendance captured. Admin must review.
```

---

### **3. OWNERSHIP_INVALID** (Future)

**Scenario:**
```
Supervisor marks Guard A present
Shift ownership = Guard B
```

**NEW (Captured):**
```sql
validation_status = 'OPERATIONAL_ONLY'
exception_type = 'OWNERSHIP_INVALID'
exception_message = 'Guard A marked present but shift owned by Guard B'
```

---

### **4. REPLACED_SHIFT** (Future)

**Scenario:**
```
Supervisor marks original guard present
Shift has active replacement
```

**NEW (Captured):**
```sql
validation_status = 'OPERATIONAL_ONLY'
exception_type = 'REPLACED_SHIFT'
exception_message = 'Shift has active replacement by Guard X'
```

---

## ADMIN RESOLUTION WORKFLOW

### **Function:** `resolve_attendance_exception()`

**Actions:**

### **1. APPROVE**
```sql
SELECT resolve_attendance_exception(
  p_exception_id := 'exception-uuid',
  p_admin_user_id := 'admin-uuid',
  p_resolution_action := 'APPROVE',
  p_resolution_note := 'Late sync verified, legitimate attendance'
);

-- Result:
attendance.validation_status → 'RESOLVED'
exception.resolution_status → 'RESOLVED'
Included in payroll ✅
```

**Use Case:**
- Late offline sync (legitimate)
- Period reopened, attendance now valid
- Admin created missing period

---

### **2. REJECT**
```sql
SELECT resolve_attendance_exception(
  p_exception_id := 'exception-uuid',
  p_admin_user_id := 'admin-uuid',
  p_resolution_action := 'REJECT',
  p_resolution_note := 'Duplicate attendance, guard already marked present'
);

-- Result:
attendance.validation_status → 'OPERATIONAL_ONLY' (stays)
exception.resolution_status → 'REJECTED'
Excluded from payroll ❌
```

**Use Case:**
- Duplicate attendance
- Invalid date
- Guard was on leave
- Data entry error

---

### **3. OVERRIDE**
```sql
SELECT resolve_attendance_exception(
  p_exception_id := 'exception-uuid',
  p_admin_user_id := 'admin-uuid',
  p_resolution_action := 'OVERRIDE',
  p_resolution_note := 'Special case - client requested',
  p_override_reason := 'Client confirmed guard worked despite system issue'
);

-- Result:
attendance.validation_status → 'RESOLVED'
exception.resolution_status → 'RESOLVED'
exception.override_applied → true
Included in payroll ✅
Flagged as override in audit
```

**Use Case:**
- System error, guard actually worked
- Client confirmation overrides system validation
- Emergency attendance approval

---

## PAYROLL SAFETY

### **Work Unit Aggregation:**

**OLD (Unsafe):**
```sql
-- Included ALL attendance
SELECT * FROM attendance
WHERE payroll_period_id = 'period-id'
```

**NEW (Safe):**
```sql
-- Excludes OPERATIONAL_ONLY
SELECT * FROM attendance
WHERE payroll_period_id = 'period-id'
  AND validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
```

**Function:** `aggregate_work_units_by_period_safe()`

**Filters:**
```sql
AND a.validation_status IN ('VALID_FOR_PAYROLL', 'RESOLVED')
-- OPERATIONAL_ONLY attendance excluded
```

**Result:**
```json
{
  "success": true,
  "work_units_created": 45,
  "excluded_attendance_count": 3,  // 3 exceptional records
  "period_id": "period-uuid"
}
```

---

## ADMIN DASHBOARD VIEW

**View:** `attendance_exceptions_dashboard`

```sql
SELECT * FROM attendance_exceptions_dashboard
WHERE resolution_status = 'PENDING'
ORDER BY created_at DESC;
```

**Output:**
```
| exception_type    | guard_name | attendance_date | exception_message           | status  |
|-------------------|------------|-----------------|----------------------------|---------|
| PERIOD_FINALIZED  | John Doe   | 2026-02-15      | Period is FINALIZED        | PENDING |
| NO_PERIOD         | Jane Smith | 2026-03-01      | No period exists           | PENDING |
| OWNERSHIP_INVALID | Bob Jones  | 2026-02-28      | Shift owned by Mike Green  | PENDING |
```

**Admin Actions:**
- Review each exception
- Check context (shift, period, guard)
- Approve / Reject / Override
- Add resolution notes

---

## USER-FACING MESSAGES

### **Supervisor UI:**

**OLD (Blocking):**
```
❌ ERROR: PAYROLL_PERIOD_NOT_AVAILABLE
   Contact system administrator.
```

**NEW (Capture):**
```
✅ Attendance recorded.
⚠️  Pending admin review: No payroll period available.
   Guard marked present operationally.
```

**OLD (Blocking):**
```
❌ ERROR: PERIOD_FINALIZED
   Cannot add attendance to closed period.
```

**NEW (Capture):**
```
✅ Attendance recorded.
⚠️  Pending admin review: Payroll period already finalized.
   Late attendance captured for review.
```

---

## VALIDATION RULES (UNCHANGED)

**These rules still apply - just deferred to admin resolution:**

1. ✅ Payroll period must exist
2. ✅ Period must be OPEN for inclusion
3. ✅ Shift ownership must be valid (future)
4. ✅ No duplicate attendance (future)
5. ✅ No replaced shifts (future)

**Changed:** Enforcement point
- **Before:** Supervisor punch time (blocking)
- **After:** Admin resolution time (deferred)

---

## OPERATIONAL FLOW

### **Scenario 1: Normal Attendance**

```
10:00 AM: Supervisor marks Guard A present
  ↓
Validation: Period exists, OPEN ✅
  ↓
validation_status = 'VALID_FOR_PAYROLL'
  ↓
No exception created
  ↓
Included in payroll ✅
```

---

### **Scenario 2: Late Sync (Finalized Period)**

```
Mar 5: Guard's offline data syncs
Contains: Feb 15 attendance
Feb period: Already finalized
  ↓
Validation: Period FINALIZED ❌
  ↓
validation_status = 'OPERATIONAL_ONLY'
Exception created: PERIOD_FINALIZED
  ↓
Sync succeeds with warning ⚠️
  ↓
Admin reviews later
Admin: "This is valid late sync"
Admin APPROVES
  ↓
validation_status = 'RESOLVED'
  ↓
Next payroll run: Includes this attendance ✅
```

---

### **Scenario 3: No Period Exists**

```
Feb 1: Supervisor marks attendance
Feb period: NOT created yet
  ↓
Validation: No period ❌
  ↓
validation_status = 'OPERATIONAL_ONLY'
Exception created: PAYROLL_PERIOD_NOT_AVAILABLE
  ↓
Attendance recorded ✅
Supervisor sees warning ⚠️
  ↓
Admin creates period for Feb
Admin reviews exception
Admin APPROVES
  ↓
validation_status = 'RESOLVED'
Attendance linked to new period
  ↓
Included in payroll ✅
```

---

### **Scenario 4: Admin Rejects**

```
Supervisor marks duplicate attendance
(Guard already marked present)
  ↓
Validation: Duplicate detected ❌
  ↓
validation_status = 'OPERATIONAL_ONLY'
Exception created: DUPLICATE_ATTENDANCE
  ↓
Admin reviews
Admin: "Yes, this is duplicate"
Admin REJECTS
  ↓
validation_status = 'OPERATIONAL_ONLY' (stays)
  ↓
Excluded from payroll ❌
Guard paid only once ✅
```

---

## CHANGES SUMMARY

### **REMOVED:**
- ❌ Blocking errors at supervisor level
- ❌ Technical error messages to field users
- ❌ Hard validation at INSERT time

### **ADDED:**
- ✅ `validation_status` column to attendance
- ✅ `attendance_exceptions` table
- ✅ Operational capture trigger
- ✅ Exception creation trigger
- ✅ Admin resolution function
- ✅ Safe payroll aggregation (excludes OPERATIONAL_ONLY)
- ✅ Exception dashboard view

### **PRESERVED:**
- ✅ All validation rules (just deferred)
- ✅ Payroll correctness (excludes exceptional attendance)
- ✅ Shift ownership logic (not weakened)
- ✅ Period finalization rules (still enforced)

---

## FILES

- `supabase/migrations/attendance_operational_capture.sql` - Implementation
- `docs/ATTENDANCE_OPERATIONAL_CAPTURE.md` - This documentation

---

**FIELD OPERATIONS:** ✅ Never blocked  
**PAYROLL CORRECTNESS:** ✅ Preserved  
**ADMIN CONTROL:** ✅ Full resolution workflow  
**VALIDATION RULES:** ✅ Enforced (deferred)  
**USER EXPERIENCE:** ✅ No technical errors

**Result:** Supervisors can always mark attendance. Validation issues captured as exceptions. Admin resolves later. Payroll excludes unresolved exceptions automatically.
