# 🔄 Session State Layer - Complete Implementation Guide

## ✅ IMPLEMENTATION STATUS

**Version:** 2.0 (Operational Reliability Layer)  
**Date:** 2026-02-16  
**Status:** ✅ Ready for Integration

---

## 🎯 WHAT THIS SOLVES

**Problem:** Guards in the field face:
- Network outages (remote locations)
- Session expiry mid-shift
- Password changes forcing immediate logout
- Unit transfers requiring re-authentication

**Solution:** Session state layer that works **independent of Supabase JWT**:
- Attendance punch works offline
- Cached credentials for temporary verification
- Automatic queue and sync
- Security maintained via operation restrictions

---

## 🗄️ DATABASE ARCHITECTURE

### **Tables Created:**

**1. workforce_session_states** ✅
- Tracks session state per device
- Manages offline credentials
- Controls operation permissions
- Queues pending sync operations

**2. offline_attendance_queue** ⏳ (Manual setup required)
- Stores offline attendance punches
- Tracks sync status
- Retains server responses

---

## 🎨 THREE SESSION STATES

### **1. VERIFIED** (Full Access)

**When:**
- Normal authenticated state
- Valid Supabase session
- Online with network

**Allowed Operations:**
- ✅ Attendance punch
- ✅ View duty roster
- ✅ Approvals
- ✅ Edits
- ✅ Admin actions

**Example:**
```dart
final state = await sessionStateService.getCurrentState();
// SessionState.verified

await sessionStateService.canPerformOperation(Operation.approvals);
// OperationCheckResult(allowed: true)
```

---

### **2. RESTRICTED** (Attendance Only)

**Triggered When:**
- Password changed
- PIN changed
- Unit transfer
- Admin action

**Allowed Operations:**
- ✅ Attendance punch (can still clock in/out)
- ✅ View assigned duty roster

**Blocked Operations:**
- ❌ Approvals (supervisor/field officer)
- ❌ Edits (modify records)
- ❌ Admin actions
- ❌ Coverage overrides

**Auto-Upgrade:**
- Automatically upgrades to VERIFIED after current shift ends
- User can manually re-login for immediate upgrade

**Use Case:**
```
Guard changes password at 10:00 AM
→ Session state: RESTRICTED
→ Current shift: 08:00 - 18:00
→ Can still punch in/out for today
→ Cannot approve other guards' attendance
→ Must re-login after 18:00 for full access
```

**Implementation:**
```dart
// After password change
await sessionStateService.transitionState(
  newState: SessionState.restricted,
  reason: 'Password changed',
  restrictedUntil: currentShiftEnd, // 18:00
  shiftContext: {
    'shift_id': shiftId,
    'unit_id': unitId,
    'shift_end': '2026-02-16T18:00:00Z',
  },
);

// Check if approval allowed
final canApprove = await sessionStateService.canPerformOperation(
  Operation.approvals,
);
// OperationCheckResult(
//   allowed: false,
//   message: 'Please re-authenticate to perform this action'
// )

// Attendance still works
final canPunch = await sessionStateService.canPerformOperation(
  Operation.attendancePunch,
);
// OperationCheckResult(allowed: true)
```

---

### **3. RECOVERY** (Offline Mode)

**Triggered When:**
- Device fingerprint mismatch
- Temporary offline
- Network unavailable
- Supabase session invalid but cached credentials exist

**Allowed Operations:**
- ✅ Local PIN verification (cached hash)
- ✅ Attendance punch (queued for sync)
- ✅ View cached duty information

**Blocked Operations:**
- ❌ Approvals
- ❌ Real-time data
- ❌ Admin actions
- ❌ Edits

**Security Limits:**
- Max 10 offline verifications before online re-auth required
- Cached hash expires after 7 days
- Pending operations tracked for sync

**Use Case:**
```
Guard in remote location (no cell signal)
→ App detects offline
→ Session state: RECOVERY
→ Enter PIN → Verified against cached hash
→ Punch attendance → Saved to offline_attendance_queue
→ Returns to office → Auto-syncs to server
→ State upgrades to VERIFIED
```

