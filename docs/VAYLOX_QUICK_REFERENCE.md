# 🚀 VAYLOX Quick Reference Card

## 📊 System Architecture

```
┌─────────────────────────────────────────┐
│         Flutter App (Client)            │
├─────────────────────────────────────────┤
│  Polling (8-12 sec intervals)           │
│  ├─ Notifications (8 sec)               │
│  ├─ Guards (12 sec)                     │
│  ├─ Leave Requests (10 sec)             │
│  └─ OT Requests (10 sec)                │
└────────────┬────────────────────────────┘
             │ Delta Sync (updated_at > lastSync)
             ▼
┌─────────────────────────────────────────┐
│         Supabase Database               │
├─────────────────────────────────────────┤
│  RLS Policies (Role-Based)              │
│  ├─ Guards: Own data only               │
│  ├─ Field Officers: Assigned units      │
│  ├─ Admins: Full org                    │
│  └─ Super Admins: All orgs              │
├─────────────────────────────────────────┤
│  Triggers & Functions                   │
│  ├─ Auto-notifications                  │
│  ├─ Attendance creation                 │
│  ├─ Unit stats calculation              │
│  └─ Shortage detection                  │
└─────────────────────────────────────────┘
```

---

## 📋 Quick Commands

### **Watch Notifications (Guard/Any User)**
```dart
final notifications = ref.watch(notificationsPollingProvider(userId));
final unreadCount = ref.watch(unreadNotificationCountProvider(userId));
```

### **Watch Leave Requests**
```dart
// Guard's own requests
final myLeaves = ref.watch(myLeaveRequestsProvider(guardId));

// Field Officer's unit requests
final unitLeaves = ref.watch(unitLeaveRequestsProvider(unitId));

// Admin's org requests
final orgLeaves = ref.watch(orgLeaveRequestsProvider(orgId));
```

### **Watch OT Requests**
```dart
// Guard's own OT
final myOT = ref.watch(myOTRequestsProvider(guardId));

// Field Officer's unit OT
final unitOT = ref.watch(unitOTRequestsProvider(unitId));

// Admin's org OT
final orgOT = ref.watch(orgOTRequestsProvider(orgId));
```

### **Create Leave Request**
```dart
await ref.read(myLeaveRequestsProvider(guardId).notifier)
  .createLeaveRequest(
    guardId: guardId,
    unitId: unitId,
    organizationId: orgId,
    leaveDate: DateTime(2026, 3, 15),
    leaveType: 'CASUAL', // CASUAL, SICK, EMERGENCY, PLANNED
    reason: 'Personal work',
  );
```

### **Approve Leave**
```dart
await ref.read(unitLeaveRequestsProvider(unitId).notifier)
  .approveLeaveRequest(leaveRequestId, reviewedByUserId);
// Auto-creates attendance, triggers notifications
```

### **Reject Leave**
```dart
await ref.read(unitLeaveRequestsProvider(unitId).notifier)
  .rejectLeaveRequest(
    leaveRequestId,
    reviewedByUserId,
    'Reason for rejection',
  );
```

### **Create OT Request**
```dart
await ref.read(myOTRequestsProvider(guardId).notifier)
  .createOTRequest(
    guardId: guardId,
    unitId: unitId,
    organizationId: orgId,
    overtimeDate: DateTime(2026, 3, 15),
    requestedHours: 8.0,
    shift: 'day', // or 'night'
    reason: 'Filling shortage',
  );
```

### **Approve OT**
```dart
await ref.read(unitOTRequestsProvider(unitId).notifier)
  .approveOTRequest(
    otRequestId,
    approvedByUserId,
    150.0, // OT rate per hour
  );
// Auto-creates OT attendance
```

### **Mark Notification as Read**
```dart
await ref.read(notificationsPollingProvider(userId).notifier)
  .markAsRead(notificationId);
```

### **Mark All Notifications as Read**
```dart
await ref.read(notificationsPollingProvider(userId).notifier)
  .markAllAsRead();
```

---

## 🔐 RLS Quick Reference

### **Guards Can:**
- ✅ View own guards record
- ✅ View own leave requests
- ✅ Create own leave requests
- ✅ Cancel own pending leave
- ✅ View own OT requests
- ✅ Create own OT requests
- ✅ Cancel own pending OT
- ✅ View own notifications
- ✅ Mark own notifications as read

