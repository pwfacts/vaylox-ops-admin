# POST-PAYROLL EXCEPTION RESOLUTION

## OBJECTIVE

**Automatically close old exceptions after payroll is locked.**

Once salary is paid, unresolved exceptions are auto-resolved based on type with full audit trail.

---

## CORE PRINCIPLE

**Payroll lock = acceptance of reality.**

After payroll is LOCKED:
- Guards already paid
- Attendance already counted
- Exceptions auto-resolved based on business logic
- Full audit trail maintained

---

## AUTO-RESOLUTION RULES

### **Rule 1: PERIOD_FINALIZED / LATE_SYNC**

**Scenario:** Guard worked, attendance captured late

**Resolution:** Auto-APPROVE

**Logic:**
```sql
-- Guard actually worked (just late capture)
validation_status → RESOLVED
resolution_source → SYSTEM_AUTO
liability_role → SYSTEM
```

**Reason:** If we paid the guard, we accepted the attendance was legitimate.

---

### **Rule 2: DUPLICATE_ATTENDANCE**

**Scenario:** Same guard marked present twice for same date

**Resolution:** Keep earliest, reject later

**Logic:**
```sql
-- Find all attendance for guard + date
duplicates = [attendance_1, attendance_2, attendance_3]
earliest = attendance_1

-- Keep earliest
IF this_record == earliest:
  validation_status → RESOLVED
  resolution_source → SYSTEM_AUTO
  liability_role → SYSTEM
ELSE:
  validation_status → OPERATIONAL_ONLY (stay excluded)
  resolution_status → REJECTED
  resolution_source → SYSTEM_AUTO
  liability_role → SUPERVISOR  (supervisor created duplicate)
```

**Reason:** Guard paid once. Earliest record is source of truth. Later entries are data entry errors.

---

### **Rule 3: OWNERSHIP_INVALID / REPLACED_SHIFT**

**Scenario:** Supervisor marked wrong guard present

**Resolution:** Auto-APPROVE with supervisor liability

**Logic:**
```sql
-- Supervisor marked Guard A, but shift owned by Guard B
-- Payroll paid Guard A (based on this attendance)
validation_status → RESOLVED
resolution_source → SYSTEM_AUTO
liability_role → SUPERVISOR  (supervisor liable for error)
```

**Reason:** Guard already paid. Can't undo. Supervisor accountable for error.

---

### **Rule 4: OTHER TYPES**

**Scenario:** Unknown or complex exception types

**Resolution:** Keep PENDING (manual review required)

**Logic:**
```sql
-- Don't auto-resolve
-- Admin must manually review
resolution_status → PENDING (no change)
```

---

## SCHEMA ADDITIONS

### **attendance_exceptions Table:**

**New Columns:**
```sql
resolution_source TEXT CHECK ('ADMIN', 'SYSTEM_AUTO')
  -- ADMIN: Manual admin resolution
  -- SYSTEM_AUTO: Automatic post-payroll resolution

liability_role TEXT CHECK ('GUARD', 'SUPERVISOR', 'ADMIN', 'SYSTEM', NULL)
  -- Who is liable/accountable for the exception
```

---

## TRIGGER FLOW

```
Payroll Period Status Changes
  ↓
OLD status: GENERATED
NEW status: LOCKED
  ↓
Trigger: trg_auto_resolve_on_payroll_lock
  ↓
Function: auto_resolve_post_payroll_exceptions(period_id)
  ↓
For each PENDING exception:
  ├─ PERIOD_FINALIZED → Auto-APPROVE
  ├─ LATE_SYNC → Auto-APPROVE
  ├─ DUPLICATE_ATTENDANCE → Keep earliest, reject rest
  ├─ OWNERSHIP_INVALID → Auto-APPROVE (supervisor liable)
  ├─ REPLACED_SHIFT → Auto-APPROVE (supervisor liable)
  └─ OTHER → Keep PENDING
  ↓
Result:
  - Exceptions resolved
  - Audit trail created
  - Notification sent to admin
```

---

## OPERATIONAL SCENARIOS

### **Scenario 1: Late Sync After Payroll**

```
Feb 28: Payroll finalized for Feb 1-28
Mar 1: Payroll LOCKED, guards paid

Unresolved exceptions:
- Guard A: PERIOD_FINALIZED (Feb 15 attendance, late sync)
- Guard B: PERIOD_FINALIZED (Feb 20 attendance, late sync)

Auto-resolution triggers:
  ↓
Guard A exception:
  exception_type = PERIOD_FINALIZED
  → Auto-APPROVE
  → validation_status = RESOLVED
  → resolution_source = SYSTEM_AUTO
  → liability_role = SYSTEM

Guard B exception:
  exception_type = PERIOD_FINALIZED
  → Auto-APPROVE
  → validation_status = RESOLVED
  → resolution_source = SYSTEM_AUTO
  → liability_role = SYSTEM

Result:
  - Both guards already paid ✅
  - Attendance now valid ✅
  - System liability (not individual) ✅
  - Full audit trail ✅
```