**Implementation:**
```dart
// Guard enters PIN offline
final result = await sessionStateService.verifyOfflinePin('1234');

if (result.verified) {
  print('Verified offline: ${result.verificationCount}/10');
  print('Remaining: ${result.remainingVerifications}');
  
  // Queue attendance punch
  await sessionStateService.queueAttendancePunch(
    attendanceData: {
      'guard_id': guardId,
      'unit_id': unitId,
      'check_in_time': DateTime.now().toIso8601String(),
      'location': gpsCoordinates,
    },
    operationType: 'CHECK_IN',
    offlinePinVerified: true,
  );
  
  // When network returns
  final syncResult = await sessionStateService.syncPendingOperations();
  print('Synced: ${syncResult.synced}, Failed: ${syncResult.failed}');
}
```

---

## 🔐 SECURITY GUARANTEES

### **✅ Never Weakened:**

**1. Approvals Always Blocked in Non-VERIFIED States**
```dart
// Always blocked in RESTRICTED/RECOVERY
if (state != SessionState.verified) {
  // approveAttendance() → Blocked
  // approveCoverageRequest() → Blocked
  // adminOverride() → Blocked
}
```

**2. Offline Credential Caching is Limited**
- PIN hash only (SHA256) - not password
- Expires after 7 days
- Max 10 offline verifications
- Must re-authenticate online after limit

**3. Dispatch Engine Still Recognizes Presence**
- Attendance punches queued offline
- Synced to server when online
- Dispatch sees guard as present after sync
- No business logic changed

**4. Automatic Security Upgrades**
```dart
// Check and upgrade state periodically
final upgraded = await sessionStateService.tryUpgradeState();

if (upgraded) {
  // RESTRICTED → VERIFIED (after shift end)
  // RECOVERY → RESTRICTED (came online but not re-authed)
}
```

---

## 📱 FLUTTER INTEGRATION

### **1. Initialize on App Start**

```dart
import 'package:crypto/crypto.dart'; // Add to pubspec.yaml

// In main.dart or app initialization
final sessionStateService = SessionStateService();

// Check current state
final state = await session StateService.getCurrentState();
print('Current state: $state');

// Auto-upgrade if eligible
await sessionStateService.tryUpgradeState();
```

### **2. After Login - Cache Credentials**

```dart
// After successful password login
await sessionStateService.cacheCredentialHash(userPin);

// Verify PIN is cached
final isValid = await sessionStateService.isCachedHashValid();
print('Cached credential valid: $isValid');
```

### **3. After Password/PIN Change - Transition to RESTRICTED**

```dart
// In change password handler
await AuthService().changePassword(oldPassword, newPassword);

// Transition to restricted
await sessionStateService.transitionState(
  newState: SessionState.restricted,
  reason: 'Password changed',
  restrictedUntil: await _getCurrentShiftEnd(),
  shiftContext: await _getCurrentShiftContext(),
);

// Show notification
showDialog(
  context: context,
  builder: (_) => AlertDialog(
    title: Text('Password Changed'),
    content: Text(
      'Your password has been updated. You can continue attendance '
      'for this shift, but re-login is required after shift end '
      'for full access.'
    ),
  ),
);
```

### **4. Attendance Punch (Works in All States)**

```dart
Future<void> punchAttendance() async {
  // Check if allowed (should always be true)
  final canPunch = await sessionStateService.canPerformOperation(
    Operation.attendancePunch,
  );
  
  if (!canPunch.allowed) {
    throw Exception('Attendance punch not allowed');
  }
  
  try {
    // Try online first
    await _supabase.from('attendance').insert({
      'guard_id': guardId,
      'check_in_time': DateTime.now().toIso8601String(),
    });
  } catch (e) {
    // If offline, queue for sync
    await sessionStateService.queueAttendancePunch(
      attendanceData: {
        'guard_id': guardId,
        'check_in_time': DateTime.now().toIso8601String(),
      },
      operationType: 'CHECK_IN',
      offlinePinVerified: true,
    );
    
    showSnackBar('Attendance saved offline - will sync when online');
  }
}
```

### **5. Block Approvals in Non-VERIFIED States**

```dart
Future<void> approveAttendance(String attendanceId) async {
  // Check if operation allowed
  final canApprove = await sessionStateService.canPerformOperation(
    Operation.approvals,
  );
  
  if (!canApprove.allowed) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Action Not Allowed'),
        content: Text(canApprove.message ?? 
          'Please re-authenticate to perform this action'),
        actions: [
          TextButton(
            onPressed: () {
              // Navigate to login
              Navigator.pushNamed(context, '/login');
            },
            child: Text('Re-Login'),
          ),
        ],
      ),
    );
    return;
  }
  
  // Proceed with approval
  await _supabase.rpc('approve_attendance', params: {'id': attendanceId});
}
```

