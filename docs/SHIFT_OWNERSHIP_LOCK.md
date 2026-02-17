# SHIFT OWNERSHIP LOCK SYSTEM

## NEW CONSTRAINTS ADDED

### **Table: `shift_instances`**
```sql
UNIQUE(unit_id, shift_date, shift, claimed_by_profile_id)
-- Prevents same guard claiming shift multiple times

CHECK (status → payroll_locked_at consistency)
-- PAYROLL_LOCKED must have payroll_locked_at timestamp
```

### **Table: `attendance`**
```sql
shift_instance_id UUID REFERENCES shift_instances(id)
-- Every attendance must link to shift ownership record
```

### **Trigger: `trigger_validate_attendance_ownership`**
- Fires BEFORE INSERT on attendance
- Validates guard is authorized shift owner
- Auto-claims shift if not already claimed
- Blocks insert if shift REPLACED or PAYROLL_LOCKED

---

## FUNCTIONS MODIFIED

### **1. `claim_shift_instance()` - NEW**
**Purpose:** Atomically claim shift ownership

**Logic:**
```
IF shift exists AND locked → REJECT
IF shift exists AND REPLACED → REJECT (original guard)
IF shift exists AND UNCLAIMED → CLAIM
IF shift not exists → CREATE and CLAIM
```

**Returns:** `shift_instance_id` or error

---

### **2. `validate_attendance_ownership()` - NEW TRIGGER**
**Purpose:** Enforce shift ownership before attendance insert

**Logic:**
```
ON attendance INSERT:
  IF no shift_instance_id provided:
    → Call claim_shift_instance()
    → If rejected, RAISE EXCEPTION (blocks insert)
  ELSE:
    → Validate guard owns shift_instance_id
    → If not owned, RAISE EXCEPTION
```

**Effect:** Attendance INSERT fails if guard not authorized

---

### **3. `dispatch_replacement()` - MODIFIED**
**Old Behavior:**
- Insert into guard_replacements table
- No ownership tracking

**New Behavior:**
```
1. Find shift_instance for original guard
2. IF shift CONFIRMED or PAYROLL_LOCKED → REJECT
3. UPDATE shift_instance SET status = 'REPLACED', replacement_profile_id
4. Insert into guard_replacements (existing behavior)
```

**Effect:** Original guard **cannot check in after replacement** (ownership transferred)

---

### **4. `confirm_attendance()` - MODIFIED**
**Old Behavior:**
- Update attendance.supervisor_status = 'CONFIRMED'

**New Behavior:**
```
1. Update attendance.supervisor_status = 'CONFIRMED'
2. UPDATE shift_instances SET status = 'CONFIRMED'
```

**Effect:** Shift ownership **locked** after supervisor confirmation

---

### **5. `can_close_payroll_period()` - MODIFIED**
**Old Behavior:**
- Check for disputed attendance only

**New Behavior:**
```
1. Check for disputed attendance
2. NEW: Check for shift_instances NOT in CONFIRMED state
3. IF any CLAIMED or REPLACED shifts exist → BLOCK closure
```

**Effect:** Payroll **cannot close** until all shifts supervisor-confirmed

---

### **6. `close_payroll_period()` - NEW**
**Purpose:** Permanently lock shifts on payroll closure

**Logic:**
```
1. Validate can_close_payroll_period()
2. UPDATE shift_instances SET status = 'PAYROLL_LOCKED'
3. UPDATE payroll_periods SET status = 'CLOSED'
```

**Effect:** Shifts **immutable** after payroll closed

---

## HOW IT PREVENTS DOUBLE PAYMENT

### **Scenario 1: Duplicate Check-In (PREVENTED)**

**Before:**
```
T0: Guard checks in → attendance row 1
T1: Network glitch, guard taps again → attendance row 2
T2: Payroll counts both rows → DOUBLE PAYMENT
```

