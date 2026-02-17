# COMPLETE TECHNICAL SYSTEM AUDIT
## Production Readiness Assessment

**Date:** 2026-02-17  
**System:** JDS Management SaaS - Guard Workforce Management  
**Audit Type:** Pre-Production Engineering Review

---

## SECTION 1 — DATABASE INVENTORY

### **AUTHENTICATION**

#### `users` (Supabase Auth - External)
- **Purpose:** Supabase authentication users
- **Critical Columns:** id, email, encrypted_password
- **Writers:** Supabase Auth, workforce-login Edge Function
- **Readers:** All RLS policies, AuthService
- **Importance:** HIGH (single point of failure for login)

#### `organization_users`
- **Purpose:** Maps auth users to organizations with roles
- **Critical Columns:** user_id, organization_id, role
- **Writers:** Admin user creation flows
- **Readers:** RLS policies, role-based routing
- **Importance:** HIGH (determines all access control)

---

### **WORKFORCE IDENTITY**

#### `workforce_profiles`
- **Purpose:** Profile data for guards, supervisors, field officers
- **Critical Columns:** id, linked_auth_user, organization_id, profile_type, employment_status
- **Writers:** workforce-login Edge Function, Admin panel
- **Readers:** Attendance system, dispatch engine, UI
- **Importance:** HIGH (core identity abstraction)

#### `guards`
- **Purpose:** Guard-specific data (legacy table - partially replaced by workforce_profiles)
- **Critical Columns:** id, full_name, employee_code, mobile_number
- **Writers:** Admin panel, guard creation
- **Readers:** Attendance, dispatch, payroll
- **Importance:** HIGH (still used in attendance FK)

#### `workforce_trusted_devices`
- **Purpose:** Trusted device registry for offline credential caching
- **Critical Columns:** profile_id, device_fingerprint, status
- **Writers:** Device registration flow, session state service
- **Readers:** Offline credential verification, photo authenticity validation
- **Importance:** MEDIUM (offline functionality only)

---

### **ATTENDANCE**

#### `attendance`
- **Purpose:** Core attendance records (check-in/check-out)
- **Critical Columns:**
  - `id`, `guard_id`, `unit_id`, `attendance_date`, `shift`
  - `check_in_time`, `check_out_time`
  - `verification_mode` (LIVE_VERIFIED, DELAYED_SYNC, OFFLINE_LOCAL, MANUAL_OVERRIDE)
  - `trust_score` (0-100)
  - `supervisor_status` (PENDING_SUPERVISOR_CONFIRMATION, CONFIRMED, DISPUTED)
  - `internal_review_flag` (silent audit flag)
- **Writers:**
  - Guard punch (AttendanceVerificationService)
  - Supervisor manual entry
  - Offline sync worker
- **Readers:**
  - Dispatch engine
  - Payroll calculation
  - Supervisor confirmation UI
  - Reports
- **Importance:** **CRITICAL** (affects payroll, dispatch, legal compliance)

#### `offline_attendance_queue`
- **Purpose:** Queued attendance punches made offline
- **Critical Columns:** id, guard_id, unit_id, queued_at, synced_at, sync_status
- **Writers:** Offline punch flow
- **Readers:** Background sync worker
- **Importance:** HIGH (data loss risk if not synced)

---

### **DISPATCH ENGINE**

#### `unit_assignments`
- **Purpose:** Guard-to-unit assignment records
- **Critical Columns:** id, profile_id, unit_id, start_date, end_date, status
- **Writers:** Admin assignment flow
- **Readers:** Dispatch algorithm, attendance validation
- **Importance:** HIGH (determines who can work where)

#### `units`
- **Purpose:** Client location/site data
- **Critical Columns:** id, name, organization_id, latitude, longitude, radius
- **Writers:** Admin setup
- **Readers:** Dispatch, attendance location validation, photo GPS check
- **Importance:** HIGH (location validation dependency)

#### `duty_rosters`
- **Purpose:** Planned duty schedules
- **Critical Columns:** id, unit_id, date, shift, required_guards
- **Writers:** Admin roster creation
- **Readers:** Dispatch engine
- **Importance:** HIGH (dispatch cannot run without roster)

#### `guard_replacements`
- **Purpose:** Replacement guard assignments for absent guards
- **Critical Columns:** original_profile_id, replacement_profile_id, unit_id, date, shift
- **Writers:** Dispatch engine (dispatch_replacement function)
- **Readers:** Dispatch status queries
- **Importance:** MEDIUM (operational continuity)

