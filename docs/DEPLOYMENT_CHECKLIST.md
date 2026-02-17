# ✅ Production Deployment Checklist - Attendance Engine

## Pre-Deployment Verification

### Database Migration Status
- [ ] All 6 attendance migrations applied successfully
  - [ ] `20260214125253` - attendance_engine_production
  - [ ] `20260214125327` - attendance_engine_triggers
  - [ ] `20260214125343` - attendance_rls_policies_part1
  - [ ] `20260214125354` - attendance_rls_policies_part2
  - [ ] `20260214125412` - attendance_rls_other_tables
  - [ ] `20260214125431` - attendance_helper_functions

**Verify**: Run `SELECT * FROM supabase_migrations.schema_migrations ORDER BY version DESC LIMIT 10;`

---

### Database Schema Verification

#### Tables Exist
- [ ] `attendance` table has new columns:
  - [ ] `primary_unit_id uuid`
  - [ ] `worked_unit_id uuid`
  - [ ] `is_temporary_assignment boolean`
  - [ ] `check_in_method text`
  - [ ] `device_id text`
  - [ ] `offline_created_at timestamptz`
  - [ ] `synced_from_offline boolean`
  - [ ] `approval_status text (default: 'PENDING_APPROVAL')`
  
- [ ] `attendance_corrections` table exists
- [ ] `attendance_approval_log` table exists
- [ ] `attendance_sync_registry` table exists

**Verify**: Run `\d attendance` in psql or check in Supabase Table Editor

#### Indexes Exist
- [ ] `idx_attendance_unique_active` (UNIQUE partial index)
- [ ] `idx_attendance_worked_unit`
- [ ] `idx_attendance_primary_unit`
- [ ] `idx_attendance_approval_status`
- [ ] `idx_attendance_date_shift`
- [ ] `idx_attendance_device_sync`

**Verify**: Run `SELECT indexname FROM pg_indexes WHERE tablename = 'attendance';`

#### Triggers Exist
- [ ] `trg_set_temporary_assignment` ON attendance
- [ ] `trg_log_attendance_approval` ON attendance
- [ ] `trg_log_attendance_void` ON attendance
- [ ] `trg_prevent_approved_edit` ON attendance

**Verify**: Run `SELECT tgname FROM pg_trigger WHERE tgrelid = 'attendance'::regclass;`

#### Functions Exist
- [ ] `check_attendance_duplicate()` function
- [ ] `get_payroll_attendance()` function
- [ ] `set_temporary_assignment()` trigger function
- [ ] `log_attendance_approval()` trigger function
- [ ] `log_attendance_void()` trigger function
- [ ] `prevent_approved_attendance_edit()` trigger function

**Verify**: Run `SELECT proname FROM pg_proc WHERE proname LIKE '%attendance%';`

---

### RLS Policies Verification

#### Attendance Table
- [ ] Guards can insert own attendance (`attendance_guard_insert`)
- [ ] Guards can select own attendance (`attendance_guard_select`)
- [ ] Supervisors can select for supervised units (`attendance_supervisor_select`)
- [ ] Supervisors can approve for supervised units (`attendance_supervisor_approve`)
- [ ] Field Officers can select for assigned units (`attendance_field_officer_select`)
- [ ] Field Officers can approve for assigned units (`attendance_field_officer_approve`)
- [ ] Admin can select all org attendance (`attendance_admin_select`)
- [ ] Admin can void attendance (`attendance_admin_void`)

**Verify**: Run `SELECT policyname, cmd FROM pg_policies WHERE tablename = 'attendance';`

#### Other Tables
- [ ] `attendance_corrections` has RLS policies
- [ ] `attendance_approval_log` has RLS policies
- [ ] `attendance_sync_registry` has RLS policies

**Verify**: Run `SELECT tablename, policyname FROM pg_policies WHERE tablename LIKE 'attendance_%';`

---

## Application Code Verification

### Models
- [ ] `AttendanceCorrection` model created (`lib/data/models/attendance_correction_model.dart`)
- [ ] `Attendance` model has fields:
  - [ ] `primaryUnitId`
  - [ ] `workedUnitId`
  - [ ] `isTemporaryAssignment`
  - [ ] `checkInMethod` (or `attendanceMethod`)
  - [ ] `deviceId`
  - [ ] `offlineCreatedAt`
  - [ ] `syncedFromOffline`

