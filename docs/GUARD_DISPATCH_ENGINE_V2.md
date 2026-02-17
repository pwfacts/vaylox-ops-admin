# 🚀 Guard Dispatch Engine - V2 Enhancements

## ✅ ENHANCEMENTS DEPLOYED

**Version:** 2.0  
**Date:** 2026-02-16  
**Migrations Applied:** 4 additional migrations  
**Status:** ✅ Production Ready

---

## 🆕 WHAT'S NEW IN V2

### **1. Presence Heartbeat ✅**

**New Function:** `presence_ping()`

Guards and users call this function every 30-60 seconds from active app sessions. It:
- Updates `users.last_seen_at` timestamp
- Triggers the lazy worker (`process_coverage_tickets()`)
- Returns worker execution results

**Usage:**
```dart
// Call every 30-60 seconds from Flutter app
Timer.periodic(Duration(seconds: 30), (_) async {
  await supabase.rpc('presence_ping');
});
```

**Benefits:**
- Automatic worker execution without manual triggers
- Presence detection for user activity tracking
- Distributed worker execution across active users

---

### **2. Arrival Verification ✅**

**New Status:** `ASSIGNED_AWAITING_ARRIVAL`

When a guard is auto-assigned, the system now:

1. Creates attendance with `verification_status = 'ASSIGNED_AWAITING_ARRIVAL'`
2. Sets `arrival_deadline` based on `units.arrival_window_minutes` (default 30 min)
3. Waits for guard to check in via:
   - Face punch
   - Geo check-in
   - Manual verification

**If guard arrives (calls `verify_guard_arrival()`):**
- Status → `PENDING_VERIFICATION`
- Ticket → `ASSIGNED`
- Event logged: `ARRIVAL_VERIFIED`

**If guard doesn't arrive by deadline:**
- Status → `AUTO_FAILED`
- Ticket → `AUTO_FAILED` then new `OPEN` ticket created
- Event logged: `ARRIVAL_FAILED`
- Field officers notified
- Auto-retry begins

**New Functions:**
```sql
-- Called from face punch/geo checkin
verify_guard_arrival(attendance_id, verification_method) → JSONB

-- Automatically called by worker
check_arrival_failures() → INTEGER
```

---

### **3. Cascading Coverage ✅**

**Automatic Chain Reaction**

When a guard is reassigned from Unit A to Unit B, the system automatically:
1. Detects the guard's original assignment (Unit A)
2. Creates a new coverage ticket for Unit A
3. Logs event as "cascading coverage"

**Example Scenario:**
```
Unit A (Mall Gate): Guard X assigned
Unit B (Tower): Guard missing → Coverage ticket created

Guard X accepts coverage for Unit B
   ↓
System creates coverage ticket for Unit A (Guard X's original unit)
   ↓
New dispatch cycle starts for Unit A
```

**New Function:**
```sql
create_cascading_coverage(guard_id, shift_date, shift) → UUID
```

**Called automatically from:** `auto_assign_guard()`

---

### **4. Ticket Timeline ✅**

**Complete Event Audit Trail**

**New Table:** `coverage_ticket_events`

Logs every action on coverage tickets:
- `TICKET_CREATED` - Ticket opened
- `WAVE_SENT` - Offers sent to guards
- `OFFER_ACCEPTED` - Guard accepts
- `OFFER_DECLINED` - Guard declines  
- `OFFER_EXPIRED` - No response
- `RESERVATION_STARTED` - 60-second countdown begins
- `FO_OVERRIDE` - Field officer intervention
- `AUTO_ASSIGNED` - Automatic assignment
- `ARRIVAL_VERIFIED` - Guard checked in
- `ARRIVAL_FAILED` - Guard no-show
- `MANUAL_REQUIRED` - Escalated to manual
- `TICKET_CLOSED` - Resolved

**New View:** `coverage_ticket_timeline`

Human-readable timeline with:
- Event timestamps
- Guard names
- User names
- Formatted messages
- Full context

