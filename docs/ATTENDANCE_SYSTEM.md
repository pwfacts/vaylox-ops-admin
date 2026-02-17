# Production-Grade Multi-Unit Attendance Engine

## Overview
This document describes the production-ready attendance system with strict security, multi-unit assignment support, offline sync capabilities, and formal correction workflows.

## Core Features

### 1. **Strict Uniqueness Constraint**
- Guards can mark attendance **only once per shift per day** (for non-voided records)
- Database-level unique index: `idx_attendance_unique_active`  
- Prevents duplicate submissions even during offline sync

### 2. **Multi-Unit Assignment Support**
- **`primary_unit_id`**: Guard's home/assigned unit
- **`worked_unit_id`**: Actual unit where guard worked
- **`is_temporary_assignment`**: Auto-set via trigger when `worked_unit_id ≠ primary_unit_id`

### 3. **Strict Approval Workflow**
- All attendance defaults to **`PENDING_APPROVAL`**
- **Supervisors**: Can approve only if `worked_unit_id = supervised_unit_id`
- **Field Officers**: Can approve only for units in `field_officer_units` mapping
- **Admin**: Cannot edit after approval - must use correction workflow

### 4. **Immutable Audit Trail**
- `attendance_approval_log`: Every approval/rejection is logged via trigger
- `attendance_corrections`: Formal correction requests for approved records
- Append-only - no deletions, only void flags

### 5. **Offline Sync with Duplicate Detection**
- `attendance_sync_registry`: Tracks all synced records
- `check_attendance_duplicate()` function: Detects exact matches, same-device conflicts, etc.
- Conflict resolution strategies: EXACT_MATCH, SAME_DEVICE_DIFFERENT_TIME, DIFFERENT_DEVICE

### 6. **Payroll Integration**
- `get_payroll_attendance()` function: Returns only **APPROVED** and **non-voided** records
- Filters out pending, rejected, or voided attendance
- Used by payroll engine for accurate salary calculation

---

## Database Schema

### Main Tables

#### `attendance`
```sql
-- Core fields
id uuid PRIMARY KEY
organization_id uuid NOT NULL
guard_id uuid NOT NULL
attendance_date date NOT NULL
shift text NOT NULL
worked_unit_id uuid  -- Where guard actually worked
primary_unit_id uuid  -- Guard's home unit
is_temporary_assignment boolean DEFAULT false  -- Auto-set via trigger
is_voided boolean DEFAULT false
approval_status text DEFAULT 'PENDING_APPROVAL'

-- Unique constraint (one attendance per guard/date/shift if not voided)
CREATE UNIQUE INDEX idx_attendance_unique_active 
ON attendance (guard_id, attendance_date, shift) 
WHERE is_voided = false;
```

#### `attendance_corrections`
```sql
id uuid PRIMARY KEY
organization_id uuid NOT NULL
attendance_id uuid NOT NULL  -- References attendance
correction_type text NOT NULL  -- TIME_ADJUSTMENT, UNIT_CHANGE, VOID, etc.
reason text NOT NULL
requested_by uuid NOT NULL
approved_by uuid
correction_status text DEFAULT 'PENDING'  -- PENDING, APPROVED, REJECTED
```

#### `attendance_approval_log`
```sql
id uuid PRIMARY KEY
attendance_id uuid NOT NULL
action text NOT NULL  -- APPROVED, REJECTED, VOIDED, CORRECTION_APPLIED
actioned_by uuid NOT NULL
actioned_by_role text NOT NULL
metadata jsonb  -- Additional context
```

#### `attendance_sync_registry`
```sql
id uuid PRIMARY KEY
device_id text NOT NULL
guard_id uuid NOT NULL
attendance_date date NOT NULL
shift text NOT NULL
offline_created_at timestamptz NOT NULL
synced_attendance_id uuid
sync_status text  -- SYNCED, DUPLICATE_DETECTED, CONFLICT_RESOLVED

-- Ensures exact offline record is tracked only once
UNIQUE(device_id, guard_id, attendance_date, shift, offline_created_at)
```

---

## Database Triggers