---

### **VERIFICATION SYSTEM**

#### `attendance_verification_tasks`
- **Purpose:** Investigation tasks for disputed attendance
- **Critical Columns:**
  - `id`, `attendance_id`, `organization_id`
  - `required_role` (SUPERVISOR, FIELD_OFFICER, ADMIN)
  - `reason_code` (LOW_TRUST, VERY_LOW_TRUST, TIME_DRIFT, OFFLINE_EXCESS, SUPERVISOR_DISPUTED)
  - `status` (PENDING, VERIFIED, JUSTIFIED, REJECTED)
  - `responsible_user_id` (specific owner)
  - `escalation_level`, `payroll_blocking`
  - `decision_type` (AUTOMATIC, MANUAL_OVERRIDE)
- **Writers:**
  - dispute_attendance() function (on supervisor rejection)
  - escalate_overdue_verification_tasks() cron
- **Readers:**
  - Supervisor/admin verification UI
  - Payroll closure check
- **Importance:** HIGH (blocks payroll if unresolved)

---

### **EVIDENCE SYSTEM**

#### `evidence_media_metadata`
- **Purpose:** Photo evidence authenticity validation results
- **Critical Columns:**
  - `task_id`, `attendance_id`
  - `captured_at`, `captured_lat`, `captured_lng`
  - `device_fingerprint`, `file_hash`
  - `validity_status` (VALID, SUSPICIOUS, INVALID)
  - `validation_flags` (TIME_OUT_OF_RANGE, LOCATION_OUT_OF_RANGE, PHOTO_REUSED, etc.)
- **Writers:** validate_photo_authenticity() function
- **Readers:** Verification task resolution
- **Importance:** MEDIUM (evidence system only, not core operations)

---

### **SESSION STATE**

#### `workforce_session_states`
- **Purpose:** Session state management (VERIFIED, RESTRICTED, RECOVERY)
- **Critical Columns:** profile_id, current_state, allowed_operations, blocked_operations
- **Writers:** SessionStateService, auto_upgrade_session_state trigger
- **Readers:** Operation permission checks, UI state indicators
- **Importance:** MEDIUM (affects offline functionality only)

---

### **AUDIT/LEGAL**

#### `session_revocation_logs`
- **Purpose:** Audit trail for session revocations
- **Critical Columns:** profile_id, revoked_at, revoked_by, reason
- **Writers:** workforce-revoke-sessions Edge Function
- **Readers:** Audit reports, compliance checks
- **Importance:** LOW (audit only, not operational)

---

### **PAYROLL**

#### `payroll_periods`
- **Purpose:** Payroll period definitions and closure status
- **Critical Columns:** id, organization_id, start_date, end_date, status (OPEN, CLOSED)
- **Writers:** Payroll admin, can_close_payroll_period validation
- **Readers:** Payroll calculation, period closure UI
- **Importance:** HIGH (financial operations)

---

### **NOTIFICATIONS**

**STATUS:** Not implemented. No notification tables found.

---

### **OTHER**

#### `organizations`
- **Purpose:** Top-level tenant data
- **Critical Columns:** id, name, subscription_tier
- **Writers:** Admin setup
- **Readers:** All RLS policies, multi-tenant filtering
- **Importance:** CRITICAL (multi-tenancy isolation)

---

## SECTION 2 — AUTOMATIONS

### **TRIGGERS**

#### 1. `trigger_auto_compute_attendance_trust_score`
- **Event:** INSERT or UPDATE of `verification_mode`, `device_timestamp`, `face_verified` on `attendance`
- **Action:** Calls `auto_compute_attendance_trust_score()` to calculate trust_score
- **Modifies:** `attendance.trust_score`, `attendance.trust_score_details`
- **Risk if fails:** Trust scores not calculated → verification tasks not created properly
- **Risk if runs twice:** Recalculates score (idempotent, safe)

#### 2. `trigger_flag_attendance_for_review`
- **Event:** INSERT or UPDATE of `trust_score` on `attendance`
- **Action:** Sets `internal_review_flag = true` if trust_score < 60
- **Modifies:** `attendance.internal_review_flag`
- **Risk if fails:** Low-trust attendance not flagged for review (silent failure)
- **Risk if runs twice:** Redundant flag set (safe)