### Repository
- [ ] `AttendanceRepository` updated with production methods:
  - [ ] `markAttendance()` with duplicate detection
  - [ ] `getTodayAttendance()`
  - [ ] `getPendingApprovals()`
  - [ ] `updateAttendanceStatus()`
  - [ ] `voidAttendance()`
  - [ ] `getAttendanceLogs()`
  - [ ] `getAttendanceReport()`
  - [ ] `getPayrollAttendance()`
  - [ ] `requestCorrection()`
  - [ ] `processCorrectionRequest()`
  - [ ] `getApprovalLog()`

### UI Integration
- [ ] Attendance marking screen updated:
  - [ ] Unit selector dropdown added
  - [ ] Passes `primaryUnitId` and `workedUnitId`
  - [ ] Handles duplicate detection response
  - [ ] Shows offline status indicator
  
- [ ] Approval screen updated:
  - [ ] Fetches pending approvals using scoped query
  - [ ] Shows temporary assignment indicator
  - [ ] Approve/reject functionality
  - [ ] Logs approval actions
  
- [ ] Admin screen updated:
  - [ ] Cannot edit approved attendance directly
  - [ ] Void functionality
  - [ ] Request correction workflow
  - [ ] View approval log

---

## Functional Testing

### Test 1: Duplicate Prevention ✅
**Steps**:
1. Login as guard
2. Mark attendance for DAY shift
3. Try to mark attendance again for DAY shift
4. **Expected**: Error "Already marked for this shift today"

- [ ] Test passed

### Test 2: Multi-Unit Assignment ✅
**Steps**:
1. Login as guard assigned to Unit A
2. Select Unit B as working unit
3. Mark attendance
4. Verify `primary_unit_id = Unit A`, `worked_unit_id = Unit B`, `is_temporary_assignment = true`

- [ ] Test passed

### Test 3: Supervisor Approval Scope ✅
**Steps**:
1. Login as supervisor of Unit A
2. Try to approve attendance for Unit B
3. **Expected**: No attendance shown / No rows updated (RLS blocks)

- [ ] Test passed

### Test 4: Cannot Edit Approved ✅
**Steps**:
1. Approve an attendance record
2. Try to update `check_in_time`
3. **Expected**: Database error "Cannot edit approved attendance"

- [ ] Test passed

### Test 5: Void Attendance ✅
**Steps**:
1. Login as admin
2. Void an attendance record
3. Verify `is_voided = true` and entry in `attendance_approval_log` with action='VOIDED'

- [ ] Test passed

### Test 6: Correction Workflow ✅
**Steps**:
1. Request correction for approved attendance
2. Verify entry created in `attendance_corrections` with status='PENDING'
3. Approve correction
4. Verify status='APPROVED'

- [ ] Test passed

### Test 7: Offline Sync ✅
**Steps**:
1. Mark attendance offline (stored locally)
2. Come online
3. Sync attendance
4. Try to sync same record again
5. **Expected**: Duplicate detected, logged in `attendance_sync_registry`

- [ ] Test passed

### Test 8: Payroll Integrity ✅
**Steps**:
1. Create attendance records with various statuses (PENDING, APPROVED, REJECTED, voided)
2. Call `getPayrollAttendance()`
3. **Expected**: Only APPROVED + non-voided returned

- [ ] Test passed

---

## Security Testing

### Test 9: Cross-Organization Access ❌
**Steps**:
1. Login as user from Organization A
2. Try to view attendance from Organization B
3. **Expected**: Empty result (RLS blocks)

- [ ] Test passed

### Test 10: Guard Cannot Approve ❌
**Steps**:
1. Login as guard
2. Try to approve own attendance
3. **Expected**: RLS policy violation (no UPDATE policy for guards)

- [ ] Test passed

### Test 11: Supervisor Cannot Approve Other Units ❌
**Steps**:
1. Login as supervisor of Unit A
2. Try to approve attendance for Unit B
3. **Expected**: No rows updated (RLS USING clause filters out)

- [ ] Test passed

---

## Performance Testing

### Test 12: Index Usage
**Steps**:
1. Run `EXPLAIN ANALYZE SELECT * FROM attendance WHERE worked_unit_id = 'unit-id' AND is_voided = false;`
2. **Expected**: Uses `idx_attendance_worked_unit` index

- [ ] Test passed

### Test 13: Duplicate Check Performance
**Steps**:
1. Insert 10,000 attendance records
2. Call `check_attendance_duplicate()`
3. **Expected**: Query completes in < 100ms

- [ ] Test passed

---

## Data Migration (If Upgrading)

### Test 14: Existing Data
- [ ] All existing attendance records have `approval_status` set (default: 'PENDING_APPROVAL')
- [ ] All existing attendance records have `is_voided` set (default: false)
- [ ] Existing `unit_id` values copied to `worked_unit_id` if null
- [ ] No null values in required fields