### 1. **Auto-Set Temporary Assignment**
```sql
CREATE TRIGGER trg_set_temporary_assignment
BEFORE INSERT OR UPDATE OF worked_unit_id, primary_unit_id
ON attendance
FOR EACH ROW
EXECUTE FUNCTION set_temporary_assignment();
```
- Automatically marks `is_temporary_assignment = true` if units differ

### 2. **Log Approvals/Rejections**
```sql
CREATE TRIGGER trg_log_attendance_approval
AFTER UPDATE OF approval_status
ON attendance
FOR EACH ROW
EXECUTE FUNCTION log_attendance_approval();
```
- Immutably logs every approval or rejection to `attendance_approval_log`

### 3. **Log Voiding Actions**
```sql
CREATE TRIGGER trg_log_attendance_void
AFTER UPDATE OF is_voided
ON attendance
FOR EACH ROW
EXECUTE FUNCTION log_attendance_void();
```

### 4. **Prevent Editing Approved Records**
```sql
CREATE TRIGGER trg_prevent_approved_edit
BEFORE UPDATE
ON attendance
FOR EACH ROW
EXECUTE FUNCTION prevent_approved_attendance_edit();
```
- Raises exception if trying to edit approved attendance
- Only allows voiding (is_voided, voided_by, voided_at, void_reason)
- Forces use of correction workflow for other changes

---

## Row-Level Security (RLS)

### Guards
```sql
-- Can insert their own attendance
CREATE POLICY "attendance_guard_insert" ON attendance
FOR INSERT TO authenticated
WITH CHECK (auth.uid() IN (SELECT user_id FROM guards WHERE id = guard_id));

-- Can view their own attendance
CREATE POLICY "attendance_guard_select" ON attendance
FOR SELECT TO authenticated
USING (auth.uid() IN (SELECT user_id FROM guards WHERE id = guard_id));
```

### Supervisors
```sql
-- View attendance for their supervised units
CREATE POLICY "attendance_supervisor_select" ON attendance
FOR SELECT TO authenticated
USING (EXISTS (
    SELECT 1 FROM guards g
    WHERE g.user_id = auth.uid()
    AND g.is_supervisor = true
    AND g.supervised_unit_id = attendance.worked_unit_id
));

-- Approve only for their units and only PENDING_APPROVAL
CREATE POLICY "attendance_supervisor_approve" ON attendance
FOR UPDATE TO authenticated
USING (EXISTS (
    SELECT 1 FROM guards g
    WHERE g.user_id = auth.uid()
    AND g.is_supervisor = true
    AND g.supervised_unit_id = attendance.worked_unit_id
    AND attendance.approval_status = 'PENDING_APPROVAL'
));
```

### Field Officers
```sql
-- View attendance for assigned units
CREATE POLICY "attendance_field_officer_select" ON attendance
FOR SELECT TO authenticated
USING (EXISTS (
    SELECT 1 FROM field_officer_units fou
    WHERE fou.user_id = auth.uid()
    AND fou.unit_id = attendance.worked_unit_id
));

-- Approve only for assigned units
CREATE POLICY "attendance_field_officer_approve" ON attendance
FOR UPDATE TO authenticated
USING (EXISTS (
    SELECT 1 FROM field_officer_units fou
    WHERE fou.user_id = auth.uid()
    AND fou.unit_id = attendance.worked_unit_id
    AND attendance.approval_status = 'PENDING_APPROVAL'
));
```

### Admin
```sql
-- View all attendance for their organization
CREATE POLICY "attendance_admin_select" ON attendance
FOR SELECT TO authenticated
USING (EXISTS (
    SELECT 1 FROM organization_users ou
    WHERE ou.user_id = auth.uid()
    AND ou.role IN ('admin', 'accountant')
    AND ou.organization_id = attendance.organization_id
));

-- Can void but not edit approved records (trigger enforces this)
CREATE POLICY "attendance_admin_void" ON attendance
FOR UPDATE TO authenticated
USING (EXISTS (
    SELECT 1 FROM organization_users ou
    WHERE ou.user_id = auth.uid()
    AND ou.role = 'admin'
    AND ou.organization_id = attendance.organization_id
));
```

---

## Helper Functions

