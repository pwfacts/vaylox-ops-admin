# Attendance Engine Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                      🎯 PRODUCTION-GRADE ATTENDANCE ENGINE                       │
│                         Database-Level Security & Integrity                      │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                              📱 APPLICATION LAYER                                │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌──────────────┐   ┌──────────────┐   ┌──────────────┐   ┌──────────────┐    │
│  │   GUARD APP  │   │ SUPERVISOR   │   │ FIELD OFFICER│   │  ADMIN APP   │    │
│  │              │   │     APP      │   │     APP      │   │              │    │
│  ├──────────────┤   ├──────────────┤   ├──────────────┤   ├──────────────┤    │
│  │ • Mark Attn  │   │ • View Pend  │   │ • View Pend  │   │ • View All   │    │
│  │ • View Own   │   │ • Approve/   │   │ • Approve/   │   │ • Void Attn  │    │
│  │ • Offline    │   │   Reject     │   │   Reject     │   │ • Request    │    │
│  │   Support    │   │ • Scoped to  │   │ • Scoped to  │   │   Correction │    │
│  │              │   │   Unit       │   │   Units      │   │ • Payroll    │    │
│  └──────┬───────┘   └──────┬───────┘   └──────┬───────┘   └──────┬───────┘    │
│         │                  │                  │                  │            │
│         └──────────────────┴──────────────────┴──────────────────┘            │
│                                    ▼                                            │
│              ┌────────────────────────────────────────────────┐                │
│              │    AttendanceRepository (Production-Grade)      │                │
│              ├────────────────────────────────────────────────┤                │
│              │ • markAttendance() + duplicate detection       │                │
│              │ • getPendingApprovals() - scoped query         │                │
│              │ • updateAttendanceStatus() - approve/reject    │                │
│              │ • voidAttendance() - admin only                │                │
│              │ • requestCorrection() - workflow trigger       │                │
│              │ • getPayrollAttendance() - APPROVED only       │                │
│              └────────────────┬───────────────────────────────┘                │
│                               │                                                 │
└───────────────────────────────┼─────────────────────────────────────────────────┘
                                ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          🔒 ROW-LEVEL SECURITY LAYER                             │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ RLS POLICIES (Enforced at Database Level)                               │   │
│  ├─────────────────────────────────────────────────────────────────────────┤   │
│  │                                                                          │   │
│  │  GUARD:        INSERT own attendance | SELECT own attendance            │   │
│  │  SUPERVISOR:   SELECT worked_unit_id = supervised_unit_id               │   │
│  │                UPDATE if PENDING_APPROVAL & worked_unit_id matches      │   │
│  │  FIELD OFFICER:SELECT worked_unit_id IN (assigned_units)                │   │
│  │                UPDATE if PENDING_APPROVAL & unit assigned               │   │
│  │  ADMIN:        SELECT all org attendance                                │   │
│  │                UPDATE for void only (trigger prevents other edits)      │   │
│  │                                                                          │   │
│  └──────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└──────────────────────────────────────────┬───────────────────────────────────────┘
                                           ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            🗄️  DATABASE LAYER                                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                        📋 ATTENDANCE TABLE                                │  │