### **Field Officers Can:**
- ✅ All guard permissions
- ✅ View leave requests for assigned units
- ✅ Approve/reject leave for assigned units
- ✅ View OT requests for assigned units
- ✅ Approve/reject OT for assigned units
- ✅ View unit stats for assigned units

### **Admins Can:**
- ✅ All field officer permissions
- ✅ View all guards in org
- ✅ View all leave requests in org
- ✅ Approve/reject any leave in org
- ✅ View all OT requests in org
- ✅ Approve/reject any OT in org
- ✅ View all unit stats in org
- ✅ Create notifications for org members

### **Super Admins Can:**
- ✅ All admin permissions
- ✅ Cross-organization access
- ✅ View all data across all orgs

---

## 📊 Database Quick Reference

### **Leave Requests Table**
```sql
CREATE TABLE leave_requests (
  id uuid PRIMARY KEY,
  organization_id uuid NOT NULL,
  guard_id uuid NOT NULL,
  unit_id uuid NOT NULL,
  leave_date date NOT NULL,
  leave_type text, -- CASUAL, SICK, EMERGENCY, PLANNED
  reason text NOT NULL,
  status text DEFAULT 'PENDING', -- PENDING, APPROVED, REJECTED, CANCELLED
  reviewed_by uuid,
  reviewed_at timestamptz,
  rejection_reason text,
  attendance_id uuid,
  created_at timestamptz,
  updated_at timestamptz,
  UNIQUE(guard_id, leave_date)
);
```

### **Overtime Requests Table**
```sql
CREATE TABLE overtime_requests (
  id uuid PRIMARY KEY,
  organization_id uuid NOT NULL,
  guard_id uuid NOT NULL,
  unit_id uuid NOT NULL,
  overtime_date date NOT NULL,
  requested_hours numeric(4,2),
  shift text, -- day, night
  reason text,
  status text DEFAULT 'PENDING', -- PENDING, APPROVED, REJECTED, CANCELLED
  approved_by uuid,
  approved_at timestamptz,
  rejection_reason text,
  attendance_id uuid,
  ot_rate_applied numeric(10,2),
  created_at timestamptz,
  updated_at timestamptz,
  UNIQUE(guard_id, unit_id, overtime_date, shift)
);
```

### **Notifications Table**
```sql
CREATE TABLE notifications (
  id uuid PRIMARY KEY,
  organization_id uuid NOT NULL,
  user_id uuid NOT NULL,
  title text NOT NULL,
  message text NOT NULL,
  type text NOT NULL, -- LEAVE_REQUESTED, LEAVE_APPROVED, etc
  action_url text,
  related_id uuid,
  is_read boolean DEFAULT false,
  read_at timestamptz,
  created_at timestamptz,
  updated_at timestamptz
);
```

### **Unit Daily Stats Table**
```sql
CREATE TABLE unit_daily_stats (
  id uuid PRIMARY KEY,
  organization_id uuid NOT NULL,
  unit_id uuid NOT NULL,
  stat_date date NOT NULL,
  required_guards integer,
  assigned_guards integer,
  present_guards integer,
  on_leave integer,
  ot_guards integer,
  shortage integer GENERATED, -- auto-calculated
  last_calculated_at timestamptz,
  updated_at timestamptz,
  UNIQUE(unit_id, stat_date)
);
```

---

## 🔔 Notification Types

```dart
enum NotificationType {
  LEAVE_REQUESTED,   // → Field Officers
  LEAVE_APPROVED,    // → Guard
  LEAVE_REJECTED,    // → Guard
  OT_REQUESTED,      // → Field Officers
  OT_APPROVED,       // → Guard
  OT_REJECTED,       // → Guard
  UNIT_SHORTAGE,     // → Available Guards
  ATTENDANCE_ALERT,  // → Supervisors
  SYSTEM,            // → All Users
}
```

---

## ⚙️ Configuration Constants