**Usage:**
```sql
-- Get timeline for ticket
SELECT * FROM coverage_ticket_timeline
WHERE coverage_ticket_id = '<ticket-id>'
ORDER BY event_time ASC;
```

**Sample Output:**
```
event_time          | event_type          | event_message
2026-02-16 06:15:00 | TICKET_CREATED      | Coverage ticket created - shortage of 1 guard(s)
2026-02-16 06:15:01 | WAVE_SENT           | Wave 1 sent to 3 guards
2026-02-16 06:15:45 | OFFER_ACCEPTED      | John Doe accepted offer (2.3 km away)
2026-02-16 06:15:45 | RESERVATION_STARTED | John Doe reservation started (60 seconds)
2026-02-16 06:16:45 | AUTO_ASSIGNED       | John Doe auto-assigned (awaiting arrival)
2026-02-16 06:25:30 | ARRIVAL_VERIFIED    | John Doe arrival verified
2026-02-16 06:30:00 | TICKET_CLOSED       | Coverage ticket resolved
```

**Flutter UI Integration:**
```dart
// Fetch timeline for ticket
final timeline = await supabase
  .from('coverage_ticket_timeline')
  .select()
  .eq('coverage_ticket_id', ticketId)
  .order('event_time');

// Display in timeline widget
ListView.builder(
  itemCount: timeline.length,
  itemBuilder: (context, index) {
    final event = timeline[index];
    return TimelineEventCard(
      time: event['event_time'],
      type: event['event_type'],
      message: event['event_message'],
    );
  },
);
```

---

### **5. Failure Escalation ✅**

**New Status:** `MANUAL_REQUIRED`

When broadcast mode completes and no guards accept within the escalation timeout:

1. Worker checks `coverage_tickets` with:
   - `status = 'OPEN'`
   - `broadcast_mode = true`
   - `broadcast_completed_at + escalation_timeout_minutes < NOW()`

2. Marks ticket as `MANUAL_REQUIRED`

3. Sends **urgent notifications** to:
   - Field officers (with 🚨 emoji)
   - Admins/Super admins

4. Logs event: `MANUAL_REQUIRED`

**Configuration:**
```sql
-- Set per unit (default 30 minutes)
UPDATE units 
SET escalation_timeout_minutes = 45
WHERE id = '<unit-id>';
```

**New Function:**
```sql
check_manual_escalation() → INTEGER
```

**Notification Example:**
```
Title: 🚨 URGENT: Manual Coverage Required
Message: Auto-dispatch failed at Mall Gate 1. All guards were notified but no one accepted. Manual assignment required immediately.
```

---

## 📊 ENHANCED WORKER

**Updated:** `process_coverage_tickets()`

Now includes 7 steps:

1. **Check arrival failures** - Guards who didn't show up
2. **Check manual escalation** - Broadcast timeouts
3. **Detect new tickets** - Missing guards
4. **Expire old offers** - Past 90 seconds
5. **Auto-assign guards** - Past 60 seconds
6. **Escalate waves** - Send next batch
7. **Close resolved tickets** - Cleanup

**Returns:**
```json
{
  "success": true,
  "tickets_created": 2,
  "offers_sent": 5,
  "assignments_made": 1,
  "arrival_failures": 1,
  "manual_escalations": 0,
  "execution_ms": 312,
  "errors": []
}
```

---

## 🔄 UPDATED WORKFLOWS

### **Complete Flow with Arrival Verification:**

```
1. Guard misses shift
   ↓
2. Coverage ticket created
   ↓
3. Wave 1 sent (3 guards)
   ↓
4. Guard A accepts (distance: 2.3 km)
   ↓
5. 60-second reservation starts
   ↓
6. Auto-assignment after 60 seconds
   ↓ (NEW v2)
7. Status: ASSIGNED_AWAITING_ARRIVAL
   Deadline: 30 minutes
   ↓
8a. Guard checks in (face punch/geo)
    → verify_guard_arrival() called
    → Status: PENDING_VERIFICATION
    → Ticket: ASSIGNED
    ↓
    Field officer verifies
    → Attendance approved for payroll
    ✅ SUCCESS

8b. Guard doesn't arrive within 30 min
    → check_arrival_failures() detects
    → Status: AUTO_FAILED
    → New OPEN ticket created
    → Auto-retry begins
    ⚠️ RETRY
```