---

### **Scenario 2: Duplicate Attendance**

```
Feb 15: Supervisor marks Guard A present at 9:00 AM
Feb 15: Different supervisor marks Guard A present at 10:00 AM
  → Exception: DUPLICATE_ATTENDANCE created

Feb 28: Payroll generated
  → Only first attendance counted (earliest)
  → Guard A paid once ✅

Mar 1: Payroll LOCKED

Auto-resolution triggers:
  ↓
Find duplicates for Guard A on Feb 15:
  attendance_1 (created 9:00 AM) ← Earliest
  attendance_2 (created 10:00 AM) ← Duplicate

Exception for attendance_1:
  → Auto-APPROVE (keep earliest)
  → validation_status = RESOLVED
  → resolution_source = SYSTEM_AUTO
  → liability_role = SYSTEM

Exception for attendance_2:
  → Auto-REJECT (duplicate)
  → validation_status = OPERATIONAL_ONLY (stays excluded)
  → resolution_status = REJECTED
  → resolution_source = SYSTEM_AUTO
  → liability_role = SUPERVISOR (supervisor created duplicate)

Result:
  - Guard paid once ✅
  - Earliest record kept ✅
  - Duplicate rejected ✅
  - Supervisor liable for error ✅
```

---

### **Scenario 3: Wrong Guard Marked Present**

```
Feb 15: Shift owned by Guard B
Feb 15: Supervisor marks Guard A present (error)
  → Exception: OWNERSHIP_INVALID created

Feb 28: Payroll generated
  → Guard A paid (based on erroneous attendance)
  → Guard B NOT paid (no attendance)

Mar 1: Payroll LOCKED

Auto-resolution triggers:
  ↓
Exception for Guard A:
  exception_type = OWNERSHIP_INVALID
  → Auto-APPROVE (guard already paid, can't undo)
  → validation_status = RESOLVED
  → resolution_source = SYSTEM_AUTO
  → liability_role = SUPERVISOR (supervisor marked wrong guard)

Result:
  - Guard A paid ✅ (even though error)
  - Guard B not paid ❌ (supervisor error, not guard's fault)
  - Supervisor liable ✅
  - Exception closed ✅
  - Admin can review liability report for supervisor performance
```

---

### **Scenario 4: Manual Admin Resolution Before Lock**

```
Feb 20: Exception created (PERIOD_FINALIZED)
Feb 25: Admin manually reviews and APPROVES
  → resolution_source = ADMIN
  → liability_role = ADMIN
  → resolution_status = RESOLVED

Mar 1: Payroll LOCKED

Auto-resolution triggers:
  ↓
Exception already RESOLVED (not PENDING)
  → Skip (no auto-resolution needed) ✅

Result:
  - Manual resolution preserved ✅
  - Admin gets credit for proactive resolution ✅
```

---

## AUDIT TRAIL

### **Resolution Audit View:**

```sql
SELECT * FROM exception_resolution_audit
WHERE period_id = 'period-id'
ORDER BY resolved_at DESC;
```

**Output:**
```
| exception_id | type              | resolution_status | resolution_source | liability_role | resolved_at         | hours_to_resolution |
|--------------|-------------------|-------------------|-------------------|----------------|---------------------|---------------------|
| exc-1        | PERIOD_FINALIZED  | RESOLVED          | SYSTEM_AUTO       | SYSTEM         | 2026-03-01 00:05:12 | 72.5                |
| exc-2        | DUPLICATE_ATTEND  | REJECTED          | SYSTEM_AUTO       | SUPERVISOR     | 2026-03-01 00:05:12 | 68.3                |
| exc-3        | OWNERSHIP_INVALID | RESOLVED          | SYSTEM_AUTO       | SUPERVISOR     | 2026-03-01 00:05:12 | 75.1                |
| exc-4        | LATE_SYNC         | RESOLVED          | ADMIN             | ADMIN          | 2026-02-28 14:30:00 | 50.2                |
```

**Analysis:**
- System auto-resolved 3 exceptions when payroll locked
- 1 exception manually resolved by admin before lock
- Liability tracked: 1 system, 2 supervisor errors

---

### **Liability Report View:**

```sql
SELECT * FROM exception_liability_report
WHERE period_id = 'period-id';
```

**Output:**
```
| period_id | from_date  | to_date    | liability_role | exception_count | admin_resolved | auto_resolved | approved | rejected |
|-----------|------------|------------|----------------|-----------------|----------------|---------------|----------|----------|
| period-1  | 2026-02-26 | 2026-03-25 | SYSTEM         | 5               | 1              | 4             | 5        | 0        |
| period-1  | 2026-02-26 | 2026-03-25 | SUPERVISOR     | 3               | 0              | 3             | 2        | 1        |
| period-1  | 2026-02-26 | 2026-03-25 | ADMIN          | 1               | 1              | 0             | 1        | 0        |
```

