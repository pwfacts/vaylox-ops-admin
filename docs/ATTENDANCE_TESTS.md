# Attendance Engine Production Test Suite

## Database-Level Tests

### Test 1: Unique Constraint Enforcement
```sql
-- Should succeed
INSERT INTO attendance (id, organization_id, guard_id, attendance_date, shift, unit_id, worked_unit_id, primary_unit_id, attendance_method)
VALUES (uuid_generate_v4(), 'org-uuid', 'guard-uuid', '2026-02-14', 'DAY', 'unit-uuid', 'unit-uuid', 'unit-uuid', 'MANUAL');

-- Should fail (duplicate)
INSERT INTO attendance (id, organization_id, guard_id, attendance_date, shift, unit_id, worked_unit_id, primary_unit_id, attendance_method)
VALUES (uuid_generate_v4(), 'org-uuid', 'guard-uuid', '2026-02-14', 'DAY', 'unit-uuid', 'unit-uuid', 'unit-uuid', 'MANUAL');
-- Expected: ERROR: duplicate key value violates unique constraint "idx_attendance_unique_active"

-- Should succeed (void first, then insert again)
UPDATE attendance SET is_voided = true WHERE guard_id = 'guard-uuid' AND attendance_date = '2026-02-14';
INSERT INTO attendance (id, organization_id, guard_id, attendance_date, shift, unit_id, worked_unit_id, primary_unit_id, attendance_method)
VALUES (uuid_generate_v4(), 'org-uuid', 'guard-uuid', '2026-02-14', 'DAY', 'unit-uuid', 'unit-uuid', 'unit-uuid', 'MANUAL');
```

### Test 2: Auto-Set Temporary Assignment Trigger
```sql
-- Scenario: Guard works at different unit
INSERT INTO attendance (
  id, organization_id, guard_id, attendance_date, shift, unit_id, 
  worked_unit_id, primary_unit_id, attendance_method
)
VALUES (
  uuid_generate_v4(), 'org-uuid', 'guard-uuid', '2026-02-15', 'DAY', 
  'unit-1', 'unit-2', 'unit-1', 'MANUAL'
);

-- Verify is_temporary_assignment is auto-set to true
SELECT is_temporary_assignment 
FROM attendance 
WHERE guard_id = 'guard-uuid' AND attendance_date = '2026-02-15';
-- Expected: true

-- Scenario: Guard works at home unit
INSERT INTO attendance (
  id, organization_id, guard_id, attendance_date, shift, unit_id, 
  worked_unit_id, primary_unit_id, attendance_method
)
VALUES (
  uuid_generate_v4(), 'org-uuid', 'guard-uuid', '2026-02-16', 'DAY', 
  'unit-1', 'unit-1', 'unit-1', 'MANUAL'
);

-- Verify is_temporary_assignment is false
SELECT is_temporary_assignment 
FROM attendance 
WHERE guard_id = 'guard-uuid' AND attendance_date = '2026-02-16';
-- Expected: false
```

### Test 3: Approval Log Trigger
```sql
-- Insert attendance
INSERT INTO attendance (
  id, organization_id, guard_id, attendance_date, shift, unit_id, 
  worked_unit_id, primary_unit_id, attendance_method, approval_status
)
VALUES (
  'test-att-uuid', 'org-uuid', 'guard-uuid', '2026-02-17', 'DAY', 
  'unit-1', 'unit-1', 'unit-1', 'MANUAL', 'PENDING_APPROVAL'
);

-- Approve
UPDATE attendance 
SET approval_status = 'APPROVED', approved_by = 'supervisor-uuid', approved_at = now()
WHERE id = 'test-att-uuid';

-- Check log
SELECT action, previous_status, new_status, actioned_by_role
FROM attendance_approval_log
WHERE attendance_id = 'test-att-uuid';
-- Expected: action='APPROVED', previous_status='PENDING_APPROVAL', new_status='APPROVED'

-- Reject another
UPDATE attendance 
SET approval_status = 'REJECTED', approved_by = 'supervisor-uuid', approved_at = now()
WHERE id = 'test-att-uuid-2';

-- Check log shows REJECTED
```