#### 3. `trigger_auto_assign_verification_task`
- **Event:** INSERT on `attendance_verification_tasks`
- **Action:** Auto-assigns task to responsible user, sets escalation_level, due_at
- **Modifies:** `attendance_verification_tasks.responsible_user_id`, `escalation_level`, `due_at`
- **Risk if fails:** Tasks created without owner → nobody sees them
- **Risk if runs twice:** Assignment overwritten (potential ownership conflict)

#### 4. `trigger_auto_upgrade_session_state`
- **Event:** Time-based or shift-end events
- **Action:** Upgrades session state from RESTRICTED → VERIFIED
- **Modifies:** `workforce_session_states.current_state`
- **Risk if fails:** Users stuck in RESTRICTED state → cannot approve attendance
- **Risk if runs twice:** Redundant state upgrade (safe if idempotent)

---

### **BACKGROUND WORKERS / CRON JOBS**

#### 1. `escalate_overdue_verification_tasks()` - **REQUIRED CRON**
- **Schedule:** Hourly (not auto-configured)
- **Action:**
  - 24h unresolved → Escalate SUPERVISOR → FIELD_OFFICER
  - 48h unresolved → Escalate FIELD_OFFICER → ADMIN
  - 72h unresolved → Set `payroll_blocking = true`
- **Modifies:** `attendance_verification_tasks.escalation_level`, `responsible_user_id`, `payroll_blocking`
- **Risk if never runs:** Tasks never escalate → supervisors can ignore indefinitely → payroll never blocks
- **Risk if runs multiple times:** Potential duplicate escalations if not idempotent

#### 2. `syncPendingOperations()` - **Client-side worker**
- **Trigger:** Background sync or network recovery
- **Action:** Syncs `offline_attendance_queue` records to `attendance` table
- **Modifies:** Inserts into `attendance`, updates `offline_attendance_queue.sync_status`
- **Risk if fails:** Offline attendance lost permanently
- **Risk if runs twice:** **DUPLICATE ATTENDANCE RECORDS** (no deduplication logic visible)

---

### **AUTOMATIC FUNCTIONS**

#### 1. `calculate_attendance_trust_score(attendance_id)`
- **Trigger:** Called by trigger on attendance INSERT/UPDATE
- **Purpose:** Computes 0-100 trust score based on verification_mode, sync_delay, GPS, face verification
- **Returns:** trust_score, trust_score_details JSONB
- **Risk:** Logic errors → incorrect trust scores → wrong escalation level

#### 2. `auto_create_verification_task()` - **DISABLED IN REFACTOR**
- **Status:** Trigger dropped, function likely orphaned
- **Original Purpose:** Auto-create tasks on low trust
- **Current Risk:** Dead code, may be accidentally re-enabled

---

## SECTION 3 — RUNTIME FLOW

### **A) GUARD CHECK-IN**

```
1. Guard opens app, taps "Check In"

2. Flutter: AttendanceVerificationService.punchAttendance() called
   - Captures GPS (Geolocator.getCurrentPosition())
   - Gets device fingerprint (device ID)
   - Records device_timestamp = NOW()

3. Network check:
   IF online:
     → Call Supabase INSERT into attendance
   ELSE:
     → Call SessionStateService.queueAttendancePunch()
     → INSERT into offline_attendance_queue
     → Return early

4. Backend: INSERT into attendance table
   - guard_id, unit_id, attendance_date, shift, check_in_time
   - verification_mode = 'LIVE_VERIFIED' (or DELAYED_SYNC if slow network)
   - device_timestamp, last_known_location (GPS JSON)
   - supervisor_status = 'PENDING_SUPERVISOR_CONFIRMATION' (default)

5. Trigger: trigger_auto_compute_attendance_trust_score fires
   - Calculates trust_score based on:
     * verification_mode (LIVE_VERIFIED = 95 base)
     * sync_delay_seconds = server_received_timestamp - device_timestamp
     * GPS presence (+2 bonus)
     * face_verified (+3 to +5 bonus if provided)
   - Sets trust_score = 98 (example)
   - Stores trust_score_details JSONB

6. Trigger: trigger_flag_attendance_for_review fires
   - IF trust_score < 60:
       SET internal_review_flag = true
   - ELSE: no action

7. NO verification task created (refactor change)

8. Response returns to Flutter:
   - AttendancePunchResult(success: true, verificationMode: LIVE_VERIFIED, trustScore: 98)

9. UI shows: "Checked In - Awaiting Supervisor Confirmation"

TABLE CHANGES:
- attendance: 1 row inserted
- offline_attendance_queue: 0 rows (online punch)
- attendance_verification_tasks: 0 rows (no auto-creation)
```

