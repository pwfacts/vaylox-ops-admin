# 🛡️ Attendance Verification Enforcement Layer

## ✅ IMPLEMENTATION COMPLETE

**Version:** 4.0 (Accountability Enforcement)  
**Date:** 2026-02-17  
**Status:** ✅ Production Ready

---

## 🎯 SYSTEM GOAL

**Force accountability, not prevent work.**

- ✅ **Never blocks** attendance creation
- ✅ **Never blocks** guard operations
- ✅ **Blocks payroll closure** if unresolved tasks exist
- ✅ **Forces supervisors** to review low-trust attendance
- ✅ **Dispatch engine ignores** verification tasks
- ✅ **Attendance remains valid** operationally

---

## 📋 VERIFICATION TASK LIFECYCLE

```
LOW TRUST ATTENDANCE CREATED
         ↓
AUTO-CREATE VERIFICATION TASK
         ↓
├─ Trust < 40 → ADMIN Required
└─ Trust < 60 → SUPERVISOR Required
         ↓
    PENDING STATUS
         ↓
SUPERVISOR/ADMIN REVIEWS
         ↓
├─ VERIFIED   → Attendance correct
├─ JUSTIFIED  → Low trust but valid reason
└─ REJECTED   → Attendance invalid
         ↓
    TASK RESOLVED
         ↓
PAYROLL CAN BE CLOSED
```

---

## 🗄️ DATABASE SCHEMA

### **Table: `attendance_verification_tasks`**

```sql
CREATE TABLE attendance_verification_tasks (
  id UUID PRIMARY KEY,
  attendance_id UUID NOT NULL UNIQUE,
  organization_id UUID NOT NULL,
  
  -- Task requirements
  required_role TEXT CHECK (required_role IN ('SUPERVISOR', 'ADMIN')),
  reason_code TEXT CHECK (reason_code IN (
    'LOW_TRUST', 'VERY_LOW_TRUST', 'TIME_DRIFT', 'OFFLINE_EXCESS'
  )),
  
  -- Status
  status TEXT DEFAULT 'PENDING' CHECK (status IN (
    'PENDING', 'VERIFIED', 'JUSTIFIED', 'REJECTED'
  )),
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  resolved_at TIMESTAMPTZ,
  resolved_by UUID,
  resolution_note TEXT,
  
  -- Metadata
  trust_score INTEGER,
  verification_flags TEXT[]
);
```

---

## 🤖 AUTOMATIC TASK CREATION

### **Trigger:** `trigger_auto_create_verification_task`

**Runs When:**
- Attendance INSERT with `trust_score < 60`
- Attendance UPDATE changes `trust_score` to < 60

**Rules:**

| Trust Score | Required Role | Reason Code |
|-------------|---------------|-------------|
| < 40 | ADMIN | VERY_LOW_TRUST |
| 40-59 | SUPERVISOR | LOW_TRUST |
| TIME_DRIFT flag | SUPERVISOR | TIME_DRIFT |
| OFFLINE_PUNCH flag | SUPERVISOR | OFFLINE_EXCESS |

**Example:**
```sql
-- Attendance with trust_score = 35
INSERT INTO attendance (..., trust_score = 35);

-- Automatic task created:
-- required_role: 'ADMIN'
-- reason_code: 'VERY_LOW_TRUST'
-- status: 'PENDING'
```

---

## 🔄 TASK RESOLUTION

### **Function:** `resolve_verification_task()`

**Parameters:**
- `p_task_id` - Task UUID
- `p_action` - 'VERIFIED', 'JUSTIFIED', or 'REJECTED'
- `p_note` - Resolution explanation
- `p_resolved_by` - User UUID

**Actions:**

**VERIFIED:**
- Attendance is correct despite low trust
- Example: "Guard was in remote area with poor network"

**JUSTIFIED:**
- Low trust but valid business reason
- Example: "Emergency shift, guard used supervisor's phone"

**REJECTED:**
- Attendance is invalid
- Example: "Time stamps don't match shift schedule"

**Example:**
```sql
SELECT resolve_verification_task(
  'task-uuid',
  'VERIFIED',
  'Confirmed with site supervisor - guard was at remote location',
  'user-uuid'
);
```

**Result:**
```json
{
  "success": true,
  "task_id": "task-uuid",
  "action": "VERIFIED",
  "attendance_id": "attendance-uuid"
}
```

---

## 📊 DASHBOARD SUMMARIES

### **Function:** `get_pending_verification_summary()`

**Parameters:**
- `p_org_id` - Organization UUID
- `p_period_start` - Optional start date
- `p_period_end` - Optional end date

**Returns:**
```json
{
  "pending_reviews": 12,
  "critical_unverified": 3,
  "aging_tasks": 5,
  "by_reason": {
    "LOW_TRUST": 7,
    "VERY_LOW_TRUST": 3,
    "TIME_DRIFT": 2
  },
  "period_start": "2026-02-01",
  "period_end": "2026-02-28"
}
```