```dart
// Polling Intervals (Adjustable)
static const Duration notificationPollInterval = Duration(seconds: 8);
static const Duration guardsPollInterval = Duration(seconds: 12);
static const Duration leaveRequestsPollInterval = Duration(seconds: 10);
static const Duration overtimeRequestsPollInterval = Duration(seconds: 10);

// Leave Types
const LEAVE_TYPES = ['CASUAL', 'SICK', 'EMERGENCY', 'PLANNED'];

// Request Statuses
const STATUSES = ['PENDING', 'APPROVED', 'REJECTED', 'CANCELLED'];

// Shift Types
const SHIFTS = ['day', 'night'];
```

---

## 🧪 Testing Snippets

### **Test Leave Workflow**
```dart
// 1. Guard creates leave
await createLeaveRequest(...);

// 2. Wait 10 seconds
await Future.delayed(Duration(seconds: 10));

// 3. Field officer should see it
final leaves = ref.read(unitLeaveRequestsProvider(unitId));
assert(leaves.value!.any((l) => l.status == 'PENDING'));

// 4. Approve
await approveLeaveRequest(...);

// 5. Wait 8 seconds
await Future.delayed(Duration(seconds: 8));

// 6. Guard should see notification
final notifs = ref.read(notificationsPollingProvider(userId));
assert(notifs.value!.any((n) => n['type'] == 'LEAVE_APPROVED'));
```

### **Test OT Workflow**
```dart
// 1. Guard creates OT
await createOTRequest(...);

// 2. Wait 10 seconds
await Future.delayed(Duration(seconds: 10));

// 3. Field officer should see it
final otRequests = ref.read(unitOTRequestsProvider(unitId));
assert(otRequests.value!.any((ot) => ot.status == 'PENDING'));

// 4. Approve with rate
await approveOTRequest(requestId, userId, 150.0);

// 5. Verify attendance created
final attendance = await supabase.from('attendance')
  .select()
  .eq('guard_id', guardId)
  .eq('is_ot', true)
  .single();
assert(attendance['ot_hours'] == 8.0);
```

---

## 🐛 Debugging Commands

### **Check Current User Role**
```sql
SELECT get_user_role();
```

### **View User's Organization(s)**
```sql
SELECT o.name, ou.role 
FROM organization_users ou
JOIN organizations o ON ou.organization_id = o.id
WHERE ou.user_id = auth.uid();
```

### **Check Pending Requests**
```sql
-- Leave
SELECT COUNT(*) FROM leave_requests WHERE status = 'PENDING';

-- OT
SELECT COUNT(*) FROM overtime_requests WHERE status = 'PENDING';
```

### **Check Unread Notifications**
```sql
SELECT COUNT(*) FROM notifications 
WHERE user_id = auth.uid() AND is_read = false;
```

### **Manually Trigger Stats Calculation**
```sql
SELECT calculate_unit_daily_stats(
  '<unit_id>'::uuid,
  '2026-03-15'::date
);
```

### **View Recent Notifications**
```sql
SELECT title, message, type, created_at 
FROM notifications
WHERE user_id = auth.uid()
ORDER BY created_at DESC
LIMIT 10;
```

---

## 📈 Performance Metrics

| Operation | Target | Measurement |
|-----------|--------|-------------|
| Notification delivery | < 8 sec | Time from insert to UI |
| Leave request visibility | < 10 sec | Submit to FO sees |
| OT request visibility | < 10 sec | Submit to FO sees |
| Approval notification | < 8 sec | Approve to guard sees |
| Delta sync bandwidth | < 5 KB | Per poll with changes |
| Daily API requests | < 40K | For 120 guards |
| Daily bandwidth | < 100 MB | Total egress |

---

## ✅ Deployment Checklist

- [ ] Migrations applied
- [ ] RLS policies enabled
- [ ] Triggers created
- [ ] Indexes created
- [ ] Flutter dependencies added
- [ ] Providers initialized
- [ ] Polling intervals configured
- [ ] Leave workflow tested
- [ ] OT workflow tested
- [ ] Notifications tested
- [ ] RLS security tested
- [ ] Performance validated

---

## 📚 Key Files

```
lib/
├── data/
│   └── services/
│       └── delta_sync_service.dart ← Core polling engine
└── presentation/
    └── providers/
        └── leave_overtime_providers.dart ← Workflows

docs/
└── VAYLOX_FREE_TIER_SYSTEM.md ← Full guide
```

---

**Version:** 1.0  
**Last Updated:** 2026-02-16  
**Status:** ✅ Production Ready
