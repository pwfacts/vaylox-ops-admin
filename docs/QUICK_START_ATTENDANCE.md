# 🚀 Quick Start Guide - Attendance Engine

## 5-Minute Integration Checklist

### ✅ Prerequisites
- [x] Supabase project set up
- [x] Migrations applied (all 6 attendance migrations)
- [x] Flutter app with `supabase_flutter` package

---

## Step 1: Update Your Guard Model (2 min)

Ensure your `Guard` model has `assignedUnitId` (for primary unit):

```dart
// lib/data/models/guard_model.dart
class Guard {
  final String id;
  final String assignedUnitId;  // ← Primary/home unit
  // ... other fields
}
```

---

## Step 2: Replace Attendance Repository (1 min)

Replace your existing `AttendanceRepository` with the production version:

```bash
# File already created at:
lib/data/repositories/attendance_repository.dart
```

Just import it in your providers/screens.

---

## Step 3: Update Attendance Marking Screen (Guard App)

**File**: `lib/presentation/screens/attendance_mark_screen.dart`

**Key Changes**:
1. Add unit selector dropdown (for multi-unit support)
2. Pass `primaryUnitId` (from guard profile) and `workedUnitId` (selected)
3. Handle duplicate detection response

**Minimal Example**:
```dart
final result = await attendanceRepo.markAttendance(
  attendance: attendanceObject,
  primaryUnitId: currentGuard.assignedUnitId,  // Home unit
  workedUnitId: selectedUnitId,                 // Where working today
  isOffline: !isOnline,
);

if (result['success']) {
  showSuccess('Attendance marked! Pending approval.');
} else if (result['isDuplicate']) {
  showError('Already marked for this shift today.');
}
```

---

## Step 4: Update Approval Screen (Supervisor/Field Officer)

**File**: `lib/presentation/screens/attendance_approval_screen.dart`

**Key Changes**:
1. Use `getPendingApprovals(unitId)` to fetch pending attendance
2. Approve/reject with `updateAttendanceStatus()`

**Minimal Example**:
```dart
// Fetch pending
final supervisorUnitId = currentUser.supervisedUnitId;
final pending = await attendanceRepo.getPendingApprovals(supervisorUnitId);

// Approve
await attendanceRepo.updateAttendanceStatus(
  attendanceId: att.id,
  status: 'APPROVED',
  approverId: currentUser.id,
  notes: 'Verified',
);
```

---

## Step 5: Update Admin Dashboard

**File**: `lib/presentation/screens/attendance_admin_screen.dart`

**Key Changes**:
1. Use `getAttendanceReport()` for viewing attendance
2. Use `voidAttendance()` for voiding (not editing)
3. Use `requestCorrection()` for corrections

**Minimal Example**:
```dart
// View attendance
final report = await attendanceRepo.getAttendanceReport(
  startDate: DateTime(2026, 2, 1),
  endDate: DateTime(2026, 2, 28),
  unitId: selectedUnitId,  // Optional filter
);

// Void (admin only)
await attendanceRepo.voidAttendance(
  attendanceId: att.id,
  voidedBy: currentUser.id,
  reason: 'Marked by mistake',
);
```

---

## Step 6: Run the App

```bash
flutter run
```

That's it! Your attendance system now has:
- ✅ Multi-unit assignment tracking
- ✅ Duplicate prevention
- ✅ Role-based approval (supervisor/FO/admin)
- ✅ Correction workflow for approved records
- ✅ Offline sync with conflict detection
- ✅ Immutable audit trails

---

## 🧪 Quick Test

### Test 1: Mark Attendance (Guard)
1. Login as guard
2. Select shift and unit
3. Mark attendance
4. **Expected**: Success, status = PENDING_APPROVAL

### Test 2: Try to Mark Again (Guard)
1. Try to mark again for same shift
2. **Expected**: Error "Already marked for this shift today"

### Test 3: Approve Attendance (Supervisor)
1. Login as supervisor
2. View pending approvals
3. Approve one
4. **Expected**: Status changes to APPROVED, logged in audit

### Test 4: Try to Edit Approved (Admin)
1. Login as admin
2. Try to edit approved attendance's check-in time
3. **Expected**: Error from database trigger "Cannot edit approved attendance"

### Test 5: Request Correction (Admin)
1. Create correction request for approved attendance
2. **Expected**: Correction created with status PENDING

---

## 🔍 Verify Security

### Test RLS Policy:
1. Login as Supervisor of Unit A
2. Try to view attendance for Unit B
3. **Expected**: Empty list (RLS blocks access)

### Test Approval Scope:
1. Login as Supervisor of Unit A
2. Try to approve attendance for Unit B
3. **Expected**: No rows updated (RLS policy prevents)

---

## 📊 Monitor in Production

### Check Audit Trail:
```sql
SELECT * FROM attendance_approval_log ORDER BY created_at DESC LIMIT 10;
```

### Check Sync Conflicts:
```sql
SELECT * FROM attendance_sync_registry WHERE sync_status = 'DUPLICATE_DETECTED';
```

### Check Pending Corrections:
```sql
SELECT * FROM attendance_corrections WHERE correction_status = 'PENDING';
```

---

## 🐛 Troubleshooting

### Issue: "column units.status does not exist"
**Fix**: Run migration `20260214125253` (already applied)

### Issue: "Cannot mark attendance - duplicate"
**Fix**: Guard already marked for this shift. Check `getTodayAttendance()` first.

### Issue: "Permission denied on attendance"
**Fix**: Check RLS policies. Verify user has correct role and unit assignment.

### Issue: "Cannot edit approved attendance"
**Fix**: This is expected! Use correction workflow instead.

---

## 📞 Quick Links

- **Full Documentation**: `docs/ATTENDANCE_SYSTEM.md`
- **Test Suite**: `docs/ATTENDANCE_TESTS.md`
- **UI Examples**: `docs/ATTENDANCE_UI_GUIDE.md`
- **Summary**: `docs/ATTENDANCE_IMPLEMENTATION_SUMMARY.md`

---

## ✅ You're Ready!

Your attendance system is now:
- 🔒 **Secure** - RLS enforced at database level
- 🌐 **Offline-ready** - Sync with duplicate detection
- 👥 **Multi-unit** - Tracks primary vs worked units
- 📝 **Auditable** - Immutable logs for compliance
- 🚫 **Fraud-proof** - Unique constraints + triggers

**Ship it!** 🚀