---

### **B) SUPERVISOR CONFIRMATION**

```
1. Supervisor opens app, sees list of pending attendance
   - Query: SELECT * FROM attendance WHERE supervisor_status = 'PENDING_SUPERVISOR_CONFIRMATION'

2. Supervisor reviews guard attendance:
   - Check-in time: 08:05 AM
   - Trust score: 45 (shown as "Needs Review" badge)
   - Internal review flag: true (shown as warning icon)

3A. IF supervisor confirms (normal case):
   
   1. Flutter: Call VerificationEnforcementService.confirmAttendance()
   
   2. Backend: confirm_attendance(attendance_id, supervisor_id) function
      - Validates attendance.supervisor_status = 'PENDING_SUPERVISOR_CONFIRMATION'
      - UPDATE attendance SET
           supervisor_status = 'CONFIRMED',
           supervisor_confirmed_by = supervisor_id,
           supervisor_confirmed_at = NOW()
      
   3. Response: success = true
   
   4. UI shows: "Confirmed"
   
   TABLE CHANGES:
   - attendance: 1 row updated (supervisor_status → CONFIRMED)
   - attendance_verification_tasks: 0 rows (no task created)

3B. IF supervisor disputes (rare case):
   
   1. Supervisor enters dispute_reason: "Guard not present at site"
   
   2. Flutter: Call VerificationEnforcementService.disputeAttendance()
   
   3. Backend: dispute_attendance(attendance_id, supervisor_id, reason) function
      - Validates reason length >= 10 chars
      - UPDATE attendance SET
           supervisor_status = 'DISPUTED',
           supervisor_confirmed_by = supervisor_id,
           supervisor_confirmed_at = NOW(),
           dispute_reason = 'Guard not present at site'
      
   4. Determine required_role:
      - IF trust_score < 40 → 'ADMIN'
      - ELSE → 'FIELD_OFFICER'
   
   5. INSERT into attendance_verification_tasks:
      - attendance_id, organization_id, required_role = 'FIELD_OFFICER'
      - reason_code = 'SUPERVISOR_DISPUTED'
      - status = 'PENDING'
   
   6. Trigger: trigger_auto_assign_verification_task fires
      - Finds unit supervisor or field officer
      - Sets responsible_user_id
      - Sets due_at = NOW() + 24 hours
   
   7. Response: success = true, verification_task_id
   
   TABLE CHANGES:
   - attendance: 1 row updated (supervisor_status → DISPUTED)
   - attendance_verification_tasks: 1 row inserted
```

---

### **C) GUARD ABSENT REPLACEMENT**

```
1. Roster shows guard assigned but not checked in
   - duty_rosters: unit_id = 'unit-1', date = '2026-02-17', shift = 'morning', required_guards = 2
   - unit_assignments: guard A, guard B assigned
   - attendance: guard A checked in, guard B NOT checked in

2. Supervisor opens dispatch UI
   - Query: dispatch_replacement_needed view
   - Shows: "Guard B absent - replacement needed"

3. Supervisor taps "Find Replacement"
   
   1. Backend: find_replacement_guard(unit_id, date, shift, absent_guard_id) function
      - Subquery: Find guards with status = 'available'
      - WHERE NOT EXISTS (attendance for this guard on this date)
      - AND EXISTS (unit_assignment for this guard to this unit)
      - ORDER BY preference score (home unit = higher score)
      - LIMIT 1
   
   2. Returns: replacement_guard_id
   
4. Supervisor confirms replacement
   
   1. Backend: dispatch_replacement(absent_guard_id, replacement_guard_id, unit_id, date, shift) function
      
      2. INSERT into guard_replacements:
         - original_profile_id = guard B
         - replacement_profile_id = guard C
         - unit_id, date, shift, status = 'active'
      
      3. Send notification to guard C (IF notification system exists - currently missing)
   
   3. Response: success = true
   
5. Guard C receives alert, checks in
   - Follows normal check-in flow (see section A)
   - attendance record created for guard C

TABLE CHANGES:
- guard_replacements: 1 row inserted
- attendance: 1 row inserted (when replacement checks in)
```

---

### **D) OFFLINE ATTENDANCE SYNC**