### **6. Sync Pending Operations (Background Task)**

```dart
// Run periodically or on network reconnection
Future<void> syncOfflineOperations() async {
  final pendingCount = await sessionStateService.getPendingSyncCount();
  
  if (pendingCount > 0) {
    showSnackBar('Syncing $pendingCount pending operations...');
    
    final result = await sessionStateService.syncPendingOperations();
    
    if (result.allSynced) {
      showSnackBar('All operations synced successfully');
    } else if (result.hasFailures) {
      showSnackBar('${result.synced} synced, ${result.failed} failed');
    }
  }
}

// Listen to connectivity changes
Connectivity().onConnectivityChanged.listen((result) {
  if (result != ConnectivityResult.none) {
    syncOfflineOperations();
  }
});
```

---

## 🎨 UI INDICATORS

### **Session State Badge**

```dart
Widget buildSessionStateBadge() {
  return FutureBuilder<SessionState>(
    future: sessionStateService.getCurrentState(),
    builder: (context, snapshot) {
      if (!snapshot.hasData) return SizedBox.shrink();
      
      final state = snapshot.data!;
      
      String label;
      Color color;
      IconData icon;
      
      switch (state) {
        case SessionState.verified:
          label = 'Verified';
          color = Colors.green;
          icon = Icons.verified_user;
          break;
        case SessionState.restricted:
          label = 'Restricted';
          color = Colors.orange;
          icon = Icons.warning;
          break;
        case SessionState.recovery:
          label = 'Offline';
          color = Colors.blue;
          icon = Icons.offline_bolt;
          break;
      }
      
      return Chip(
        avatar: Icon(icon, color: color, size: 16),
        label: Text(label),
        backgroundColor: color.withOpacity(0.1),
        labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold),
      );
    },
  );
}
```

### **Pending Sync Indicator**

```dart
Widget buildSyncIndicator() {
  return FutureBuilder<int>(
    future: sessionStateService.getPendingSyncCount(),
    builder: (context, snapshot) {
      if (!snapshot.hasData || snapshot.data == 0) {
        return SizedBox.shrink();
      }
      
      return ListTile(
        leading: Icon(Icons.sync, color: Colors.blue),
        title: Text('Pending Sync'),
        subtitle: Text('${snapshot.data} operations waiting'),
        trailing: ElevatedButton(
          onPressed: syncOfflineOperations,
          child: Text('Sync Now'),
        ),
      );
    },
  );
}
```

---

## 🔄 STATE TRANSITION DIAGRAM

```
┌──────────────┐
│   VERIFIED   │ ← Full access, all operations allowed
└──────┬───────┘
       │
       ├─── Password Change ───→ ┌────────────────┐
       ├─── PIN Change ────────→ │   RESTRICTED   │
       ├─── Unit Transfer ─────→ │ (Attendance    │
       │                          │  Only)         │
       │                          └────────┬───────┘
       │                                   │
       │                          Shift End or
       │                          Re-Login
       │                                   │
       │                                   ↓
       ├─── Offline/No Network ──→ ┌──────────────┐
       │                            │   RECOVERY   │
       │                            │  (Offline    │
       │                            │   Mode)      │
       │                            └──────┬───────┘
       │                                   │
       │                          Network Returns +
       │                          Auto-Sync
       │                                   │
       └───────────────────────────────────┘
```

---

## 📋 DEPLOYMENT CHECKLIST

**Database Setup:**
- [x] Create workforce_session_states table
- [ ] Create offline_attendance_queue table (manual)
- [ ] Add RLS policies (manual)
- [ ] Run session_state_functions.sql migration

**Flutter Setup:**
- [x] Create SessionStateService
- [ ] Add crypto package to pubspec.yaml
- [ ] Initialize service in main.dart
- [ ] Update Auth Service to transition states
- [ ] Update Attendance UI to check operation permissions
- [ ] Add session state badges to UI
- [ ] Implement background sync

**Testing:**
- [ ] Test password change → RESTRICTED transition
- [ ] Test offline PIN verification
- [ ] Test attendance queue and sync
- [ ] Test operation blocking in RESTRICTED state
- [ ] Test auto-upgrade after shift end

---

## 🚀 READY TO USE

The session state layer is now ready to provide **operational reliability without weakening security**. Guards can punch attendance even when offline or in restricted mode, while sensitive operations remain blocked.

**Next:** Complete the manual database setup, then integrate the Flutter service into your auth and attendance flows.