│  ├───────────────────────────────────────────────────────────────────────────┤  │
│  │ CORE FIELDS:                                                              │  │
│  │  • guard_id, attendance_date, shift                                       │  │
│  │  • primary_unit_id (guard's home unit)                                    │  │
│  │  • worked_unit_id (where guard actually worked)                           │  │
│  │  • is_temporary_assignment (auto-set by trigger ⚡)                       │  │
│  │  • approval_status (default: PENDING_APPROVAL)                            │  │
│  │  • is_voided (soft delete flag)                                           │  │
│  │                                                                            │  │
│  │ CONSTRAINTS:                                                               │  │
│  │  ✅ idx_attendance_unique_active:                                          │  │
│  │     UNIQUE (guard_id, date, shift) WHERE is_voided = false               │  │
│  │     → One attendance per shift per day (non-voided)                       │  │
│  │                                                                            │  │
│  │ TRIGGERS:                                                                  │  │
│  │  ⚡ set_temporary_assignment:                                             │  │
│  │     IF worked_unit_id ≠ primary_unit_id THEN is_temporary := true        │  │
│  │  ⚡ log_attendance_approval:                                              │  │
│  │     ON approval_status change → INSERT into approval_log                  │  │
│  │  ⚡ log_attendance_void:                                                  │  │
│  │     ON is_voided = true → INSERT into approval_log                        │  │
│  │  ⚡ prevent_approved_edit:                                                │  │
│  │     IF status = APPROVED AND editing non-void fields → RAISE EXCEPTION    │  │
│  │                                                                            │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                  │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                  📝 ATTENDANCE_CORRECTIONS (Append-Only)                  │  │
│  ├───────────────────────────────────────────────────────────────────────────┤  │
│  │ • attendance_id (FK to attendance)                                        │  │
│  │ • correction_type (TIME_ADJUSTMENT, UNIT_CHANGE, VOID, etc.)             │  │
│  │ • reason, requested_by, approved_by                                       │  │
│  │ • correction_status (PENDING, APPROVED, REJECTED)                         │  │
│  │                                                                            │  │
│  │ PURPOSE: Formal workflow for editing approved attendance                  │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                  │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │                 📊 ATTENDANCE_APPROVAL_LOG (Immutable)                    │  │
│  ├───────────────────────────────────────────────────────────────────────────┤  │
│  │ • attendance_id, action (APPROVED/REJECTED/VOIDED)                        │  │
│  │ • actioned_by, actioned_by_role                                           │  │
│  │ • previous_status, new_status, metadata                                   │  │
│  │                                                                            │  │
│  │ PURPOSE: Immutable audit trail of all approval actions                    │  │
│  │ INSERTED BY: Database triggers (cannot be bypassed)                       │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                  │
│  ┌───────────────────────────────────────────────────────────────────────────┐  │
│  │              🔄 ATTENDANCE_SYNC_REGISTRY (Deduplication)                  │  │
│  ├───────────────────────────────────────────────────────────────────────────┤  │
│  │ • device_id, guard_id, attendance_date, shift                             │  │
│  │ • offline_created_at, synced_attendance_id                                │  │
│  │ • sync_status (SYNCED, DUPLICATE_DETECTED, CONFLICT_RESOLVED)            │  │
│  │ • conflict_resolution_method                                              │  │
│  │                                                                            │  │
│  │ PURPOSE: Track offline sync, detect duplicates                            │  │
│  │ UNIQUE: (device_id, guard_id, date, shift, offline_created_at)           │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                        🛠️  HELPER FUNCTIONS (Database Level)                    │
├─────────────────────────────────────────────────────────────────────────────────┤
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ check_attendance_duplicate(guard, date, shift, device, offline_time)    │   │
│  ├─────────────────────────────────────────────────────────────────────────┤   │
│  │ RETURNS:                                                                 │   │
│  │  • is_duplicate: boolean                                                 │   │
│  │  • existing_attendance_id: uuid                                          │   │
│  │  • conflict_type: EXACT_MATCH | SAME_DEVICE | DIFFERENT_DEVICE          │   │
│  │                                                                           │   │
│  │ PURPOSE: Detect duplicate attendance during offline sync                 │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
│  ┌─────────────────────────────────────────────────────────────────────────┐   │
│  │ get_payroll_attendance(org_id, start_date, end_date, unit_id)           │   │
│  ├─────────────────────────────────────────────────────────────────────────┤   │
│  │ FILTERS:                                                                 │   │
│  │  • approval_status = 'APPROVED'                                          │   │
│  │  • is_voided = FALSE                                                     │   │
│  │                                                                           │   │
│  │ RETURNS: guard_id, dates, shifts, worked_unit_id, OT hours, etc.        │   │
│  │ PURPOSE: Safe data for payroll calculation (only verified attendance)    │   │
│  └─────────────────────────────────────────────────────────────────────────┘   │
│                                                                                  │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                           🔄 DATA FLOW EXAMPLES                                  │
└─────────────────────────────────────────────────────────────────────────────────┘

1️⃣  MARK ATTENDANCE (Guard)
    ───────────────────────────────────────────────────────────────────────
    Guard → markAttendance(primaryUnit=A, workedUnit=B)
         → RLS: Check guard owns this attendance
         → check_attendance_duplicate()
         → If duplicate: REJECT + log in sync_registry
         → If unique: INSERT attendance
         → Trigger: set is_temporary_assignment = (A ≠ B) → TRUE
         → Status: PENDING_APPROVAL

2️⃣  APPROVE ATTENDANCE (Supervisor)
    ───────────────────────────────────────────────────────────────────────
    Supervisor → updateAttendanceStatus(att_id, 'APPROVED')
              → RLS: Check worked_unit_id = supervised_unit_id
              → RLS: Check approval_status = 'PENDING_APPROVAL'
              → UPDATE approval_status = 'APPROVED'
              → Trigger: log_attendance_approval → INSERT into approval_log
              → Log: {action: APPROVED, actioned_by: supervisor, role: supervisor}

3️⃣  TRY TO EDIT APPROVED (Admin) ❌
    ───────────────────────────────────────────────────────────────────────
    Admin → UPDATE attendance SET check_in_time = '10:00'
         → Trigger: prevent_approved_edit
         → IF status = APPROVED AND editing non-void field
         → RAISE EXCEPTION: "Cannot edit approved attendance. Use corrections."
         → ❌ UPDATE BLOCKED

4️⃣  REQUEST CORRECTION (Admin) ✅
    ───────────────────────────────────────────────────────────────────────
    Admin → requestCorrection(att_id, type, reason, field, old, new)
         → INSERT into attendance_corrections
         → Status: PENDING
         → Another admin approved correction
         → Admin manually applies change (or automated)
         → Trigger: logs CORRECTION_APPLIED in approval_log

5️⃣  OFFLINE SYNC (Guard)
    ───────────────────────────────────────────────────────────────────────
    Guard (offline) → markAttendance(..., isOffline=true)
                   → Stored in local SQLite

    Guard (online) → Sync triggered
                  → markAttendance(..., syncedFromOffline=true)
                  → check_attendance_duplicate(device_id, offline_time)
                  → If EXACT_MATCH: Reject + log in sync_registry
                  → If unique: Insert + log in sync_registry (SYNCED)

6️⃣  PAYROLL GENERATION (Accountant)
    ───────────────────────────────────────────────────────────────────────
    Accountant → getPayrollAttendance(org, Feb-2026)
              → Database function filters:
                 - approval_status = 'APPROVED'
                 - is_voided = FALSE
              → Returns only verified attendance
              → Calculate salaries (safe from pending/rejected/voided)

┌─────────────────────────────────────────────────────────────────────────────────┐
│                            ✅ SECURITY GUARANTEES                                │
└─────────────────────────────────────────────────────────────────────────────────┘

🔒 Database-Level:
  ✅ Unique constraint prevents duplicate attendance
  ✅ Triggers auto-set temporary assignment flag
  ✅ Triggers log every approval/void action (immutable)
  ✅ Triggers prevent editing approved attendance

🔒 RLS Policies:
  ✅ Guards can only insert/view their own attendance
  ✅ Supervisors can only approve for their supervised units
  ✅ Field officers can only approve for assigned units
  ✅ Admin can view all but cannot bypass triggers

🔒 Offline Sync:
  ✅ Duplicate detection via check_attendance_duplicate()
  ✅ Conflict tracking in sync_registry
  ✅ Three conflict types: EXACT_MATCH, SAME_DEVICE, DIFFERENT_DEVICE

🔒 Payroll:
  ✅ Only APPROVED + non-voided attendance included
  ✅ Pending/rejected/voided excluded
  ✅ Safe for salary calculation

🔒 Audit:
  ✅ Every action logged in approval_log
  ✅ Append-only (no deletions)
  ✅ Tracks actor, role, timestamp, metadata

┌─────────────────────────────────────────────────────────────────────────────────┐
│                           🎯 SYSTEM SURVIVES                                     │
└─────────────────────────────────────────────────────────────────────────────────┘

✅ Duplicate sync from multiple devices
✅ Multi-unit temporary assignments
✅ Supervisor absence (FO/admin can step in, scoped)
✅ Offline data sync with conflict resolution
✅ Temporary guard deployment to different units
✅ Admin mistakes (correction workflow mandatory)
✅ Fraud attempts (unique constraints + RLS)
✅ Cross-organization data leaks (RLS scoping)

┌─────────────────────────────────────────────────────────────────────────────────┐
│                        📊 PERFORMANCE OPTIMIZATIONS                              │
└─────────────────────────────────────────────────────────────────────────────────┘

Indexes:
  • idx_attendance_unique_active (guard_id, date, shift) WHERE is_voided = false
  • idx_attendance_worked_unit (worked_unit_id) WHERE is_voided = false
  • idx_attendance_approval_status (approval_status) WHERE is_voided = false
  • idx_attendance_date_shift (date, shift) WHERE is_voided = false
  • idx_attendance_device_sync (device_id, offline_time) WHERE synced = true

Query Optimization:
  • Supervisor queries use worked_unit index
  • Payroll queries use approval_status index
  • Offline sync uses device_sync index
  • Filtered indexes reduce index size (only non-voided records)
```