```
1. Guard was offline, punched attendance
   - INSERT into offline_attendance_queue:
     * guard_id, unit_id, attendance_date, shift
     * check_in_time_offline = device local time
     * queued_at = NOW()
     * sync_status = 'pending'

2. Device comes back online
   - Flutter: Detects network (connectivity_plus listener)
   - Calls AttendanceVerificationService.syncQueuedAttendance()

3. Backend sync process:
   
   1. Query offline_attendance_queue WHERE sync_status = 'pending'
   
   2. FOR EACH queued record:
      
      a. INSERT into attendance:
         - guard_id, unit_id, attendance_date, shift
         - check_in_time = queued_record.check_in_time_offline
         - device_timestamp = queued_record.check_in_time_offline
         - server_received_timestamp = NOW()
         - verification_mode = 'DELAYED_SYNC'
         - supervisor_status = 'PENDING_SUPERVISOR_CONFIRMATION'
      
      b. Calculate sync_delay_seconds:
         - sync_delay = server_received_timestamp - device_timestamp
         - Example: 3 hours offline = 10800 seconds
      
      c. Trigger: trigger_auto_compute_attendance_trust_score fires
         - Base score for DELAYED_SYNC:
           * < 1 min delay = 90
           * < 5 min delay = 85
           * < 15 min delay = 75
           * < 1 hour delay = 65
           * > 1 hour delay = 55
         - Example: 3 hour delay = 55 base
         - Deductions: No GPS (-5), No face verification (-0)
         - Final trust_score = 50
      
      d. Trigger: trigger_flag_attendance_for_review fires
         - trust_score (50) < 60 → SET internal_review_flag = true
      
      e. UPDATE offline_attendance_queue SET
         - sync_status = 'synced'
         - synced_at = NOW()

4. Response to Flutter: synced = 1, failed = 0

TABLE CHANGES:
- attendance: 1 row inserted per queued record
- offline_attendance_queue: N rows updated (sync_status → synced)

CRITICAL RISK: No deduplication check
- If syncQueuedAttendance() called twice before first update commits
- OR if network flickers mid-sync
- RESULT: Duplicate attendance records for same guard/date/shift
```

---

### **E) PAYROLL CLOSING**

```
1. Admin opens "Close Payroll Period" UI
   - Period: 2026-02-01 to 2026-02-28

2. Frontend calls: can_close_payroll_period('org-id', '2026-02-01', '2026-02-28')

3. Backend: can_close_payroll_period() function
   
   1. Count DISPUTED attendance in period:
      SELECT COUNT(*) FROM attendance
      WHERE organization_id = 'org-id'
        AND attendance_date >= '2026-02-01'
        AND attendance_date <= '2026-02-28'
        AND supervisor_status = 'DISPUTED'
   
   2. IF disputed_count > 0:
      - Fetch list of disputed records with guard names
      - RETURN: can_close = false, disputed_count, message
   
   3. ELSE:
      - RETURN: can_close = true

4A. IF can_close = false:
   - UI shows error dialog:
     "Cannot close period - 5 disputed attendance records must be resolved"
   - Lists disputed attendance with links to verification tasks
   - Admin cannot proceed

4B. IF can_close = true:
   - Admin clicks "Confirm Close Period"
   - UPDATE payroll_periods SET status = 'CLOSED'
   - Payroll calculation runs (external system)

IMPORTANT: PENDING_SUPERVISOR_CONFIRMATION does NOT block payroll
- Only DISPUTED blocks
- This means payroll can close with unconfirmed attendance
- RISK: Supervisor confirms AFTER payroll closed → amendment needed
```

---

## SECTION 4 — FAILURE POINTS

### **RACE CONDITIONS**

#### 1. **Duplicate Offline Sync** - SEVERITY: HIGH
**Scenario:**
```
T0: Guard offline, punches attendance → offline_attendance_queue row created
T1: Network comes back
T2: syncQueuedAttendance() called
T3: Query finds pending record
T4: Network drops briefly
T5: syncQueuedAttendance() called again (retry)
T6: Query finds SAME pending record (status not yet updated)
T7: Both processes INSERT into attendance table
RESULT: Two attendance records for same guard/date/shift
```

**Broken System State:**
- `attendance` table: 2 rows with identical guard_id, attendance_date, shift
- Payroll calculation: Counts as double shift → overpayment
- Dispatch engine: Shows guard present twice

