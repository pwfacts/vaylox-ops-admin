# ATTENDANCE EXCEPTION ACCOUNTABILITY

## OBJECTIVE

**Enforce accountability without blocking salary payments.**

Unresolved exceptions accumulate → Escalate ownership → Flag in payroll → Pay anyway with warnings.

---

## ESCALATION LIFECYCLE

```
Exception Created
  ↓
Assigned to SUPERVISOR (0-24h deadline)
  ↓
24h passed → Escalate to FIELD_OFFICER (24-48h deadline)
  ↓
48h passed → Escalate to ADMIN (48-72h deadline)
  ↓
72h passed → Mark as PAYROLL_RISK
  ↓
Payroll generated → Guard PAID but flagged ⚠️
```

---

## SCHEMA CHANGES

### **attendance_exceptions Table:**

**New Columns:**
```sql
assigned_to_user_id UUID          -- Current owner
escalation_level TEXT              -- SUPERVISOR / FIELD_OFFICER / ADMIN / PAYROLL_RISK
due_at TIMESTAMPTZ                 -- Resolution deadline
escalated_at TIMESTAMPTZ           -- When last escalated
risk_flag BOOLEAN                  -- TRUE if >72h unresolved
last_escalation_at TIMESTAMPTZ    -- Last escalation timestamp
```

---

## ESCALATION LEVELS

### **Level 1: SUPERVISOR (0-24h)**

**Trigger:** Exception created

**Assignment:** Site supervisor

**Deadline:** 24 hours

**Action:** Supervisor reviews and resolves

---

### **Level 2: FIELD_OFFICER (24-48h)**

**Trigger:** 24 hours passed, unresolved

**Assignment:** Field officer / Manager

**Deadline:** 24 more hours (48h total)

**Notification:**
```
⚠️ WARNING: Exception Escalated to Field Officer
Exception for John Doe (2026-02-15) escalated after 24h
```

---

### **Level 3: ADMIN (48-72h)**

**Trigger:** 48 hours passed, unresolved

**Assignment:** Admin

**Deadline:** 24 more hours (72h total)

**Notification:**
```
🔴 URGENT: Exception Escalated to Admin
Exception for John Doe (2026-02-15) escalated after 48h
```

---

### **Level 4: PAYROLL_RISK (>72h)**

**Trigger:** 72 hours passed, unresolved

**Assignment:** Admin (stays)

**Risk Flag:** `risk_flag = TRUE`

**Notification:**
```
🚨 CRITICAL: Attendance Exception Past 72h
Exception for John Doe (2026-02-15) unresolved for 75.3 hours - PAYROLL RISK
```

**Payroll Impact:**
- ✅ Guard STILL PAID
- ⚠️ Payslip shows warning
- ⚠️ Payroll summary flagged
- ⚠️ Admin notified

---

## NOTIFICATION EVENTS TABLE

**Purpose:** Internal event log (no external integrations)

```sql
CREATE TABLE notification_events (
  event_type TEXT CHECK (
    'EXCEPTION_CREATED',
    'EXCEPTION_ESCALATED',
    'EXCEPTION_RISK_FLAG',
    'EXCEPTION_RESOLVED',
    'PAYROLL_RISK_SUMMARY'
  ),
  
  recipient_user_id UUID,
  reference_id UUID,
  reference_type TEXT,
  
  title TEXT,
  message TEXT,
  severity TEXT,  -- INFO, WARNING, URGENT, CRITICAL
  
  metadata JSONB,
  read_at TIMESTAMPTZ,
  acknowledged_at TIMESTAMPTZ
);
```

**Event Types:**

1. **EXCEPTION_CREATED**
   - When: New exception logged
   - Severity: WARNING
   - Recipient: Assigned supervisor

2. **EXCEPTION_ESCALATED**
   - When: Escalation level changes
   - Severity: WARNING (24h) / URGENT (48h)
   - Recipient: New assignee

3. **EXCEPTION_RISK_FLAG**
   - When: Exception passes 72h
   - Severity: CRITICAL
   - Recipient: Admin

4. **EXCEPTION_RESOLVED**
   - When: Admin resolves exception
   - Severity: INFO
   - Recipient: Original creator

5. **PAYROLL_RISK_SUMMARY**
   - When: Payroll generated with risk flags
   - Severity: CRITICAL
   - Recipient: Admin who generated payroll

---

## ESCALATION PROCESSOR

**Function:** `process_unresolved_attendance_exceptions()`

**Execution:** Cron job (every hour)

**Logic:**
```sql
FOR each PENDING exception:
  hours_overdue = NOW() - created_at
  
  IF hours_overdue > 72:
    escalation_level = 'PAYROLL_RISK'
    risk_flag = TRUE
    Notify admin (CRITICAL)
  
  ELIF hours_overdue > 48:
    escalation_level = 'ADMIN'
    assigned_to = admin
    Notify admin (URGENT)
  
  ELIF hours_overdue > 24:
    escalation_level = 'FIELD_OFFICER'
    assigned_to = field_officer
    Notify field_officer (WARNING)
```