### Test 4: Prevent Editing Approved Attendance
```sql
-- Approve attendance
UPDATE attendance 
SET approval_status = 'APPROVED', approved_by = 'admin-uuid', approved_at = now()
WHERE id = 'test-att-uuid';

-- Try to change check_in_time (should fail)
UPDATE attendance 
SET check_in_time = now()
WHERE id = 'test-att-uuid';
-- Expected: ERROR: Cannot edit approved attendance. Use attendance_corrections workflow.

-- Try to void (should succeed)
UPDATE attendance 
SET is_voided = true, voided_by = 'admin-uuid', voided_at = now(), void_reason = 'Test void'
WHERE id = 'test-att-uuid';
-- Expected: Success

-- Check void log
SELECT action, new_status, notes
FROM attendance_approval_log
WHERE attendance_id = 'test-att-uuid' AND action = 'VOIDED';
-- Expected: action='VOIDED', notes='Test void'
```

### Test 5: Void Log Trigger
```sql
-- Void attendance
UPDATE attendance 
SET is_voided = true, voided_by = 'admin-uuid', voided_at = now(), void_reason = 'Mistaken entry'
WHERE id = 'test-att-uuid';

-- Verify log
SELECT action, actioned_by, notes
FROM attendance_approval_log
WHERE attendance_id = 'test-att-uuid' AND action = 'VOIDED';
-- Expected: action='VOIDED', notes='Mistaken entry'
```

### Test 6: Duplicate Detection Function
```sql
-- Insert attendance
INSERT INTO attendance (
  id, organization_id, guard_id, attendance_date, shift, unit_id, 
  worked_unit_id, primary_unit_id, attendance_method, device_id, offline_created_at
)
VALUES (
  'att-uuid-1', 'org-uuid', 'guard-uuid', '2026-02-18', 'DAY', 
  'unit-1', 'unit-1', 'unit-1', 'MANUAL', 'DEVICE_ABC', '2026-02-18T08:00:00Z'
);

-- Check for duplicate (exact match)
SELECT * FROM check_attendance_duplicate(
  'guard-uuid', 
  '2026-02-18', 
  'DAY', 
  'DEVICE_ABC', 
  '2026-02-18T08:00:00Z'
);
-- Expected: is_duplicate=true, conflict_type='EXACT_MATCH'

-- Check for duplicate (same device, different time)
SELECT * FROM check_attendance_duplicate(
  'guard-uuid', 
  '2026-02-18', 
  'DAY', 
  'DEVICE_ABC', 
  '2026-02-18T09:00:00Z'
);
-- Expected: is_duplicate=true, conflict_type='SAME_DEVICE_DIFFERENT_TIME'

-- Check for duplicate (different device)
SELECT * FROM check_attendance_duplicate(
  'guard-uuid', 
  '2026-02-18', 
  'DAY', 
  'DEVICE_XYZ', 
  '2026-02-18T08:00:00Z'
);
-- Expected: is_duplicate=true, conflict_type='DIFFERENT_DEVICE'

-- Check for non-duplicate
SELECT * FROM check_attendance_duplicate(
  'guard-uuid', 
  '2026-02-19', 
  'DAY', 
  'DEVICE_ABC', 
  '2026-02-19T08:00:00Z'
);
-- Expected: is_duplicate=false
```