**Dashboard Counters:**
- **pending_reviews** - Total pending tasks
- **critical_unverified** - Tasks requiring ADMIN (trust < 40)
- **aging_tasks** - Tasks pending > 3 days

---

## 🚫 PAYROLL PERIOD CLOSURE

### **Function:** `can_close_payroll_period()`

**Blocks closure if unresolved tasks exist in period.**

**Parameters:**
- `p_org_id` - Organization UUID
- `p_period_start` - Period start date
- `p_period_end` - Period end date

**Example:**
```sql
SELECT can_close_payroll_period(
  'org-uuid',
  '2026-02-01',
  '2026-02-28'
);
```

**Result (CAN CLOSE):**
```json
{
  "can_close": true,
  "unresolved_count": 0,
  "critical_count": 0,
  "unresolved_tasks": [],
  "message": "Period can be closed"
}
```

**Result (BLOCKED):**
```json
{
  "can_close": false,
  "unresolved_count": 5,
  "critical_count": 2,
  "unresolved_tasks": [
    {
      "task_id": "task-1",
      "attendance_id": "att-1",
      "guard_name": "John Doe",
      "attendance_date": "2026-02-15",
      "trust_score": 35,
      "reason_code": "VERY_LOW_TRUST",
      "required_role": "ADMIN",
      "days_pending": 7
    }
    // ... more tasks
  ],
  "message": "2 critical tasks require admin review"
}
```

---

## 📱 FLUTTER INTEGRATION

### **1. Get Pending Tasks**

```dart
final enforcementService = VerificationEnforcementService();

// Get all pending tasks
final tasks = await enforcementService.getPendingTasks(
  organizationId: orgId,
  requiredRole: 'SUPERVISOR', // Optional filter
  limit: 50,
);

// Display in UI
for (final task in tasks) {
  ListTile(
    leading: CircleAvatar(
      backgroundColor: task.urgencyLevel == TaskUrgency.critical 
          ? Colors.red 
          : Colors.orange,
      child: Text('${task.trustScore}'),
    ),
    title: Text(task.guardName),
    subtitle: Text(
      '${task.attendanceDate} - ${task.reasonCode}\n'
      '${task.daysPending} days pending'
    ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(Icons.check, color: Colors.green),
          onPressed: () => _resolveTask(task.id, TaskAction.verify),
        ),
        IconButton(
          icon: Icon(Icons.close, color: Colors.red),
          onPressed: () => _resolveTask(task.id, TaskAction.reject),
        ),
      ],
    ),
  );
}
```

---

### **2. Resolve Task**

```dart
Future<void> _resolveTask(String taskId, TaskAction action) async {
  // Show dialog for note
  final note = await showDialog<String>(
    context: context,
    builder: (_) => NoteDialog(action: action),
  );
  
  if (note == null) return;
  
  // Resolve task
  final result = await enforcementService.resolveTask(
    taskId: taskId,
    action: action,
    note: note,
  );
  
  if (result.success) {
    showSnackBar('Task resolved successfully');
    // Refresh task list
  } else {
    showSnackBar('Error: ${result.error}');
  }
}
```

---

### **3. Dashboard Summary**

```dart
// Get summary for current month
final summary = await enforcementService.getSummary(
  organizationId: orgId,
  periodStart: DateTime(2026, 2, 1),
  periodEnd: DateTime(2026, 2, 28),
);

// Display summary cards
Row(
  children: [
    SummaryCard(
      title: 'Pending Reviews',
      value: summary.pendingReviews,
      color: Colors.orange,
      icon: Icons.pending_actions,
    ),
    SummaryCard(
      title: 'Critical',
      value: summary.criticalUnverified,
      color: Colors.red,
      icon: Icons.warning,
    ),
    SummaryCard(
      title: 'Aging',
      value: summary.agingTasks,
      color: Colors.blue,
      icon: Icons.schedule,
    ),
  ],
);
```

---

### **4. Check Period Closure**

```dart
// Before closing payroll period
final check = await enforcementService.canClosePeriod(
  organizationId: orgId,
  periodStart: DateTime(2026, 2, 1),
  periodEnd: DateTime(2026, 2, 28),
);

if (check.canClose) {
  // Proceed with closure
  await closePayrollPeriod();
} else {
  // Show unresolved tasks
  showDialog(
    context: context,
    builder: (_) => AlertDialog(
      title: Text('Cannot Close Period'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(check.message),
          SizedBox(height: 16),
          Text('${check.unresolvedCount} unresolved tasks:'),
          ...check.unresolvedTasks.map((task) => 
            ListTile(
              title: Text(task['guard_name']),
              subtitle: Text('${task['attendance_date']} - Trust: ${task['trust_score']}'),
              trailing: Text('${task['days_pending']} days'),
            )
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Review Tasks'),
        ),
      ],
    ),
  );
}
```

---

### **5. Bulk Resolution**

```dart
// Select multiple tasks
final selectedTaskIds = [...]; // From UI selection

// Bulk verify
final result = await enforcementService.bulkResolveTasks(
  taskIds: selectedTaskIds,
  action: TaskAction.verify,
  note: 'Batch verification - all guards confirmed present by site manager',
);

showSnackBar(
  '${result.succeeded} verified, ${result.failed} failed'
);
```