**Fix Required:** Add UNIQUE constraint on `(guard_id, attendance_date, shift)` OR use upsert with ON CONFLICT

---

#### 2. **Concurrent Verification Task Assignment** - SEVERITY: MEDIUM
**Scenario:**
```
T0: 24 hours pass, task not resolved
T1: Cron escalate_overdue_verification_tasks() starts
T2: Finds task, begins escalation to FIELD_OFFICER
T3: Supervisor simultaneously resolves task (resolve_verification_task)
T4: UPDATE attendance_verification_tasks SET status = 'VERIFIED'
T5: Cron UPDATE attendance_verification_tasks SET escalation_level = 'FIELD_OFFICER'
T6: Task is VERIFIED but escalation_level changed
RESULT: Resolved task marked as escalated (confusing audit trail)
```

**Fix Required:** Add WHERE status = 'PENDING' to escalation UPDATE

---

### **DOUBLE ATTENDANCE**

#### 3. **Manual + Automatic Attendance** - SEVERITY: HIGH
**Scenario:**
```
T0: Guard offline, cannot punch
T1: Supervisor creates manual attendance: verification_mode = 'MANUAL_OVERRIDE'
T2: Guard comes online
T3: Offline queue syncs, creates second attendance
RESULT: Two attendance records for same guard/date/shift
```

**Broken System State:**
- Supervisor confirmed manual attendance
- System auto-created from offline queue
- Both show as valid (PENDING_SUPERVISOR_CONFIRMATION)

**Fix Required:** Check for existing attendance before offline sync insert

---

### **WRONG GUARD ASSIGNED**

#### 4. **Replacement After Attendance Punched** - SEVERITY: MEDIUM
**Scenario:**
```
T0: Guard A assigned to Unit 1
T1: Supervisor sees Guard A not checked in (actually delayed)
T2: Supervisor dispatches Guard B as replacement
T3: guard_replacements: Guard B replaces Guard A
T4: Guard A arrives late, checks in
T5: Guard B also checks in
RESULT: Two guards checked in for one roster slot
```

**Broken System State:**
- duty_rosters.required_guards = 1
- attendance: 2 records (Guard A, Guard B)
- Dispatch shows overstaffed
- Payroll pays both

**Fix Required:** Prevent original guard check-in after replacement dispatched

---

### **UNIT TRANSFER MID-SHIFT**

#### 5. **Guard Assignment Changed During Active Shift** - SEVERITY: HIGH
**Scenario:**
```
T0: Guard checked in at Unit A (08:00 AM)
T1: Admin changes unit_assignment: Unit A → Unit B (10:00 AM)
T2: Guard tries to check out at Unit A (16:00 PM)
T3: Validation: unit_id mismatch (checked in at A, now assigned to B)
RESULT: Cannot check out, shift incomplete
```

**Broken System State:**
- attendance: check_in_time exists, check_out_time NULL
- Payroll: Incomplete shift, wage calculation broken
- Guard stuck in "checked in" state

**Fix Required:** Allow check-out at original check-in unit OR prevent assignment changes during active shifts

---

### **OFFLINE CONFLICTS**

#### 6. **Same Guard Punches Multiple Times Offline** - SEVERITY: MEDIUM
**Scenario:**
```
T0: Guard offline
T1: Guard taps "Check In" → offline_attendance_queue row 1
T2: App crashes, guard reopens
T3: Guard taps "Check In" again → offline_attendance_queue row 2
T4: Network returns, both sync
RESULT: Two attendance records
```

**Broken System State:**
- Same as duplicate sync issue

**Fix Required:** Client-side deduplication OR server-side idempotency key

---

### **ESCALATION LOOPS**

#### 7. **Circular Task Reassignment** - SEVERITY: LOW
**Scenario:**
```
T0: Task assigned to Supervisor A
T1: A reassigns to Field Officer B
T2: B reassigns to Admin C
T3: C reassigns back to A
T4: 24h pass, cron escalates to Field Officer
T5: Ownership circular → task bounces forever
```

**Broken System State:**
- Task never resolved
- Payroll never closes
- Audit trail shows circular reassignments

**Fix Required:** Prevent reassignment once escalated OR limit reassignment frequency

---

### **DEADLOCKS**