### 1. **Duplicate Detection**
```dart
final duplicateCheck = await supabase.rpc('check_attendance_duplicate', params: {
  'p_guard_id': guardId,
  'p_attendance_date': '2026-02-14',
  'p_shift': 'DAY',
  'p_device_id': 'DEVICE_ABC',
  'p_offline_created_at': '2026-02-14T10:00:00Z',
});

// Returns: {is_duplicate: true/false, existing_attendance_id: uuid, conflict_type: text}
```

### 2. **Payroll Attendance** 
```dart
final payrollData = await supabase.rpc('get_payroll_attendance', params: {
  'p_organization_id': orgId,
  'p_start_date': '2026-02-01',
  'p_end_date': '2026-02-28',
  'p_unit_id': unitId,  // Optional
});

// Returns only APPROVED and non-voided attendance
```

---

## Usage Examples

### 1. **Mark Attendance (Online)**
```dart
final result = await attendanceRepo.markAttendance(
  attendance: attendanceObject,
  primaryUnitId: guard.assignedUnitId,  // Home unit
  workedUnitId: selectedUnitId,          // Where they're working today
  isOffline: false,
);

if (result['success']) {
  print('Attendance marked: ${result['id']}');
} else if (result['isDuplicate']) {
  print('Duplicate detected: ${result['conflictType']}');
}
```

### 2. **Mark Attendance (Offline, then Sync)**
```dart
// Step 1: Mark offline
await attendanceRepo.markAttendance(
  attendance: attendanceObject,
  primaryUnitId: primaryUnitId,
  workedUnitId: workedUnitId,
  isOffline: true,  // Stores in local DB
);

// Step 2: Sync when online (repository auto-detects duplicates)
await attendanceRepo.markAttendance(
  attendance: attendanceObject.copyWith(syncedFromOffline: true),
  primaryUnitId: primaryUnitId,
  workedUnitId: workedUnitId,
  isOffline: false,
);
```

### 3. **Approve Attendance (Supervisor)**
```dart
await attendanceRepo.updateAttendanceStatus(
  attendanceId: attendanceId,
  status: 'APPROVED',
  approverId: currentUserId,
  notes: 'Verified in person',
);
// Automatically logged in attendance_approval_log via trigger
```

### 4. **Request Correction (After Approval)**
```dart
await attendanceRepo.requestCorrection(
  attendanceId: attendanceId,
  organizationId: orgId,
  type: CorrectionType.timeAdjustment,
  reason: 'Guard forgot to checkout, adjusting based on CCTV',
  requestedBy: currentUserId,
  fieldChanged: 'check_out_time',
  oldValue: 'null',
  newValue: '2026-02-14T18:00:00Z',
);
```

### 5. **Process Correction (Admin)**
```dart
await attendanceRepo.processCorrectionRequest(
  correctionId: correctionId,
  approve: true,
  approvedBy: adminUserId,
);
```

### 6. **Void Attendance (Admin)**
```dart
await attendanceRepo.voidAttendance(
  attendanceId: attendanceId,
  voidedBy: adminUserId,
  reason: 'Marked by mistake - guard was on leave',
);
// Automatically logged in attendance_approval_log
```

### 7. **Get Payroll Data**
```dart
final payrollData = await attendanceRepo.getPayrollAttendance(
  organizationId: orgId,
  startDate: DateTime(2026, 2, 1),
  endDate: DateTime(2026, 2, 28),
);

// Only APPROVED + non-voided records returned
// Safe for salary calculation
```

---

## Security Guarantees

### ✅ Database-Level Security
- RLS enforces access at the database layer
- Even if frontend is compromised, users can only access their authorized data
- Triggers ensure audit logs cannot be bypassed

### ✅ Multi-Unit Safety
- Supervisors can ONLY approve for `worked_unit_id = their supervised_unit_id`
- Field officers can ONLY approve for units in their `field_officer_units` mapping
- No cross-unit approval possible

### ✅ Immutability
- Approved records cannot be edited (trigger prevents it)
- All changes must go through correction workflow
- Every action is logged in `attendance_approval_log`

### ✅ Duplicate Prevention
- Unique index ensures one attendance per shift per day
- Sync registry tracks offline submissions
- Duplicate detection function identifies conflicts

### ✅ Payroll Integrity
- Payroll engine can ONLY read APPROVED + non-voided records
- Pending/rejected/voided attendance is excluded
- Database function ensures consistency