**After:**
```
T0: Guard checks in
    → claim_shift_instance() creates shift ownership
    → attendance.shift_instance_id = 'shift-1'
    → shift_instances.status = 'CLAIMED'

T1: Guard taps again
    → claim_shift_instance() called
    → Shift already CLAIMED by same guard
    → Returns existing shift_instance_id
    → attendance.shift_instance_id = 'shift-1' (same)

T2: Payroll query:
    SELECT DISTINCT ON (shift_instance_id) * FROM attendance
    → Only 1 payable record per shift_instance_id
    → NO DOUBLE PAYMENT
```

---

### **Scenario 2: Replacement After Check-In (PREVENTED)**

**Before:**
```
T0: Guard A checks in → attendance exists
T1: Supervisor dispatches Guard B as replacement
T2: Guard B checks in → attendance exists
T3: Payroll counts BOTH → DOUBLE PAYMENT
```

**After:**
```
T0: Guard A checks in
    → shift_instances.claimed_by_profile_id = 'guard-A'
    → shift_instances.status = 'CLAIMED'

T1: Supervisor dispatches Guard B
    → dispatch_replacement() called
    → UPDATE shift_instances SET
        status = 'REPLACED',
        replacement_profile_id = 'guard-B'

T2: Guard A tries to check in again (late arrival)
    → validate_attendance_ownership() trigger fires
    → claim_shift_instance() called
    → Shift status = 'REPLACED'
    → REJECT with error: "You have been replaced"
    → INSERT BLOCKED

T3: Guard B checks in
    → claim_shift_instance() sees replacement_profile_id = 'guard-B'
    → Creates NEW shift_instance for Guard B
    → shift_instances(2).claimed_by_profile_id = 'guard-B'

T4: Payroll query:
    → Guard A shift_instance = REPLACED (not paid)
    → Guard B shift_instance = CONFIRMED (paid)
    → NO DOUBLE PAYMENT
```

---

### **Scenario 3: Manual + Offline Attendance (PREVENTED)**

**Before:**
```
T0: Guard offline, cannot punch
T1: Supervisor creates manual attendance
T2: Guard comes online, offline queue syncs
T3: Two attendance records → DOUBLE PAYMENT
```

**After:**
```
T0: Guard offline

T1: Supervisor creates manual attendance
    → claim_shift_instance() called
    → shift_instances.claimed_by_profile_id = 'guard-A'
    → shift_instances.status = 'CLAIMED'
    → attendance.shift_instance_id = 'shift-1'

T2: Guard comes online, offline queue syncs
    → syncQueuedAttendance() tries to INSERT attendance
    → validate_attendance_ownership() trigger fires
    → claim_shift_instance() called
    → Shift already CLAIMED by same guard
    → Returns same shift_instance_id
    → attendance.shift_instance_id = 'shift-1' (SAME as manual)

T3: Payroll query:
    SELECT DISTINCT ON (shift_instance_id) * FROM attendance
    → Both rows have shift_instance_id = 'shift-1'
    → Only 1 counted
    → NO DOUBLE PAYMENT
```

---

### **Scenario 4: Payroll Closed, Late Attendance (PREVENTED)**

**Before:**
```
T0: Payroll closed for February
T1: Guard submits late February attendance (March 5th)
T2: Payroll amendment required
```

**After:**
```
T0: close_payroll_period() called
    → UPDATE shift_instances SET status = 'PAYROLL_LOCKED'
    → Immutable

T1: Guard tries to submit late attendance
    → validate_attendance_ownership() trigger fires
    → claim_shift_instance() called
    → Shift status = 'PAYROLL_LOCKED'
    → REJECT with error: "Shift already PAYROLL_LOCKED"
    → INSERT BLOCKED

T2: Admin must manually create attendance override
    → Requires explicit unlock or amendment workflow
```

---

## EXAMPLE FLOW: BEFORE VS AFTER

### **Normal Check-In Flow**

#### **BEFORE (No Ownership)**
```
1. Guard taps "Check In"
2. INSERT INTO attendance (guard_id, unit_id, date, shift)
3. Done

Risk: No ownership validation, duplicates possible
```