#### 8. **Multiple Disputes on Same Day** - SEVERITY: LOW
**Scenario:** (Theoretical PostgreSQL deadlock)
```
Process A: dispute_attendance(guard1, unit1)
  → UPDATE attendance WHERE id = 'att1'
  → INSERT INTO attendance_verification_tasks
Process B: dispute_attendance(guard2, unit1)
  → UPDATE attendance WHERE id = 'att2'
  → INSERT INTO attendance_verification_tasks (trigger locks table)
RESULT: Potential deadlock if trigger locks in reverse order
```

**Current Risk:** Low (different attendance rows, no shared locks expected)

---

### **RLS LOCKOUTS**

#### 9. **Organization Changed Mid-Request** - SEVERITY: LOW
**Scenario:**
```
T0: User authenticated, organization_id = 'org-A'
T1: Query: SELECT * FROM attendance WHERE organization_id = 'org-A'
T2: Admin changes user's organization: org-A → org-B
T3: User tries UPDATE attendance WHERE id = 'att-1' (owned by org-A)
T4: RLS policy: user.organization_id (org-B) != attendance.organization_id (org-A)
RESULT: Permission denied
```

**Broken System State:**
- User sees data, cannot modify
- UI shows stale data

**Fix Required:** Re-authenticate on organization change OR invalidate session

---

#### 10. **Field Officer Access to Admin-Required Task** - SEVERITY: MEDIUM
**Scenario:**
```
T0: Task created with required_role = 'FIELD_OFFICER'
T1: Field officer assigned as responsible_user_id
T2: 48h pass, cron escalates required_role = 'ADMIN'
T3: responsible_user_id unchanged (still field officer)
T4: Field officer tries to resolve task
T5: RLS check: required_role (ADMIN) != user role (FIELD_OFFICER)
RESULT: Permission denied (or allowed but business logic violation)
```

**Broken System State:**
- Task shows as "your task" but cannot resolve
- UI permission error

**Fix Required:** Update responsible_user_id when escalating required_role

---

## SECTION 5 — PRODUCTION READINESS

### **Is system safe for 50 guards?**

**YES** - with caveats:

✅ **Safe:**
- Database schema supports multi-tenancy
- RLS policies prevent cross-organization access
- Basic workflows function
- Performance adequate for small scale

⚠️ **Caveats:**
- Manual monitoring required for offline sync failures
- Admin must manually run escalation cron (not automated)
- No alerting if tasks stuck
- Duplicate attendance possible → manual cleanup needed

---

### **Is system safe for 500 guards?**

**PROBABLY NOT** - without fixes:

❌ **Critical Gaps:**
- **Duplicate attendance risk scales linearly** → 500 guards = 50x higher duplicate risk
- **No cron job configured** → escalate_overdue_verification_tasks() never runs → tasks pile up
- **Offline sync race conditions** → 500 devices syncing = high collision probability
- **No database connection pooling visible** → concurrent check-ins may exhaust connections
- **No rate limiting on API** → flash check-in at shift start = 500 simultaneous INSERTs

⚠️ **Performance Concerns:**
- Haversine distance calculation (photo validation) on every dispute → CPU intensive
- JSONB queries on trust_score_details → index needed
- Sequential offline sync → 100 queued records = slow

**Must Fix Before 500 Guards:**
1. Add UNIQUE constraint on attendance (guard_id, date, shift)
2. Configure cron job for escalation worker
3. Add idempotency key to offline sync
4. Implement connection pooling
5. Add database indexes on hot paths

---

### **Is system safe for 5,000 guards?**

**NO** - requires architectural changes:

❌ **Fundamental Limits:**
- **Synchronous sync model** → 5,000 offline guards coming online = queue overload
- **Single attendance table** → 5,000 guards × 30 days = 150,000 rows/month → query performance degradation
- **Trust score calculation on write path** → 5,000 concurrent check-ins = trigger bottleneck
- **Photo authenticity validation** → Haversine on 5,000 photos = unacceptable latency
- **No sharding strategy** → single Supabase instance limit

**Required for 5,000 Guards:**
1. **Async sync queue** → Message broker (RabbitMQ, SQS) for offline sync
2. **Read replicas** → Separate dispatch queries from write load
3. **Partitioned attendance table** → By date or organization_id
4. **Background trust score calculation** → Move to async worker
5. **Caching layer** → Redis for dispatch status, unit assignments
6. **CDN for photos** → ImageKit integration already planned
7. **Database sharding** → Multi-region Supabase or custom Postgres cluster

---

### **What must be fixed before production?**

#### **BLOCKERS (Fix before ANY production use):**

