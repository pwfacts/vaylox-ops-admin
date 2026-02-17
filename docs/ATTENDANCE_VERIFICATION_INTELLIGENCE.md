# 🎯 Attendance Verification Intelligence Layer

## ✅ IMPLEMENTATION COMPLETE

**Version:** 3.0 (Verification Intelligence)  
**Date:** 2026-02-16  
**Status:** ✅ Production Ready

---

## 🎯 OVERVIEW

Added **attendance verification intelligence layer** that supports offline operations while providing trust scores for payroll verification.

### **Key Features:**
- ✅ Never blocks offline attendance
- ✅ Computes trust scores (0-100) automatically
- ✅ Exposes verification quality to supervisors
- ✅ Never auto-blocks payroll - only flags for review
- ✅ Dispatch treats low trust as "present but unverified"

---

## 📊 FOUR VERIFICATION MODES

### **1. LIVE_VERIFIED** (95-100)
- Immediate network sync
- Real-time verification
- GPS + face verification

### **2. DELAYED_SYNC** (80-90)
- Network slow but available
- Sync delay < 5 minutes
- Background queue

### **3. OFFLINE_LOCAL** (50-70)
- No network
- Cached PIN verification
- Queued for sync

### **4. MANUAL_OVERRIDE** (10-40)
- Supervisor manual entry
- Attendance correction
- Always requires review

---

## 📈 TRUST SCORE CALCULATION

**Base Score:**
```
LIVE_VERIFIED     → 95
DELAYED_SYNC      → 55-90 (based on delay)
OFFLINE_LOCAL     → 60
MANUAL_OVERRIDE   → 25
```

**Deductions:**
- Time drift > 5min: -15 (FLAG: TIME_DRIFT)
- No device fingerprint: -10 (FLAG: NO_DEVICE_ID)
- No GPS: -5

**Bonuses:**
- Face match ≥ 90%: +5
- Face verified: +3
- GPS captured: +2

**Classification:**
- **HIGH_TRUST:** 80-100
- **MEDIUM_TRUST:** 60-79
- **LOW_TRUST:** 40-59
- **VERY_LOW_TRUST:** 0-39

---

## 🗄️ DATABASE

### **New Columns:**
```sql
verification_mode TEXT
device_timestamp TIMESTAMPTZ
server_received_timestamp TIMESTAMPTZ
sync_delay_seconds INTEGER
device_fingerprint TEXT
last_known_location JSONB
time_drift_seconds INTEGER
trust_score INTEGER (0-100)
trust_score_details JSONB
```

### **Auto-Trigger:**
- Computes trust score on INSERT/UPDATE
- Calculates sync delay automatically
- Stores detailed scoring breakdown

### **New View:**
`attendance_with_verification` - Includes trust scores, classifications, and supervisor alerts

---

## 📱 FLUTTER USAGE

### **Punch Attendance:**
```dart
final result = await AttendanceVerificationService().punchAttendance(
  guardId: guardId,
  unitId: unitId,
  shift: 'morning',
  isCheckIn: true,
  gpsLocation: position,
  faceVerified: true,
);

// Automatically handles:
// - Live sync (if online)
// - Delayed queue (if slow)
// - Offline cache (if no network)
```

### **Sync Queued:**
```dart
final syncResult = await attendanceService.syncQueuedAttendance();
// Syncs all queued offline/delayed attendance
```

### **Get Low Trust:**
```dart
final lowTrust = await attendanceService.getLowTrustAttendance(
  organizationId: orgId,
  maxTrustScore: 60,
);
// Returns attendance requiring supervisor review
```

---

## 🔄 DISPATCH ENGINE

**Behavior:**
- All attendance → Guard marked "present"
- Low trust → Additional flag "unverified"
- Never blocks payroll
- Supervisor can review and approve

---

## ✅ FILES CREATED

- ✅ `supabase/migrations/attendance_verification_intelligence.sql`
- ✅ `lib/core/services/attendance_verification_service.dart`
- ✅ `docs/ATTENDANCE_VERIFICATION_INTELLIGENCE.md`

---

## 🚀 DEPLOYMENT

1. Run SQL migration
2. Add `geolocator` package
3. Integrate `AttendanceVerificationService`
4. Add trust score badges to UI
5. Create supervisor review screen

**Status:** Ready for integration