---

## Common Scenarios

### Scenario 1: Guard Works at Different Unit (Temporary Assignment)
```dart
// Guard A is assigned to Unit 1 but works at Unit 2 today
await markAttendance(
  primaryUnitId: 'unit-1-id',  // Home unit
  workedUnitId: 'unit-2-id',    // Where they worked
);
// `is_temporary_assignment` automatically set to `true` via trigger
```

### Scenario 2: Supervisor Absence
- If supervisor is absent, their supervised unit's attendance remains PENDING
- Field officers or admins can step in to approve
- RLS still enforces: Field officers can only approve if unit is in their mapping

### Scenario 3: Duplicate Sync from Offline
1. Guard marks attendance offline (stored in local DB)
2. Device comes online, tries to sync
3. `check_attendance_duplicate()` detects existing record
4. Sync is rejected, entry logged in `attendance_sync_registry`
5. No duplicate attendance created

### Scenario 4: Correcting Approved Attendance
1. Admin notices check-out time is missing
2. Admin creates correction request via `requestCorrection()`
3. Request stored in `attendance_corrections` table (status: PENDING)
4. Another admin/authorized user approves correction
5. Manual update to attendance record (or automated based on your workflow)
6. Logged in `attendance_approval_log` as CORRECTION_APPLIED

---

## Migration Notes

### Applying Migration
The migration was split into:
1. `attendance_engine_production` - Tables, indexes, constraints
2. `attendance_engine_triggers` - Trigger functions
3. `attendance_rls_policies_part1` - Guard/Supervisor policies
4. `attendance_rls_policies_part2` - Field Officer/Admin policies
5. `attendance_rls_other_tables` - Corrections/Log/Sync policies
6. `attendance_helper_functions` - Utility functions

### Backward Compatibility
- Existing `unit_id` column is kept for compatibility
- `worked_unit_id` defaults to `unit_id` if not provided
- Existing attendance records updated to `approval_status = 'PENDING_APPROVAL'`

---

## Testing Checklist

- [ ] Guard can mark attendance for their shift
- [ ] Duplicate attendance is prevented (same guard/date/shift)
- [ ] Supervisor can approve only for their supervised unit
- [ ] Supervisor CANNOT approve for other units
- [ ] Field officer can approve only for assigned units
- [ ] Admin can view all attendance
- [ ] Admin CANNOT edit approved attendance directly
- [ ] Correction workflow creates request successfully
- [ ] Voiding attendance creates log entry
- [ ] Offline sync detects duplicates correctly
- [ ] Payroll function returns only APPROVED + non-voided
- [ ] `is_temporary_assignment` auto-sets when units differ
- [ ] Approval log captures every action

---

## Performance Considerations

### Indexes Created
- `idx_attendance_unique_active` (guard_id, date, shift) WHERE is_voided=false
- `idx_attendance_worked_unit` (worked_unit_id) WHERE is_voided=false
- `idx_attendance_primary_unit` (primary_unit_id) WHERE is_voided=false
- `idx_attendance_approval_status` (approval_status) WHERE is_voided=false
- `idx_attendance_date_shift` (date, shift) WHERE is_voided=false
- `idx_attendance_device_sync` (device_id, offline_created_at) WHERE synced=true

### Query Optimization
- Use `worked_unit_id` for supervisor/FO approval queries
- Use `is_voided = false` filter in all active attendance queries
- Payroll function uses index on approval_status + is_voided

---

## Support & Troubleshooting

### Common Errors

**Error: "Cannot edit approved attendance"**
- **Cause**: Trigger preventing direct edits
- **Solution**: Use correction workflow via `requestCorrection()`

**Error: "Duplicate attendance"**
- **Cause**: Unique constraint violation
- **Solution**: Check existing attendance for guard/date/shift before inserting

**Error: "Permission denied"**
- **Cause**: RLS policy blocking access
- **Solution**: Verify user role and unit assignments

---

## Future Enhancements
- [ ] Auto-approve attendance after N hours if supervisor unavailable
- [ ] Biometric verification integration
- [ ] Geofencing enforcement (GPS within unit radius)
- [ ] Shift swap workflow
- [ ] Leave integration (block attendance if on approved leave)