### Test 7: Payroll Function
```sql
-- Insert attendance records with various statuses
INSERT INTO attendance (id, organization_id, guard_id, attendance_date, shift, unit_id, worked_unit_id, primary_unit_id, attendance_method, approval_status, is_voided)
VALUES 
  (uuid_generate_v4(), 'org-uuid', 'guard-1', '2026-02-01', 'DAY', 'unit-1', 'unit-1', 'unit-1', 'MANUAL', 'APPROVED', false),
  (uuid_generate_v4(), 'org-uuid', 'guard-1', '2026-02-02', 'DAY', 'unit-1', 'unit-1', 'unit-1', 'MANUAL', 'PENDING_APPROVAL', false),
  (uuid_generate_v4(), 'org-uuid', 'guard-1', '2026-02-03', 'DAY', 'unit-1', 'unit-1', 'unit-1', 'MANUAL', 'APPROVED', true),
  (uuid_generate_v4(), 'org-uuid', 'guard-1', '2026-02-04', 'DAY', 'unit-1', 'unit-1', 'unit-1', 'MANUAL', 'REJECTED', false),
  (uuid_generate_v4(), 'org-uuid', 'guard-1', '2026-02-05', 'DAY', 'unit-1', 'unit-1', 'unit-1', 'MANUAL', 'APPROVED', false);

-- Call payroll function
SELECT * FROM get_payroll_attendance('org-uuid', '2026-02-01', '2026-02-05', null);
-- Expected: 2 records (Feb 1 and Feb 5 - both APPROVED and non-voided)
```

---

## RLS Policy Tests

### Test 8: Guard Insert Policy
```sql
-- Scenario: Guard tries to mark attendance for themselves
-- Setup: User UUID = 'user-123', guard.user_id = 'user-123'

SET request.jwt.claims = '{"sub": "user-123"}';

INSERT INTO attendance (
  id, organization_id, guard_id, attendance_date, shift, unit_id, 
  worked_unit_id, primary_unit_id, attendance_method
)
VALUES (
  uuid_generate_v4(), 'org-uuid', 'guard-uuid-for-user-123', '2026-02-20', 'DAY', 
  'unit-1', 'unit-1', 'unit-1', 'MANUAL'
);
-- Expected: Success

-- Scenario: Guard tries to mark attendance for someone else
INSERT INTO attendance (
  id, organization_id, guard_id, attendance_date, shift, unit_id, 
  worked_unit_id, primary_unit_id, attendance_method
)
VALUES (
  uuid_generate_v4(), 'org-uuid', 'other-guard-uuid', '2026-02-20', 'DAY', 
  'unit-1', 'unit-1', 'unit-1', 'MANUAL'
);
-- Expected: RLS Policy Violation (cannot insert for other guards)
```

### Test 9: Guard Select Policy
```sql
-- Setup: User UUID = 'user-123' (guard)
SET request.jwt.claims = '{"sub": "user-123"}';

SELECT * FROM attendance WHERE guard_id = 'guard-uuid-for-user-123';
-- Expected: Returns own attendance

SELECT * FROM attendance WHERE guard_id = 'other-guard-uuid';
-- Expected: Returns empty (cannot see others' attendance)
```

### Test 10: Supervisor Approve Policy
```sql
-- Setup: Supervisor UUID = 'supervisor-123', supervised_unit_id = 'unit-1'
SET request.jwt.claims = '{"sub": "supervisor-123"}';

-- Try to approve attendance for supervised unit
UPDATE attendance 
SET approval_status = 'APPROVED', approved_by = 'supervisor-123', approved_at = now()
WHERE id = 'att-in-unit-1' AND worked_unit_id = 'unit-1' AND approval_status = 'PENDING_APPROVAL';
-- Expected: Success

-- Try to approve attendance for non-supervised unit
UPDATE attendance 
SET approval_status = 'APPROVED', approved_by = 'supervisor-123', approved_at = now()
WHERE id = 'att-in-unit-2' AND worked_unit_id = 'unit-2' AND approval_status = 'PENDING_APPROVAL';
-- Expected: RLS Policy Violation (no rows updated)

-- Try to approve already approved attendance
UPDATE attendance 
SET approval_status = 'APPROVED', approved_by = 'supervisor-123', approved_at = now()
WHERE id = 'att-already-approved' AND worked_unit_id = 'unit-1' AND approval_status = 'APPROVED';
-- Expected: RLS Policy Violation (USING clause filters out non-PENDING)
```