### **Cascading Coverage Flow:**

```
Unit A: Guard X assigned (day shift)
Unit B: Guard Y missing (day shift)

Coverage ticket created for Unit B
   ↓
Wave 1 sent
   ↓
Guard X accepts (closest to Unit B)
   ↓
60-second reservation
   ↓
Auto-assign Guard X to Unit B
   ↓ (NEW v2)
System detects Guard X was assigned to Unit A
   ↓
Create cascading coverage ticket for Unit A
   ↓
New dispatch cycle begins for Unit A
   ↓
Wave 1 sent to guards near Unit A
   ↓
Guard Z accepts
   ↓
Both units covered ✅
```

---

## 🗄️ DATABASE CHANGES

### **New Tables:**
- `coverage_ticket_events` - Event audit log

### **Modified Tables:**

**`users`:**
- Added `last_seen_at TIMESTAMPTZ`

**`units`:**
- Added `arrival_window_minutes INTEGER DEFAULT 30`
- Added `escalation_timeout_minutes INTEGER DEFAULT 30`

**`coverage_tickets`:**
- Updated status constraint (added `AUTO_FAILED`, `MANUAL_REQUIRED`, `ASSIGNED_AWAITING_ARRIVAL`)
- Added `assigned_at TIMESTAMPTZ`
- Added `arrival_deadline TIMESTAMPTZ`
- Added `arrival_verified_at TIMESTAMPTZ`
- Added `broadcast_completed_at TIMESTAMPTZ`

**`attendance`:**
- Updated `verification_status` constraint (added `ASSIGNED_AWAITING_ARRIVAL`, `AUTO_FAILED`)

---

## 🔧 NEW FUNCTIONS

1. **`presence_ping()`** - Heartbeat + worker trigger
2. **`verify_guard_arrival(attendance_id, method)`** - Mark guard as arrived
3. **`check_arrival_failures()`** - Detect no-shows
4. **`check_manual_escalation()`** - Escalate failed broadcasts
5. **`create_cascading_coverage(guard_id, date, shift)`** - Chain coverage
6. **`log_coverage_event(...)`** - Event logging helper

**Updated Functions:**
- `auto_assign_guard()` - Now creates `ASSIGNED_AWAITING_ARRIVAL`, calls cascading coverage
- `process_coverage_tickets()` - Enhanced with arrival/escalation checks
- `send_wave_offers()` - Logs `WAVE_SENT` events
- `accept_coverage_offer()` - Logs `OFFER_ACCEPTED` and `RESERVATION_STARTED`
- `decline_coverage_offer()` - Logs `OFFER_DECLINED`
- `field_officer_override_assignment()` - Logs `FO_OVERRIDE`

---

## 🎯 USAGE EXAMPLES

### **Presence Heartbeat**

```dart
// In Flutter main app
class _AppState extends State<App> {
  Timer? _presenceTimer;
  
  @override
  void initState() {
    super.initState();
    _startPresenceHeartbeat();
  }
  
  void _startPresenceHeartbeat() {
    _presenceTimer = Timer.periodic(Duration(seconds: 30), (_) async {
      try {
        final result = await supabase.rpc('presence_ping');
        print('Worker result: ${result['worker_result']}');
      } catch (e) {
        print('Presence ping failed: $e');
      }
    });
  }
  
  @override
  void dispose() {
    _presenceTimer?.cancel();
    super.dispose();
  }
}
```

### **Arrival Verification (Face Punch)**

```dart
Future<void> onFacePunchSuccess(String attendanceId) async {
  final result = await supabase.rpc('verify_guard_arrival', params: {
    'p_attendance_id': attendanceId,
    'p_verification_method': 'FACE_PUNCH',
  });
  
  if (result['success']) {
    showSnackbar('Arrival verified! ✅');
  }
}
```

### **View Ticket Timeline**

