# SHIFT OWNERSHIP FAILSAFE RESOLUTION

## SCHEMA CHANGES

### **1. `shift_instances` - New Status**
```sql
-- Added to existing status enum:
'AUTO_CONFIRMED'  -- Auto-confirmed after 24h supervisor inactivity

-- New columns:
auto_confirm_reason TEXT
accountable_role TEXT
```

**State Machine:**
```
UNCLAIMED → CLAIMED → AUTO_CONFIRMED (24h timeout) → PAYROLL_LOCKED
                  ↓
              CONFIRMED (supervisor action) → PAYROLL_LOCKED
```

---

### **2. `late_arrival_disputes` - New Table**

**Purpose:** Store rejected attendance attempts to prevent wage dispute evidence loss

**Columns:**
- `guard_id`, `unit_id`, `shift_date`, `shift`
- `attempted_at` - When guard tried to check in
- `rejection_reason` - Why rejected (REPLACED, LOCKED, etc.)
- `shift_instance_id` - Which shift was claimed
- `resolution_status` (PENDING, APPROVED, REJECTED, TIMEOUT)
- `resolved_by`, `resolved_at`, `resolution_note`

**Example Record:**
```json
{
  "guard_id": "guard-A",
  "shift_date": "2026-02-17",
  "rejection_reason": "SHIFT_REPLACED: You have been replaced for this shift",
  "shift_instance_status": "REPLACED",
  "attempted_at": "2026-02-17T10:30:00Z",
  "resolution_status": "PENDING"
}
```

---

## TRIGGER LOGIC

### **Modified: `validate_attendance_ownership()`**

**Old Behavior:**
```sql
IF claim fails → RAISE EXCEPTION (block insert)
```

**New Behavior:**
```sql
IF claim fails:
  1. INSERT INTO late_arrival_disputes (
       guard_id, rejection_reason, attempted_at, ...
     )
  2. RAISE EXCEPTION (still blocks insert)
```

**Effect:** 
- Attendance INSERT still blocked (payment correctness maintained)
- Evidence preserved in late_arrival_disputes table
- Supervisor can review and manually approve if justified

---

### **New: `auto_confirm_stale_shifts()` - Cron Worker**

**Trigger:** Run hourly (cron job)

**Logic:**
```sql
FOR EACH shift_instance WHERE:
  status = 'CLAIMED'
  AND created_at < NOW() - 24 hours
  AND supervisor_confirmed_at IS NULL

UPDATE shift_instances SET
  status = 'AUTO_CONFIRMED',
  auto_confirm_reason = 'Supervisor inactive - auto-confirmed after 24 hours',
  accountable_role = 'SUPERVISOR'
```

**Effect:**
- Shifts auto-progress after 24h
- Payroll can close (no deadlock)
- Accountability tracked (supervisor responsible)

---

## UPDATED PAYROLL BEHAVIOR

### **Before Failsafe:**

```sql
can_close_payroll_period():
  IF any shifts in CLAIMED or REPLACED state → BLOCK
```

**Problem:** Supervisor inactivity blocks payroll indefinitely

---

### **After Failsafe:**

```sql
can_close_payroll_period():
  IF any shifts in CLAIMED or REPLACED state → BLOCK
  
  -- NEW: AUTO_CONFIRMED allowed
  CONFIRMED shifts → CLOSE
  AUTO_CONFIRMED shifts → CLOSE (with audit flag)
```

**Allowed States for Payroll:**
- ✅ CONFIRMED (supervisor approved)
- ✅ AUTO_CONFIRMED (timeout-approved, accountable_role=SUPERVISOR)
- ❌ CLAIMED (< 24h old, awaiting confirmation)
- ❌ REPLACED (not yet resolved)
- ❌ DISPUTED (investigation pending)

---

### **Payroll Query:**