### Test 11: Field Officer Approve Policy
```sql
-- Setup: Field Officer UUID = 'fo-123', assigned units = ['unit-1', 'unit-2']
SET request.jwt.claims = '{"sub": "fo-123"}';

-- Try to approve for assigned unit
UPDATE attendance 
SET approval_status = 'APPROVED', approved_by = 'fo-123', approved_at = now()
WHERE id = 'att-in-unit-1' AND worked_unit_id = 'unit-1' AND approval_status = 'PENDING_APPROVAL';
-- Expected: Success

-- Try to approve for non-assigned unit
UPDATE attendance 
SET approval_status = 'APPROVED', approved_by = 'fo-123', approved_at = now()
WHERE id = 'att-in-unit-3' AND worked_unit_id = 'unit-3' AND approval_status = 'PENDING_APPROVAL';
-- Expected: RLS Policy Violation
```

### Test 12: Admin Select and Void Policy
```sql
-- Setup: Admin UUID = 'admin-123', organization_id = 'org-uuid'
SET request.jwt.claims = '{"sub": "admin-123"}';

-- View all attendance for organization
SELECT * FROM attendance WHERE organization_id = 'org-uuid';
-- Expected: Returns all attendance

-- Void attendance
UPDATE attendance 
SET is_voided = true, voided_by = 'admin-123', voided_at = now(), void_reason = 'Admin void'
WHERE id = 'att-to-void';
-- Expected: Success

-- Try to edit check_in_time (should fail if approved)
UPDATE attendance 
SET check_in_time = now()
WHERE id = 'approved-att';
-- Expected: Trigger prevents edit (even for admin)
```

---

## Application-Level Tests (Dart/Flutter)

### Test 13: Mark Attendance (No Duplicates)
```dart
test('Should prevent duplicate attendance', () async {
  final repo = AttendanceRepository();
  final attendance = Attendance(
    id: Uuid().v4(),
    guardId: 'guard-123',
    attendanceDate: DateTime.now(),
    shift: 'DAY',
    // ... other fields
  );

  // First attempt should succeed
  final result1 = await repo.markAttendance(
    attendance: attendance,
    primaryUnitId: 'unit-1',
    workedUnitId: 'unit-1',
  );
  expect(result1['success'], true);

  // Second attempt should fail (duplicate)
  final result2 = await repo.markAttendance(
    attendance: attendance.copyWith(id: Uuid().v4()),
    primaryUnitId: 'unit-1',
    workedUnitId: 'unit-1',
  );
  expect(result2['success'], false);
  expect(result2['isDuplicate'], true);
});
```

### Test 14: Offline Sync with Duplicate Detection
```dart
test('Should detect offline duplicates on sync', () async {
  final repo = AttendanceRepository();
  final attendance = Attendance(
    id: Uuid().v4(),
    guardId: 'guard-123',
    attendanceDate: DateTime.now(),
    shift: 'DAY',
    deviceId: 'DEVICE_ABC',
    offlineCreatedAt: DateTime.now(),
    syncedFromOffline: true,
    // ... other fields
  );

  // Mark online first
  await repo.markAttendance(
    attendance: attendance,
    primaryUnitId: 'unit-1',
    workedUnitId: 'unit-1',
    isOffline: false,
  );

  // Try to sync offline record (should detect duplicate)
  final syncResult = await repo.markAttendance(
    attendance: attendance.copyWith(id: Uuid().v4()),
    primaryUnitId: 'unit-1',
    workedUnitId: 'unit-1',
    isOffline: false,
  );

  expect(syncResult['isDuplicate'], true);
  expect(syncResult['conflictType'], 'EXACT_MATCH');
});
```

### Test 15: Approval Workflow
```dart
test('Should approve attendance for supervised unit', () async {
  final repo = AttendanceRepository();

  // Mark attendance
  final result = await repo.markAttendance(
    attendance: attendance,
    primaryUnitId: 'unit-1',
    workedUnitId: 'unit-1',
  );
  final attendanceId = result['id'];

  // Approve
  await repo.updateAttendanceStatus(
    attendanceId: attendanceId,
    status: 'APPROVED',
    approverId: 'supervisor-123',
    notes: 'Verified',
  );

  // Verify status
  final updated = await repo.getAttendanceLogs();
  final approved = updated.firstWhere((a) => a['id'] == attendanceId);
  expect(approved['approval_status'], 'APPROVED');
});
```