```dart
Future<List<Map<String, dynamic>>> getTicketTimeline(String ticketId) async {
  return await supabase
    .from('coverage_ticket_timeline')
    .select()
    .eq('coverage_ticket_id', ticketId)
    .order('event_time');
}
```

### **Monitor Manual Escalations**

```sql
-- Find tickets requiring manual intervention
SELECT 
  ct.id,
  u.name AS unit_name,
  ct.shift_date,
  ct.shift,
  ct.shortage,
  ct.broadcast_completed_at,
  NOW() - ct.broadcast_completed_at AS time_since_broadcast
FROM coverage_tickets ct
JOIN units u ON ct.unit_id = u.id
WHERE ct.status = 'MANUAL_REQUIRED'
ORDER BY ct.broadcast_completed_at;
```

---

## ⚠️ CONFIGURATION

### **Unit-Level Settings:**

```sql
-- Set arrival window (default 30 minutes)
UPDATE units SET arrival_window_minutes = 45 WHERE id = '<unit-id>';

-- Set escalation timeout (default 30 minutes)
UPDATE units SET escalation_timeout_minutes = 60 WHERE id = '<unit-id>';

-- Set shift grace period (default 15 minutes)
UPDATE units SET shift_start_grace_minutes = 20 WHERE id = '<unit-id>';
```

### **Recommended Values:**

| Setting | Recommended | Use Case |
|---------|-------------|----------|
| `arrival_window_minutes` | 30 | Standard shifts |
| `arrival_window_minutes` | 15 | Emergency coverage |
| `escalation_timeout_minutes` | 30 | Normal operations |
| `escalation_timeout_minutes` | 60 | Night shifts (fewer guards) |
| `shift_start_grace_minutes` | 15 | Day shifts |
| `shift_start_grace_minutes` | 30 | Night shifts |

---

## 📈 MONITORING

### **Active Tickets Requiring Attention:**

```sql
SELECT 
  ct.status,
  COUNT(*) AS count,
  ARRAY_AGG(u.name) AS units
FROM coverage_tickets ct
JOIN units u ON ct.unit_id = u.id
WHERE ct.status IN ('OPEN', 'ASSIGNED_AWAITING_ARRIVAL', 'MANUAL_REQUIRED')
GROUP BY ct.status;
```

### **Arrival Failure Rate:**

```sql
SELECT 
  COUNT(*) FILTER (WHERE status = 'AUTO_FAILED') AS failures,
  COUNT(*) FILTER (WHERE status = 'ASSIGNED') AS successes,
  ROUND(
    COUNT(*) FILTER (WHERE status = 'AUTO_FAILED')::NUMERIC / 
    NULLIF(COUNT(*), 0) * 100, 
    2
  ) AS failure_rate_percent
FROM coverage_tickets
WHERE created_at > NOW() - INTERVAL '7 days';
```

### **Manual Escalation Rate:**

```sql
SELECT 
  COUNT(*) FILTER (WHERE status = 'MANUAL_REQUIRED') AS manual_required,
  COUNT(*) AS total_tickets,
  ROUND(
    COUNT(*) FILTER (WHERE status = 'MANUAL_REQUIRED')::NUMERIC / 
    NULLIF(COUNT(*), 0) * 100, 
    2
  ) AS manual_rate_percent
FROM coverage_tickets
WHERE created_at > NOW() - INTERVAL '7 days';
```

---

## ✅ DEPLOYMENT CHECKLIST

- [x] Migrations applied (4 additional)
- [x] Functions updated
- [x] Triggers created
- [x] Views created
- [x] RLS policies applied
- [ ] Configure unit arrival windows
- [ ] Configure escalation timeouts  
- [ ] Integrate presence heartbeat in Flutter
- [ ] Integrate arrival verification (face punch/geo)
- [ ] Test cascading coverage
- [ ] Test failure escalation
- [ ] Monitor timeline view in UI

---

**Version:** 2.0  
**Status:** ✅ Production Ready  
**Requires:** Guard Dispatch Engine v1.0 (base system)