**Cron Schedule:**
```sql
SELECT cron.schedule(
  'process-attendance-exceptions',
  '0 * * * *',  -- Every hour
  $$SELECT process_unresolved_attendance_exceptions()$$
);
```

---

## PAYROLL BEHAVIOR

### **Payroll Generation:**

**Function:** `generate_payroll_with_risk_check()`

**Logic:**
```sql
1. Generate payroll normally (all resolved + valid attendance)
2. Count risk-flagged exceptions
3. Add warning to result:
   "X guards paid with Y unresolved attendance issues"
4. Send notification to admin
5. Return payroll + risk summary
```

**Example Result:**
```json
{
  "success": true,
  "calculations_created": 45,
  "payroll_risk_warning": true,
  "risk_flagged_exceptions": 3,
  "affected_guards_count": 3,
  "warning_message": "3 guards paid with 3 unresolved attendance issues"
}
```

---

### **Payroll Risk Summary View:**

```sql
SELECT * FROM payroll_risk_summary
WHERE payroll_period_id = 'period-id';
```

**Output:**
```
| period_id | from_date  | to_date    | total_exceptions | pending | risk_flagged | affected_guards |
|-----------|------------|------------|------------------|---------|--------------|-----------------|
| period-1  | 2026-02-26 | 2026-03-25 | 8                | 3       | 2            | 3               |
```

**Breakdown:**
- Total exceptions: 8
- Pending (unresolved): 3
- Risk flagged (>72h): 2
- Affected guards: 3

**Escalation levels:**
- Supervisor level: 1
- Field officer level: 0
- Admin level: 1
- Payroll risk level: 2

---

## PAYSLIP WARNINGS

**Function:** `get_payslip_with_warnings(calculation_id)`

**Returns:**
```json
{
  "calculation_id": "uuid",
  "guard_id": "uuid",
  "net_pay": 16255.44,
  "has_warnings": true,
  "warning_message": "This payslip includes attendance with unresolved exceptions. Contact admin for details.",
  "exceptions": [
    {
      "type": "PERIOD_FINALIZED",
      "message": "Period is ATTENDANCE_FINALIZED for 2026-02-15",
      "date": "2026-02-15",
      "level": "PAYROLL_RISK"
    }
  ]
}
```

**Payslip Display:**
```
═══════════════════════════════════════
NET PAY: ₹16,255.44
═══════════════════════════════════════

⚠️ WARNING ⚠️
This payslip includes attendance with unresolved exceptions.
Contact admin for details.

Exception Details:
- Type: PERIOD_FINALIZED
- Date: 2026-02-15
- Level: PAYROLL_RISK
═══════════════════════════════════════
```

---

## OPERATIONAL SCENARIOS

### **Scenario 1: Normal Resolution**

```
Day 1, 10:00 AM: Exception created
  → Assigned to Supervisor
  → Due: Day 2, 10:00 AM

Day 1, 2:00 PM: Supervisor resolves
  → Status: RESOLVED
  → No escalation needed ✅
```

---

### **Scenario 2: Escalation to Field Officer**

```
Day 1, 10:00 AM: Exception created
  → Assigned to Supervisor
  → Due: Day 2, 10:00 AM

Day 2, 11:00 AM: Cron runs
  → 25 hours passed
  → Escalate to Field Officer
  → Due: Day 3, 11:00 AM
  → Notification sent ⚠️

Day 2, 3:00 PM: Field Officer resolves
  → Status: RESOLVED
  → No further escalation ✅
```

---

### **Scenario 3: Payroll Risk**

```
Day 1, 10:00 AM: Exception created
  → Assigned to Supervisor

Day 2, 11:00 AM: Escalated to Field Officer
Day 3, 12:00 PM: Escalated to Admin
Day 4, 11:00 AM: Cron runs
  → 73 hours passed
  → Level: PAYROLL_RISK
  → risk_flag = TRUE
  → Critical notification 🚨

Day 5: Payroll generated
  → Guard PAID ✅
  → Payslip shows warning ⚠️
  → Admin sees: "1 guard paid with unresolved issues"
  → Exception still pending

Day 6: Admin finally resolves
  → Status: RESOLVED
  → risk_flag cleared
```

---

### **Scenario 4: Multiple Guards, Multiple Risks**