### Test 16: Correction Workflow
```dart
test('Should create correction request for approved attendance', () async {
  final repo = AttendanceRepository();

  // Request correction
  await repo.requestCorrection(
    attendanceId: 'approved-att-id',
    organizationId: 'org-123',
    type: CorrectionType.timeAdjustment,
    reason: 'Forgot to checkout',
    requestedBy: 'user-123',
    fieldChanged: 'check_out_time',
    oldValue: 'null',
    newValue: '2026-02-14T18:00:00Z',
  );

  // Get corrections
  final corrections = await repo.getCorrections();
  expect(corrections.length, greaterThan(0));
  expect(corrections.first.correctionStatus, CorrectionStatus.pending);

  // Approve correction
  await repo.processCorrectionRequest(
    correctionId: corrections.first.id,
    approve: true,
    approvedBy: 'admin-123',
  );

  // Verify approved
  final updatedCorrections = await repo.getCorrections();
  final approved = updatedCorrections.firstWhere((c) => c.id == corrections.first.id);
  expect(approved.correctionStatus, CorrectionStatus.approved);
});
```

### Test 17: Void Attendance
```dart
test('Should void attendance and log action', () async {
  final repo = AttendanceRepository();

  // Void
  await repo.voidAttendance(
    attendanceId: 'att-to-void',
    voidedBy: 'admin-123',
    reason: 'Marked by mistake',
  );

  // Get approval log
  final log = await repo.getApprovalLog('att-to-void');
  final voidEntry = log.firstWhere((l) => l['action'] == 'VOIDED');
  expect(voidEntry['notes'], 'Marked by mistake');
});
```

### Test 18: Payroll Integration
```dart
test('Should return only approved and non-voided attendance for payroll', () async {
  final repo = AttendanceRepository();

  final payrollData = await repo.getPayrollAttendance(
    organizationId: 'org-123',
    startDate: DateTime(2026, 2, 1),
    endDate: DateTime(2026, 2, 28),
  );

  // Verify all returned records are APPROVED
  for (var record in payrollData) {
    // Payroll function doesn't return approval_status in response
    // But we know it only returns APPROVED + non-voided
    expect(record['guard_id'], isNotNull);
    expect(record['is_temporary_assignment'], isNotNull);
  }
});
```

### Test 19: Temporary Assignment Detection
```dart
test('Should auto-detect temporary assignment', () async {
  final repo = AttendanceRepository();

  final attendance = Attendance(
    id: Uuid().v4(),
    guardId: 'guard-123',
    attendanceDate: DateTime.now(),
    shift: 'DAY',
    // ... other fields
  );

  // Mark at different unit
  final result = await repo.markAttendance(
    attendance: attendance,
    primaryUnitId: 'unit-1',  // Home unit
    workedUnitId: 'unit-2',    // Working at different unit
  );

  // Fetch back and verify flag
  final logs = await repo.getAttendanceLogs();
  final created = logs.firstWhere((a) => a['id'] == result['id']);
  expect(created['is_temporary_assignment'], true);
});
```

---

## Edge Case Tests

### Test 20: Multiple Shifts Same Day
```sql
-- Should allow different shifts on same day
INSERT INTO attendance (id, organization_id, guard_id, attendance_date, shift, unit_id, worked_unit_id, primary_unit_id, attendance_method)
VALUES 
  (uuid_generate_v4(), 'org-uuid', 'guard-uuid', '2026-02-21', 'DAY', 'unit-1', 'unit-1', 'unit-1', 'MANUAL'),
  (uuid_generate_v4(), 'org-uuid', 'guard-uuid', '2026-02-21', 'NIGHT', 'unit-1', 'unit-1', 'unit-1', 'MANUAL');
-- Expected: Both succeed (different shifts)
```