1. **Duplicate Attendance Prevention**
   ```sql
   ALTER TABLE attendance ADD CONSTRAINT unique_guard_attendance 
   UNIQUE (guard_id, attendance_date, shift);
   ```

2. **Escalation Cron Job**
   - Configure Supabase cron or external scheduler
   - Call `escalate_overdue_verification_tasks()` every hour
   - Add monitoring/alerting for failures

3. **Offline Sync Idempotency**
   - Add `idempotency_key` to offline_attendance_queue
   - Check existing attendance before INSERT

#### **HIGH PRIORITY (Fix within first month):**

4. **Notification System**
   - No notifications implemented → guards don't know about replacements
   - Field officers don't know about escalated tasks

5. **Error Alerting**
   - No monitoring for failed syncs, stuck tasks, deadlocks
   - Admin has no visibility into system health

6. **Database Indexes**
   ```sql
   CREATE INDEX idx_attendance_pending ON attendance(supervisor_status) 
     WHERE supervisor_status = 'PENDING_SUPERVISOR_CONFIRMATION';
   CREATE INDEX idx_offline_queue_pending ON offline_attendance_queue(sync_status)
     WHERE sync_status = 'pending';
   ```

7. **Connection Pooling**
   - Verify Supabase connection limits
   - Configure pgBouncer if needed

#### **MEDIUM PRIORITY (Fix within 3 months):**

8. **Audit Logging**
   - No comprehensive audit trail for configuration changes
   - Cannot track who changed unit assignments, rosters

9. **Data Retention Policy**
   - No archival strategy for old attendance
   - evidence_media_metadata grows unbounded

10. **Backup/Recovery**
    - Verify Supabase backup schedule
    - Test restore procedure
    - Document recovery runbook

---

## SECTION 6 — WHAT THIS PRODUCT ACTUALLY IS

This system is a **supervisor-driven attendance accountability platform** that operates on a trust-first, investigate-later model. Guards punch attendance freely (online or offline), with the system computing a silent trust score (0-100) based on network conditions, GPS accuracy, device identity, and time synchronization. These trust scores create **internal review flags** but never block operations. All attendance defaults to `PENDING_SUPERVISOR_CONFIRMATION` and is **operationally valid** unless explicitly disputed. Supervisors review pending attendance daily and either confirm (workflow ends) or dispute (verification engine activates). Only disputed attendance creates investigation tasks, which escalate automatically if unresolved (24h → Field Officer, 48h → Admin, 72h → payroll blocking). The dispatch engine treats pending and confirmed attendance identically as "present," ignoring verification status entirely. Photo evidence validation runs when provided but cannot block resolution—supervisors can override invalid photos by providing a justification. The system's design philosophy is **"force accountability at payroll, not at punch time"**—guards work uninterrupted, supervisors confirm work happened, and investigations open only when supervisors reject, not when algorithms detect anomalies. The architecture uses Supabase for auth/database, PostgreSQL triggers for trust score calculation, and client-side Flutter for offline queueing, with a critical dependency on a not-yet-configured cron job for task escalation.

---

### **PRODUCTION READINESS CHECKLIST**

```
PILOT (50 guards, single organization, supervised deployment):
[❌] Duplicate attendance prevention (UNIQUE constraint)
[❌] Escalation cron configured
[❌] Offline sync idempotency
[❌] Basic monitoring dashboard
[❌] Notification system for replacements
[ ] Manual runbook for stuck tasks
[ ] Admin training on verification workflow

PAID CLIENT (500 guards, multi-tenant, production SLA):
[❌] All pilot requirements
[❌] Database indexes optimized
[❌] Connection pooling verified
[❌] Error alerting system
[❌] Audit logging comprehensive
[❌] Backup/restore tested
[❌] Performance testing completed
[❌] Legal compliance review (labor law, data retention)

SCALE (5,000+ guards, multi-region, high-availability):
[❌] All paid client requirements
[❌] Async sync architecture (message queue)
[❌] Read replicas for queries
[❌] Database sharding/partitioning
[❌] CDN for media assets
[❌] Caching layer (Redis)
[❌] Load balancer configured
[❌] Disaster recovery plan
[❌] 24/7 on-call support
```

---

**CURRENT STATUS:** Not production-ready. System has solid architecture but critical implementation gaps (duplicate prevention, cron jobs, notifications). Safe for supervised pilot with manual oversight. Requires 3-4 weeks of hardening before paid client deployment.