#### **AFTER (Ownership Lock)**
```
1. Guard taps "Check In"
2. Trigger: validate_attendance_ownership() fires
3. claim_shift_instance(unit, date, shift, guard_profile) called
4. IF no instance exists:
     → CREATE shift_instances (status='CLAIMED', claimed_by=guard)
   ELSE IF instance exists AND owned by guard:
     → Return existing shift_instance_id
   ELSE IF instance REPLACED or LOCKED:
     → RAISE EXCEPTION → INSERT BLOCKED
5. attendance.shift_instance_id = claimed_id
6. INSERT succeeds

Guarantee: One active owner per shift
```

---

### **Replacement Dispatch Flow**

#### **BEFORE (No Transfer)**
```
1. Supervisor selects replacement guard
2. INSERT INTO guard_replacements (original, replacement)
3. Done

Risk: Original guard can still check in
```

#### **AFTER (Ownership Transfer)**
```
1. Supervisor selects replacement guard
2. dispatch_replacement(original, replacement, unit, date, shift) called
3. Find shift_instance owned by original guard
4. UPDATE shift_instances SET status='REPLACED', replacement_profile_id
5. INSERT INTO guard_replacements (existing behavior)
6. Done

Guarantee: Original guard blocked from check-in, only replacement can claim
```

---

### **Supervisor Confirmation Flow**

#### **BEFORE (Soft Confirmation)**
```
1. Supervisor confirms attendance
2. UPDATE attendance SET supervisor_status='CONFIRMED'
3. Done

Risk: Attendance can still be modified
```

#### **AFTER (Hard Lock)**
```
1. Supervisor confirms attendance
2. UPDATE attendance SET supervisor_status='CONFIRMED'
3. UPDATE shift_instances SET status='CONFIRMED', supervisor_confirmed_by
4. Done

Guarantee: Shift ownership locked, no further claims possible
```

---

### **Payroll Closure Flow**

#### **BEFORE (Weak Validation)**
```
1. Admin clicks "Close Payroll"
2. Check for disputed attendance only
3. UPDATE payroll_periods SET status='CLOSED'
4. Done

Risk: Unconfirmed attendance included in payroll
```

#### **AFTER (Strict Validation)**
```
1. Admin clicks "Close Payroll"
2. can_close_payroll_period() checks:
   - Disputed attendance count
   - Unconfirmed shift instances count
3. IF any CLAIMED/REPLACED shifts exist → BLOCK
4. ELSE:
   - UPDATE shift_instances SET status='PAYROLL_LOCKED'
   - UPDATE payroll_periods SET status='CLOSED'
5. Done

Guarantee: Only supervisor-confirmed shifts in payroll, all shifts immutable after close
```

---

## STATE MACHINE

```
UNCLAIMED → CLAIMED → CONFIRMED → PAYROLL_LOCKED
    ↓          ↓
REPLACED   (stays CLAIMED if not confirmed)

Transitions:
- UNCLAIMED → CLAIMED: Guard checks in
- UNCLAIMED/CLAIMED → REPLACED: Replacement dispatched
- CLAIMED → CONFIRMED: Supervisor confirms
- CONFIRMED → PAYROLL_LOCKED: Payroll closed
- PAYROLL_LOCKED → (immutable, no transitions)
```

---

## KEY BENEFITS

✅ **Prevents Duplicate Payment** - DISTINCT ON shift_instance_id  
✅ **Blocks Replaced Guard** - REPLACED state rejects original guard check-in  
✅ **Enforces Confirmation** - Payroll requires CONFIRMED state  
✅ **Immutable After Close** - PAYROLL_LOCKED prevents amendments  
✅ **Atomic Claims** - Race-safe shift ownership acquisition  
✅ **Audit Trail** - Every ownership change tracked in shift_instances  

---

**Result:** Double payment scenarios eliminated through ownership state machine.