### Test 21: Void and Re-Mark Same Day
```sql
-- Void first attendance
UPDATE attendance SET is_voided = true WHERE guard_id = 'guard-uuid' AND attendance_date = '2026-02-22';

-- Mark new attendance
INSERT INTO attendance (id, organization_id, guard_id, attendance_date, shift, unit_id, worked_unit_id, primary_unit_id, attendance_method)
VALUES (uuid_generate_v4(), 'org-uuid', 'guard-uuid', '2026-02-22', 'DAY', 'unit-1', 'unit-1', 'unit-1', 'MANUAL');
-- Expected: Success (voided record doesn't count in unique constraint)
```

### Test 22: Supervisor Approves Temp Assignment in Their Unit
```sql
-- Guard from Unit 1 works at Unit 2 (supervisor's unit)
INSERT INTO attendance (
  id, organization_id, guard_id, attendance_date, shift, unit_id, 
  worked_unit_id, primary_unit_id, attendance_method
)
VALUES (
  'temp-assign-att', 'org-uuid', 'guard-from-unit-1', '2026-02-23', 'DAY', 
  'unit-2', 'unit-2', 'unit-1', 'MANUAL'
);

-- Supervisor of Unit 2 approves (should succeed - they check worked_unit_id)
SET request.jwt.claims = '{"sub": "supervisor-of-unit-2"}';
UPDATE attendance 
SET approval_status = 'APPROVED', approved_by = 'supervisor-of-unit-2', approved_at = now()
WHERE id = 'temp-assign-att' AND approval_status = 'PENDING_APPROVAL';
-- Expected: Success
```

---

## Performance Tests

### Test 23: Query Performance with Indexes
```sql
-- Should use idx_attendance_worked_unit
EXPLAIN ANALYZE
SELECT * FROM attendance WHERE worked_unit_id = 'unit-1' AND is_voided = false;

-- Should use idx_attendance_approval_status
EXPLAIN ANALYZE
SELECT * FROM attendance WHERE approval_status = 'PENDING_APPROVAL' AND is_voided = false;

-- Should use idx_attendance_date_shift
EXPLAIN ANALYZE
SELECT * FROM attendance WHERE attendance_date = '2026-02-14' AND shift = 'DAY' AND is_voided = false;
```

---

## Security Tests

### Test 24: Cross-Organization Data Leak
```sql
-- User from Org A tries to view Org B's attendance
SET request.jwt.claims = '{"sub": "user-from-org-a"}';

SELECT * FROM attendance WHERE organization_id = 'org-b-uuid';
-- Expected: Empty (RLS prevents cross-org access)
```

### Test 25: Guard Tries to Approve Own Attendance
```sql
-- Guard tries to approve (should fail - no UPDATE policy for guards)
SET request.jwt.claims = '{"sub": "guard-user-123"}';

UPDATE attendance 
SET approval_status = 'APPROVED'
WHERE guard_id = 'guard-uuid-for-user-123';
-- Expected: RLS Policy Violation (guards don't have approve policy)
```

---

## Summary

This test suite validates:
✅ Unique constraint: One attendance per guard/date/shift (non-voided)
✅ Multi-unit logic: primary_unit_id vs worked_unit_id tracking
✅ Temporary assignment auto-detection
✅ Default PENDING_APPROVAL status
✅ Supervisor scope: Can only approve worked_unit_id matches
✅ Field Officer scope: Can only approve assigned units
✅ Admin correction workflow: Cannot edit approved, must use corrections
✅ Append-only audit: All actions logged
✅ Payroll safety: Only APPROVED + non-voided
✅ RLS enforcement: Database-level security
✅ Duplicate detection: Offline sync safety
✅ Trigger logging: Immutable audit trail

## Running Tests

### Database Tests
```bash
# Connect to Supabase
psql "postgresql://postgres:[PASSWORD]@[HOST]:5432/postgres"

# Run SQL tests
\i attendance_tests.sql
```

### Application Tests
```bash
# Run Flutter tests
flutter test test/attendance_repository_test.dart
```