```sql
SELECT 
  si.id,
  si.status,
  si.auto_confirm_reason,
  si.accountable_role,
  a.guard_id,
  a.check_in_time,
  a.check_out_time
FROM shift_instances si
JOIN attendance a ON a.shift_instance_id = si.id
WHERE si.status IN ('CONFIRMED', 'AUTO_CONFIRMED', 'PAYROLL_LOCKED')
  AND si.shift_date BETWEEN '2026-02-01' AND '2026-02-28'
```

**Payment Logic:**
```
CONFIRMED → Pay normally
AUTO_CONFIRMED → Pay normally + flag for audit (accountable_role logged)
```

---

## OPERATIONAL SCENARIOS

### **Scenario 1: Supervisor Inactive**

```
Day 1, 08:00: Guard checks in
  → shift_instances.status = 'CLAIMED'
  → attendance.supervisor_status = 'PENDING_SUPERVISOR_CONFIRMATION'

Day 1, 16:00: Shift ends
  → Supervisor does not review

Day 2, 08:00: Still no supervisor confirmation
  → auto_confirm_stale_shifts() cron runs
  → shift_instances.status = 'AUTO_CONFIRMED'
  → auto_confirm_reason = 'Supervisor inactive - auto-confirmed after 24 hours'
  → accountable_role = 'SUPERVISOR'

Day 7: Payroll closes
  → can_close_payroll_period() returns true
  → Shift included in payroll with audit flag
  → Report shows: "5 shifts auto-confirmed due to supervisor inactivity"
```

**Result:** Payroll not blocked, supervisor accountability tracked

---

### **Scenario 2: Late Arrival After Replacement**

```
Day 1, 08:00: Guard A assigned to shift

Day 1, 08:15: Guard A not checked in
  → Supervisor dispatches Guard B as replacement
  → shift_instances.status = 'REPLACED'
  → shift_instances.replacement_profile_id = 'guard-B'

Day 1, 08:30: Guard B checks in
  → Claim succeeds (replacement authorized)
  → shift_instances(2).claimed_by = 'guard-B'

Day 1, 09:00: Guard A arrives late, tries to check in
  → validate_attendance_ownership() trigger fires
  → claim_shift_instance() returns error: "SHIFT_REPLACED"
  
  → INSERT INTO late_arrival_disputes:
      guard_id = 'guard-A'
      rejection_reason = 'SHIFT_REPLACED: You have been replaced'
      shift_instance_id = 'shift-1'
      shift_instance_status = 'REPLACED'
      attempted_at = '09:00'
  
  → Attendance INSERT BLOCKED (no double payment)
  
  → UI shows Guard A: "Cannot check in - you were replaced. Dispute logged."

Day 1, 10:00: Supervisor reviews late_arrival_disputes
  → Sees Guard A attempted punch at 09:00
  → Option 1: Approve (creates manual attendance for Guard A, Guard B removed)
  → Option 2: Reject (Guard A not paid, only Guard B)
```

**Result:** Guard A not paid (correct), but evidence preserved for wage dispute resolution

---

### **Scenario 3: Guard Forgotten in System**

```
Day 1: Guard checks in, works full shift
  → shift_instances.status = 'CLAIMED'

Day 2-7: Supervisor never reviews (on leave/forgot)

Day 8: auto_confirm_stale_shifts() runs
  → shift_instances.status = 'AUTO_CONFIRMED'

Day 10: Payroll closes
  → Shift included with auto_confirm_reason logged
  → Admin report: "Warning: 1 shift auto-confirmed"
  → Supervisor flagged for review
```

**Result:** Guard paid (correct), supervisor accountability tracked

---

### **Scenario 4: Disputed Late Arrival Approved**

```
Day 1, 08:00: Guard replaced (REPLACED state)

Day 1, 09:00: Original guard tries to check in
  → Rejected → late_arrival_disputes row created

Day 1, 10:00: Supervisor reviews dispute
  → Calls: resolve_late_arrival_dispute(dispute_id, 'APPROVED', supervisor_id, 'Valid reason')
  
  → Creates manual attendance for original guard:
      verification_mode = 'MANUAL_OVERRIDE'
      supervisor_status = 'CONFIRMED'
  
  → Original guard now payable
  → Replacement guard attendance removed (or marked invalid)
```