```
Payroll Period: Feb 26 - Mar 25

Exceptions:
- Guard A: 1 exception (PAYROLL_RISK, 80h old)
- Guard B: 2 exceptions (ADMIN, 50h old)
- Guard C: 1 exception (PAYROLL_RISK, 75h old)
- Guards D-Z: No exceptions

Payroll Generation:
  → All 26 guards PAID ✅
  → Summary: "3 guards paid with 4 unresolved attendance issues"
  → Report:
    - Affected guards: 3
    - Risk flagged: 2
    - Admin level: 2
    - Payroll risk level: 2

Admin Dashboard:
  🚨 PAYROLL RISK: 2 exceptions over 72h
  ⚠️ ADMIN LEVEL: 2 exceptions between 48-72h
  
  Review Required:
  - Guard A: 1 exception (80h old) - CRITICAL
  - Guard B: 2 exceptions (50h old) - URGENT
  - Guard C: 1 exception (75h old) - CRITICAL
```

---

## ADMIN DASHBOARD QUERIES

### **Pending Exceptions by Level:**
```sql
SELECT 
  escalation_level,
  COUNT(*) AS count,
  COUNT(*) FILTER (WHERE risk_flag = true) AS risk_flagged
FROM attendance_exceptions
WHERE resolution_status = 'PENDING'
GROUP BY escalation_level
ORDER BY 
  CASE escalation_level
    WHEN 'PAYROLL_RISK' THEN 1
    WHEN 'ADMIN' THEN 2
    WHEN 'FIELD_OFFICER' THEN 3
    WHEN 'SUPERVISOR' THEN 4
  END;
```

**Output:**
```
| escalation_level | count | risk_flagged |
|-----------------|-------|--------------|
| PAYROLL_RISK    | 2     | 2            |
| ADMIN           | 3     | 0            |
| FIELD_OFFICER   | 5     | 0            |
| SUPERVISOR      | 12    | 0            |
```

---

### **My Assigned Exceptions:**
```sql
SELECT 
  ae.id,
  g.full_name,
  ae.exception_type,
  ae.attendance_date,
  ae.escalation_level,
  ae.due_at,
  ae.risk_flag,
  EXTRACT(EPOCH FROM (NOW() - ae.created_at)) / 3600 AS hours_old
FROM attendance_exceptions ae
JOIN guards g ON g.id = ae.guard_id
WHERE ae.assigned_to_user_id = 'current-user-id'
  AND ae.resolution_status = 'PENDING'
ORDER BY ae.risk_flag DESC, ae.due_at ASC;
```

---

### **Unread Notifications:**
```sql
SELECT 
  ne.title,
  ne.message,
  ne.severity,
  ne.created_at
FROM notification_events ne
WHERE ne.recipient_user_id = 'current-user-id'
  AND ne.read_at IS NULL
ORDER BY 
  CASE ne.severity
    WHEN 'CRITICAL' THEN 1
    WHEN 'URGENT' THEN 2
    WHEN 'WARNING' THEN 3
    WHEN 'INFO' THEN 4
  END,
  ne.created_at DESC;
```

---

## KEY PRINCIPLES

### **1. Never Block Salary**
```
Risk flag = TRUE
  → Guard still PAID ✅
  → Payslip shows warning
  → Admin accountability enforced
```

### **2. Escalation Enforces Ownership**
```
Supervisor didn't resolve → Field Officer assigned
Field Officer didn't resolve → Admin assigned
Admin didn't resolve → PAYROLL_RISK flagged
```

### **3. Payroll Transparency**
```
Payroll summary shows:
"X guards paid with Y unresolved attendance issues"

Not hidden, but also not blocked.
```

### **4. Notifications Not Emails**
```
All events stored in notification_events table
No external integrations (email, SMS) yet
UI can show notifications in-app
```

---

## CRON JOB SETUP

```sql
-- Run every hour
SELECT cron.schedule(
  'process-attendance-exceptions',
  '0 * * * *',
  $$SELECT process_unresolved_attendance_exceptions()$$
);

-- Check cron status
SELECT * FROM cron.job WHERE jobname = 'process-attendance-exceptions';

-- View cron run history
SELECT * FROM cron.job_run_details 
WHERE jobid = (SELECT jobid FROM cron.job WHERE jobname = 'process-attendance-exceptions')
ORDER BY start_time DESC
LIMIT 10;
```

---

## FILES

- `supabase/migrations/attendance_exception_accountability.sql` - Implementation
- `docs/ATTENDANCE_EXCEPTION_ACCOUNTABILITY.md` - This documentation

---

**ACCOUNTABILITY:** ✅ Enforced via escalation  
**SALARY BLOCKING:** ❌ Never blocked  
**PAYROLL TRANSPARENCY:** ✅ Risk flags visible  
**NOTIFICATIONS:** ✅ Internal event system  
**ESCALATION:** ✅ Automatic (hourly cron)

**Result:** Exceptions don't block operations, but they also can't be ignored. Ownership escalates automatically. Guards always get paid, but unresolved issues are flagged in payroll summary and payslips.