**Verify**: Run:
```sql
SELECT COUNT(*) FROM attendance WHERE approval_status IS NULL;  -- Should be 0
SELECT COUNT(*) FROM attendance WHERE is_voided IS NULL;        -- Should be 0
SELECT COUNT(*) FROM attendance WHERE worked_unit_id IS NULL;   -- Should be 0
```

---

## Monitoring Setup

### Metrics to Monitor
- [ ] Daily attendance count by status (PENDING, APPROVED, REJECTED)
- [ ] Duplicate sync conflicts count (from `attendance_sync_registry`)
- [ ] Correction requests count (from `attendance_corrections`)
- [ ] Average approval time (from `attendance_approval_log`)
- [ ] Temporary assignment percentage

### Alerts to Setup
- [ ] Alert if > 100 pending approvals for > 24 hours
- [ ] Alert if > 10 duplicate sync conflicts per day
- [ ] Alert if correction requests > 5% of total attendance
- [ ] Alert if any RLS policy violation attempts

**Monitoring Query Examples**:
```sql
-- Pending approvals > 24 hours
SELECT COUNT(*) FROM attendance 
WHERE approval_status = 'PENDING_APPROVAL' 
AND created_at < NOW() - INTERVAL '24 hours';

-- Duplicate conflicts today
SELECT COUNT(*) FROM attendance_sync_registry 
WHERE sync_status = 'DUPLICATE_DETECTED' 
AND created_at::date = CURRENT_DATE;

-- Correction request ratio
SELECT 
  (SELECT COUNT(*) FROM attendance_corrections WHERE created_at::date = CURRENT_DATE) * 100.0 /
  NULLIF((SELECT COUNT(*) FROM attendance WHERE created_at::date = CURRENT_DATE), 0) AS correction_percentage;
```

---

## Documentation Verification

- [ ] `ATTENDANCE_SYSTEM.md` reviewed and understood
- [ ] `ATTENDANCE_TESTS.md` test cases executed
- [ ] `ATTENDANCE_UI_GUIDE.md` UI examples implemented
- [ ] `QUICK_START_ATTENDANCE.md` followed for integration
- [ ] `ATTENDANCE_ARCHITECTURE_DIAGRAM.md` reviewed for system understanding

---

## Rollback Plan

### If Issues Found:
1. **Database Issues**:
   - [ ] Backup current database state
   - [ ] Have migration rollback scripts ready
   - [ ] Document specific SQL to revert changes

2. **Application Issues**:
   - [ ] Keep old repository code in separate branch
   - [ ] Have feature flag to switch back to old system
   - [ ] Document affected UI screens

3. **Data Issues**:
   - [ ] Export attendance data before deployment
   - [ ] Have script to restore data if needed
   - [ ] Document data transformation steps

---

## Final Sign-Off

### Development Team
- [ ] All database migrations applied successfully
- [ ] All triggers and functions tested
- [ ] RLS policies verified
- [ ] Application code integrated and tested
- [ ] Documentation complete

**Signed**: ________________  **Date**: __________

### QA Team
- [ ] All functional tests passed
- [ ] All security tests passed
- [ ] Performance tests passed
- [ ] Edge cases tested (offline, multi-unit, etc.)

**Signed**: ________________  **Date**: __________

### Product Owner
- [ ] Business requirements met
- [ ] User acceptance criteria satisfied
- [ ] Rollback plan approved
- [ ] Go-live approved

**Signed**: ________________  **Date**: __________

---

## Post-Deployment

### First 24 Hours
- [ ] Monitor error logs for RLS violations
- [ ] Monitor attendance marking success rate
- [ ] Monitor approval workflow completion rate
- [ ] Monitor sync conflict rate

### First Week
- [ ] Review approval log for anomalies
- [ ] Review correction requests
- [ ] Review temporary assignment patterns
- [ ] Review payroll data accuracy

### First Month
- [ ] Performance review (query times, index usage)
- [ ] Security audit (RLS policy effectiveness)
- [ ] User feedback collection
- [ ] Documentation updates based on real usage

---

## Emergency Contacts

**Database Issues**: [DBA Name/Contact]
**Application Issues**: [Tech Lead Name/Contact]
**Security Issues**: [Security Team Contact]
**Business Questions**: [Product Owner Contact]

---

**Status**: [ ] NOT READY  [ ] READY FOR DEPLOYMENT  [ ] DEPLOYED

**Date**: __________  **Deployed By**: __________