**Result:** Legitimate late arrival compensated while maintaining audit trail

---

## COMPARISON: BEFORE VS AFTER

### **Supervisor Inactivity**

| Aspect | Before Failsafe | After Failsafe |
|--------|----------------|----------------|
| Day 1 | Guard checks in | Guard checks in |
| Day 2 | Supervisor doesn't review | Supervisor doesn't review |
| Day 3 | Still pending | Auto-confirmed (accountable=SUPERVISOR) |
| Payroll Day 7 | **BLOCKED** | ✅ Closes with audit flag |
| Guard Payment | Delayed indefinitely | Paid on time |

---

### **Rejected Check-In**

| Aspect | Before Failsafe | After Failsafe |
|--------|----------------|----------------|
| Guard replaced | Status = REPLACED | Status = REPLACED |
| Original arrives late | INSERT blocked, silent failure | INSERT blocked, logged to disputes |
| Evidence | Lost | Preserved: attempted_at, device_timestamp, GPS |
| Wage Dispute | Guard has no proof | Guard can reference dispute_id |
| Supervisor Action | None | Can approve/reject from UI |

---

## PAYMENT CORRECTNESS GUARANTEES

### **Still Enforced:**

✅ **One payment per shift_instance:** `DISTINCT ON (shift_instance_id)` in payroll query  
✅ **Replaced guard blocked:** REPLACED state prevents check-in  
✅ **Payroll locked immutable:** PAYROLL_LOCKED state final  
✅ **Ownership validation:** Trigger blocks unauthorized attendance  

### **New:**

✅ **Auto-confirmation after 24h:** Prevents operational deadlock  
✅ **Dispute evidence preserved:** late_arrival_disputes table  
✅ **Accountability tracked:** auto_confirm_reason + accountable_role  
✅ **Manual override available:** resolve_late_arrival_dispute() function  

---

## CRON JOBS REQUIRED

```
Job 1: Auto-Confirm Stale Shifts
Schedule: Every hour
Function: auto_confirm_stale_shifts()
Purpose: Move CLAIMED → AUTO_CONFIRMED after 24h

Job 2: Escalate Overdue Tasks (existing)
Schedule: Every hour  
Function: escalate_overdue_verification_tasks()
Purpose: Escalate verification tasks
```

---

## AUDIT REPORT QUERIES

### **Auto-Confirmed Shifts by Period:**
```sql
SELECT 
  u.name AS unit,
  si.shift_date,
  si.shift,
  wp.full_name AS guard,
  si.auto_confirm_reason,
  si.accountable_role
FROM shift_instances si
JOIN units u ON u.id = si.unit_id
JOIN workforce_profiles wp ON wp.id = si.claimed_by_profile_id
WHERE si.status IN ('AUTO_CONFIRMED', 'PAYROLL_LOCKED')
  AND si.auto_confirm_reason IS NOT NULL
  AND si.shift_date BETWEEN '2026-02-01' AND '2026-02-28'
ORDER BY si.shift_date DESC;
```

### **Pending Late Arrival Disputes:**
```sql
SELECT 
  g.full_name AS guard,
  u.name AS unit,
  lad.shift_date,
  lad.shift,
  lad.attempted_at,
  lad.rejection_reason,
  EXTRACT(DAY FROM NOW() - lad.attempted_at) AS days_pending
FROM late_arrival_disputes lad
JOIN guards g ON g.id = lad.guard_id
JOIN units u ON u.id = lad.unit_id
WHERE lad.resolution_status = 'PENDING'
ORDER BY lad.attempted_at DESC;
```

---

**Result:** Operational deadlocks prevented while maintaining payment correctness and preserving evidence for dispute resolution.