**Analysis:**
- **SYSTEM liability:** 5 exceptions (late syncs, system issues)
- **SUPERVISOR liability:** 3 exceptions (duplicates, wrong guard)
- **ADMIN liability:** 1 exception (admin manual override)

**Use Case:** Performance review for supervisors (how many errors they create)

---

## POST-PAYROLL SUMMARY

**Function:** `get_post_payroll_resolution_summary(period_id)`

```sql
SELECT get_post_payroll_resolution_summary('period-id');
```

**Returns:**
```json
{
  "period_id": "uuid",
  "total_exceptions": 9,
  "auto_resolved": 7,
  "admin_resolved": 2,
  "still_pending": 0,
  "liability_breakdown": [
    { "liability_role": "SYSTEM", "count": 5 },
    { "liability_role": "SUPERVISOR", "count": 3 },
    { "liability_role": "ADMIN", "count": 1 }
  ]
}
```

---

## MANUAL RESOLUTION (ENHANCED)

**Function:** `resolve_attendance_exception_v2()`

**New Parameters:**
- `p_liability_role` - Optional, specify who is liable

**Example:**
```sql
SELECT resolve_attendance_exception_v2(
  p_exception_id := 'exc-id',
  p_admin_user_id := 'admin-id',
  p_resolution_action := 'APPROVE',
  p_resolution_note := 'Verified with client - guard actually worked',
  p_liability_role := 'SUPERVISOR'  -- Supervisor error, not guard
);

-- Result:
{
  "success": true,
  "action": "APPROVED",
  "resolution_source": "ADMIN"  -- Manual admin resolution
}
```

---

## WORKFLOW COMPARISON

### **BEFORE (Manual Only):**
```
Exception created
  ↓
Escalates: SUPERVISOR → FIELD_OFFICER → ADMIN → PAYROLL_RISK
  ↓
Payroll generated (with risk flags)
  ↓
Payroll LOCKED
  ↓
Exceptions still PENDING ❌
  ↓
Admin must manually resolve each one
  ↓
Takes days/weeks
```

---

### **AFTER (Auto + Manual):**
```
Exception created
  ↓
Escalates: SUPERVISOR → FIELD_OFFICER → ADMIN → PAYROLL_RISK
  ↓
Option 1: Admin manually resolves before payroll lock
  → resolution_source = ADMIN
  
Option 2: Payroll generated (with risk flags)
  ↓
Payroll LOCKED
  ↓
Auto-resolution triggers ✅
  ↓
PERIOD_FINALIZED → Auto-APPROVE
DUPLICATE_ATTENDANCE → Keep earliest
OWNERSHIP_INVALID → Auto-APPROVE (supervisor liable)
  ↓
Result: Clean slate ✅
  ↓
Admin can focus on genuinely complex exceptions only
```

---

## NOTIFICATION

**When auto-resolution runs:**

```
📧 Notification to Admin:
───────────────────────────
Title: Post-Payroll Auto-Resolution Complete
Message: 7 exceptions auto-resolved after payroll lock (6 approved, 1 rejected)

Details:
- Period: Feb 26 - Mar 25
- Resolved: 7
- Approved: 6
- Rejected: 1
───────────────────────────
```

---

## KEY PRINCIPLES

### **1. Never Delete Records**
```sql
-- ❌ NEVER DO THIS
DELETE FROM attendance_exceptions WHERE ...;

-- ✅ ALWAYS DO THIS
UPDATE attendance_exceptions 
SET resolution_status = 'RESOLVED',
    resolved_at = NOW(),
    resolution_source = 'SYSTEM_AUTO'
WHERE ...;
```

---

### **2. Full Audit Trail**
```sql
-- Every resolution tracked
resolution_source: WHO resolved (ADMIN / SYSTEM_AUTO)
liability_role: WHO is liable (GUARD / SUPERVISOR / ADMIN / SYSTEM)
resolved_at: WHEN resolved
resolution_note: WHY resolved
```

---

### **3. Payroll Lock = Acceptance**
```
If we paid the guard → We accepted the attendance as valid
Auto-resolution just formalizes this acceptance
```

---

### **4. Liability Tracking**
```
SYSTEM liability: System issues (late sync, period creation)
SUPERVISOR liability: Data entry errors (duplicates, wrong guard)
ADMIN liability: Manual overrides
```

---

## FILES

- `supabase/migrations/post_payroll_exception_resolution.sql` - Implementation
- `docs/POST_PAYROLL_EXCEPTION_RESOLUTION.md` - This documentation

---

**AUTO-RESOLUTION:** ✅ Triggers on payroll LOCK  
**AUDIT TRAIL:** ✅ Full tracking  
**LIABILITY TRACKING:** ✅ Accountability preserved  
**NEVER DELETE:** ✅ Only resolve with metadata  
**BUSINESS LOGIC:** ✅ Type-specific resolution rules

**Result:** Payroll lock triggers automatic cleanup. Old exceptions resolved based on business logic. Guards already paid, so acceptance formalized. Full audit trail and liability tracking for accountability. Admin focuses only on genuinely complex cases.