---

### **6. Tasks by Urgency**

```dart
// Get tasks grouped by urgency
final tasksByUrgency = await enforcementService.getTasksByUrgency(
  organizationId: orgId,
);

// Display in tabs
TabBarView(
  children: [
    buildTaskList(tasksByUrgency[TaskUrgency.critical]!), // Red
    buildTaskList(tasksByUrgency[TaskUrgency.warning]!),  // Orange
    buildTaskList(tasksByUrgency[TaskUrgency.normal]!),   // Blue
  ],
);
```

---

## 🎨 UI COMPONENTS

### **Task Urgency Badge**

```dart
Widget buildUrgencyBadge(TaskUrgency urgency) {
  Color color;
  IconData icon;
  String label;
  
  switch (urgency) {
    case TaskUrgency.critical:
      color = Colors.red;
      icon = Icons.error;
      label = 'CRITICAL';
      break;
    case TaskUrgency.warning:
      color = Colors.orange;
      icon = Icons.warning;
      label = 'WARNING';
      break;
    case TaskUrgency.normal:
      color = Colors.blue;
      icon = Icons.info;
      label = 'NORMAL';
      break;
  }
  
  return Chip(
    avatar: Icon(icon, color: color, size: 16),
    label: Text(label),
    backgroundColor: color.withOpacity(0.1),
    labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold),
  );
}
```

### **Reason Code Label**

```dart
String getReasonLabel(String reasonCode) {
  switch (reasonCode) {
    case 'LOW_TRUST':
      return 'Low Trust Score';
    case 'VERY_LOW_TRUST':
      return 'Very Low Trust';
    case 'TIME_DRIFT':
      return 'Time Drift Detected';
    case 'OFFLINE_EXCESS':
      return 'Excessive Offline Usage';
    default:
      return reasonCode;
  }
}
```

---

## 🔄 DISPATCH ENGINE COMPATIBILITY

**Behavior:**
- ✅ Dispatch engine **IGNORES** verification tasks
- ✅ All attendance (even with pending tasks) → Guard marked "present"
- ✅ Attendance **remains valid operationally**
- ✅ Tasks only affect **payroll closure**

**Example:**
```sql
-- Dispatch query (unchanged)
SELECT guard_id, check_in_time
FROM attendance
WHERE attendance_date = CURRENT_DATE
  AND unit_id = 'unit-uuid';

-- Returns ALL attendance, regardless of verification task status
-- Guards with pending tasks are still "present" for dispatch
```

---

## ✅ WHAT WAS NOT CHANGED

**Business Logic (UNTOUCHED):**
- ❌ Attendance creation - Not blocked
- ❌ Guard operations - Not blocked
- ❌ Dispatch engine - Not modified
- ❌ Attendance table structure - Only added verification tasks table
- ❌ Existing workflows - Unchanged

**Only Added:** Enforcement layer for payroll closure accountability

---

## 📊 ANALYTICS

### **Resolution Statistics**

```dart
final stats = await enforcementService.getResolutionStats(
  organizationId: orgId,
  fromDate: DateTime(2026, 2, 1),
);

print('Total: ${stats.total}');
print('Verified: ${stats.verified}');
print('Justified: ${stats.justified}');
print('Rejected: ${stats.rejected}');
print('Pending: ${stats.pending}');
print('Resolution Rate: ${stats.resolutionRate}%');
```

### **Average Resolution Time**

```dart
final avgTime = await enforcementService.getAverageResolutionTime(
  organizationId: orgId,
  fromDate: DateTime.now().subtract(Duration(days: 30)),
);

if (avgTime != null) {
  print('Average resolution: ${avgTime.inHours} hours');
}
```

---

## 📋 DEPLOYMENT CHECKLIST

**Database:**
- [ ] Run `attendance_verification_enforcement.sql` migration
- [ ] Verify `attendance_verification_tasks` table created
- [ ] Test trigger with low-trust attendance
- [ ] Verify view: `verification_tasks_with_details`

**Flutter:**
- [ ] Create `VerificationEnforcementService`
- [ ] Add supervisor review screen
- [ ] Add dashboard summary widgets
- [ ] Implement payroll closure check
- [ ] Add task resolution dialog

**Testing:**
- [ ] Create low-trust attendance → Verify task auto-created
- [ ] Resolve task → Verify status updated
- [ ] Try closing period with pending tasks → Verify blocked
- [ ] Resolve all tasks → Verify period can close
- [ ] Test bulk resolution

---

## 📂 FILES CREATED

- ✅ `supabase/migrations/attendance_verification_enforcement.sql`
- ✅ `lib/core/services/verification_enforcement_service.dart`
- ✅ `docs/VERIFICATION_ENFORCEMENT_LAYER.md`

---

**Your attendance system now enforces accountability without blocking operations!** 🛡️

Guards can work uninterrupted, but supervisors must review low-trust attendance before payroll can be closed - forcing accountability where it matters.
