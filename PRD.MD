# Security Guard Management System
## Product Requirements Document (PRD)

**Version:** 2.1  
**Date:** January 29, 2026  
**Status:** Revised – Implementation Ready  

---

## Document Control

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | Jan 28, 2026 | Product Team | Initial draft |
| 2.0 | Jan 29, 2026 | Product Team | Complete specification |
| 2.1 | Jan 29, 2026 | Product Team | Attendance system restructure, offline mode finalized, image storage migrated to ImageKit, archive strategy secured, cost assumptions revised |

---

## Change Log (v2.1)

### Critical Changes
1. **Attendance System Restructured**
   - Three distinct attendance modes defined
   - Manual fallback mechanism added with mandatory controls
   - Supervisor approval workflow introduced
   
2. **Offline Mode Finalized**
   - Offline punch rules defined
   - Sync strategy documented
   - Duplicate prevention logic added

3. **Image Storage Migration**
   - Migrated from ImgBB to ImageKit.io
   - Private folders with signed URLs
   - Role-based access control

4. **Archive Strategy Secured**
   - Private GitHub repository instead of public releases
   - Encryption added to archive process
   - Access controls defined

5. **Cost Model Revised**
   - Removed "zero cost" claims
   - Realistic cost projections: ₹0–₹2,000/month for up to 500 guards
   - No dependency on unstable "free forever" services

6. **Anti-Fraud Controls Added**
   - System-level controls documented
   - Reporting mechanisms for misuse detection
   - Device binding and GPS validation

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Infrastructure & Technology](#2-infrastructure--technology)
3. [User Roles & Permissions](#3-user-roles--permissions)
4. [Database Architecture](#4-database-architecture)
5. [Core Features](#5-core-features)
6. [Attendance System](#6-attendance-system-critical)
7. [Salary Processing](#7-salary-processing)
8. [Admin Web Panel](#8-admin-web-panel)
9. [Mobile App](#9-mobile-app)
10. [Data Management](#10-data-management)
11. [Security & Compliance](#11-security--compliance)
12. [Implementation Plan](#12-implementation-plan)

---

## 1. Executive Summary

### 1.1 Product Vision

A comprehensive, cloud-based security guard management system that automates the complete lifecycle of security operations—from guard enrollment to salary disbursement—using face recognition, real-time analytics, and intelligent automation with system-enforced validation and audit controls.

### 1.2 Business Objectives

1. **Operational Efficiency:** Reduce salary processing time from 2 days to 2 hours
2. **Cost Reduction:** Eliminate manual paperwork and reduce administrative costs by 75%
3. **Traceability:** Multiple controls reduce misuse and provide complete audit trail
4. **Scalability:** Support growth from 50 to 2000+ guards
5. **Compliance:** Maintain complete audit trail for financial and employment records

### 1.3 Key Deliverables

1. **Flutter Mobile Application** (Android & iOS)
   - Guard self-attendance with face recognition
   - Offline mode support
   - Supervisor attendance marking
   - Field officer management tools

2. **Flutter Web Admin Panel**
   - Dashboard with analytics
   - Guard lifecycle management
   - Salary processing wizard
   - Advanced reporting with pivot tables

3. **Backend Infrastructure** (Supabase)
   - PostgreSQL database with RLS
   - RESTful APIs
   - Real-time subscriptions
   - Serverless edge functions

---

## 2. Infrastructure & Technology

### 2.1 Technology Stack

| Component | Technology | Purpose |
|-----------|------------|---------|
| **Backend** | Supabase | PostgreSQL, Authentication, Realtime, Row Level Security |
| **Frontend** | Flutter 3.x | Cross-platform (Mobile + Web), Native performance |
| **Image Storage** | ImageKit.io | Private media with signed URLs, role-based access |
| **Archive Storage** | Private GitHub Repository | Encrypted archives with access control (GitHub Education Pack) |
| **Face Recognition** | Google ML Kit | On-device processing, privacy-preserving |
| **Charts** | Syncfusion Flutter | Professional charts & pivot tables |
| **Local Storage** | SQLite (via Sqflite) | Offline data storage and sync queue |

### 2.2 Why This Stack?

**Supabase:**
- PostgreSQL power with modern API
- Built-in authentication and RLS
- Real-time subscriptions
- Free tier: 500MB DB, adequate for 500+ guards

**ImageKit.io:**
- Private folders with signed URLs
- Role-based access control
- Image optimization and CDN
- Free tier: 20GB storage, 20GB bandwidth/month

**Private GitHub Repository:**
- GitHub Education Pack provides free private repos
- Version control for archives
- API access for automated uploads
- Encryption support

**Google ML Kit:**
- On-device processing (privacy-preserving)
- No cloud dependency
- Free
- 80-95% accuracy

### 2.3 Cost Model (Revised)

**Operational Cost Projection:**

Designed for low-cost operation on free/low-tier services.

| Service | Free Tier | Expected Usage (500 guards) | Monthly Cost |
|---------|-----------|----------------------------|--------------|
| Supabase | 500MB DB, 1GB storage | 400MB DB, 500MB storage | ₹0 |
| ImageKit | 20GB storage, 20GB bandwidth | 15GB storage, 10GB bandwidth | ₹0 |
| GitHub | Unlimited private repos (Education) | 5GB archives | ₹0 |
| Flutter | Open source | Development | ₹0 |
| ML Kit | On-device, free | Face recognition | ₹0 |
| Domain | N/A | example.com | ₹500/year (~₹40/month) |

**Total Expected Cost: ₹0–₹500/month**

**Scaling Cost (500-2000 guards):**
- Supabase Pro: $25/month (~₹2,000)
- ImageKit Basic: $9/month (~₹750)
- **Total: ₹2,750/month**

**Important Notes:**
- No dependency on unstable "free forever" services
- Costs scale linearly with usage
- Enterprise options available for 2000+ guards
- All services have paid tiers with SLAs

---

## 3. User Roles & Permissions

### 3.1 Role Hierarchy

```
Main Admin (Super User)
    ├── Field Officer (Area Manager)
    │       └── Supervisor (Unit Manager)
    │               └── Security Guard
    └── Accountant (Read-only Financial)
```

### 3.2 Permission Matrix Summary

| Action | Guard | Supervisor | Field Officer | Admin | Accountant |
|--------|-------|------------|---------------|-------|------------|
| Mark own attendance | ✅ | ✅ | ✅ | ✅ | ❌ |
| Mark others (Unit) | ❌ | ✅ | ❌ | ❌ | ❌ |
| Mark others (Area) | ❌ | ❌ | ✅ | ❌ | ❌ |
| **Approve manual attendance** | ❌ | ✅ | ✅ | ✅ | ❌ |
| Add guards | ❌ | ❌ | ✅ | ✅ | ❌ |
| Process salary (Area) | ❌ | ❌ | ✅ | ❌ | ❌ |
| Process salary (All) | ❌ | ❌ | ❌ | ✅ | ❌ |
| View financial reports | ❌ | ❌ | ❌ | ✅ | ✅ |
| System settings | ❌ | ❌ | ❌ | ✅ | ❌ |

---

## 4. Database Architecture

### 4.1 Core Tables

#### **guards** - Master guard data
```sql
CREATE TABLE guards (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  guard_code TEXT NOT NULL UNIQUE,
  
  -- Personal Information
  full_name TEXT NOT NULL,
  phone TEXT NOT NULL UNIQUE,
  emergency_contact TEXT NOT NULL,
  aadhar_number TEXT NOT NULL UNIQUE,
  pan_number TEXT UNIQUE,
  date_of_birth DATE NOT NULL,
  
  -- Documents (ImageKit URLs with signed access)
  aadhar_front_url TEXT,
  aadhar_back_url TEXT,
  pan_card_url TEXT,
  photo_url TEXT,
  police_verification_url TEXT,
  
  -- Employment Details
  assigned_unit_id UUID NOT NULL REFERENCES units(id),
  assigned_unit_code TEXT NOT NULL,
  duty_shift TEXT NOT NULL CHECK (duty_shift IN ('day', 'night', 'both')),
  designation TEXT NOT NULL DEFAULT 'security_guard',
  
  -- Salary Configuration
  basic_salary DECIMAL(10, 2) NOT NULL,
  ot_rate_per_hour DECIMAL(10, 2),
  ot_calculation_method TEXT DEFAULT 'hourly',
  
  -- Bank Details
  bank_name TEXT,
  account_number TEXT,
  ifsc_code TEXT,
  
  -- Face Recognition (numerical vector, non-reversible)
  face_encoding TEXT,
  
  -- Status
  status TEXT NOT NULL DEFAULT 'active',
  
  -- Metadata
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);
```

#### **attendance** - Daily attendance records (REVISED)
```sql
CREATE TABLE attendance (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  guard_id UUID NOT NULL REFERENCES guards(id),
  attendance_date DATE NOT NULL,
  shift TEXT NOT NULL CHECK (shift IN ('day', 'night')),
  
  -- Unit Assignment
  unit_id UUID NOT NULL REFERENCES units(id),
  is_temporary_assignment BOOLEAN DEFAULT false,
  
  -- Timing
  check_in_time TIMESTAMPTZ,
  check_out_time TIMESTAMPTZ,
  
  -- Attendance Method (NEW - CRITICAL)
  attendance_method TEXT NOT NULL CHECK (
    attendance_method IN ('FACE', 'MANUAL_FALLBACK', 'SUPERVISOR')
  ),
  
  -- Face Recognition Data (when method = FACE)
  face_verified BOOLEAN DEFAULT false,
  face_match_score DECIMAL(5, 2), -- 0.00 to 1.00
  
  -- Manual Fallback Data (when method = MANUAL_FALLBACK)
  fallback_reason TEXT CHECK (
    fallback_reason IN ('poor_lighting', 'camera_issue', 'face_mismatch', 'device_issue', 'other')
  ),
  fallback_reason_text TEXT, -- Required if reason = 'other'
  fallback_photo_url TEXT, -- Mandatory for manual fallback
  
  -- Approval Data (for MANUAL_FALLBACK)
  approval_status TEXT DEFAULT 'PENDING_APPROVAL' CHECK (
    approval_status IN ('PENDING_APPROVAL', 'APPROVED', 'REJECTED')
  ),
  approved_by UUID REFERENCES users(id),
  approved_at TIMESTAMPTZ,
  approval_notes TEXT,
  
  -- Location Data
  gps_location POINT,
  gps_accuracy DECIMAL(10, 2), -- meters
  
  -- OT Details
  is_ot BOOLEAN DEFAULT false,
  ot_hours DECIMAL(5, 2) DEFAULT 0,
  ot_rate_applied DECIMAL(10, 2),
  
  -- Offline Sync (NEW)
  synced_from_offline BOOLEAN DEFAULT false,
  device_id TEXT,
  offline_created_at TIMESTAMPTZ,
  
  -- Tracking
  marked_by_user_id UUID REFERENCES users(id),
  
  -- Metadata
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Prevent duplicate attendance
  UNIQUE(guard_id, attendance_date, shift),
  
  -- Validation constraints
  CHECK (
    (attendance_method = 'FACE' AND face_verified = true) OR
    (attendance_method = 'MANUAL_FALLBACK' AND fallback_reason IS NOT NULL AND fallback_photo_url IS NOT NULL) OR
    (attendance_method = 'SUPERVISOR')
  )
);

-- Indexes
CREATE INDEX idx_attendance_approval ON attendance(approval_status) WHERE approval_status = 'PENDING_APPROVAL';
CREATE INDEX idx_attendance_method ON attendance(attendance_method);
CREATE INDEX idx_attendance_guard_date ON attendance(guard_id, attendance_date);
CREATE INDEX idx_attendance_sync ON attendance(synced_from_offline) WHERE synced_from_offline = true;
```

#### **offline_attendance_queue** - Offline sync queue (NEW)
```sql
CREATE TABLE offline_attendance_queue (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  guard_id UUID NOT NULL REFERENCES guards(id),
  attendance_data JSONB NOT NULL, -- Complete attendance record
  device_id TEXT NOT NULL,
  offline_created_at TIMESTAMPTZ NOT NULL,
  sync_status TEXT DEFAULT 'PENDING' CHECK (
    sync_status IN ('PENDING', 'SYNCED', 'FAILED', 'DUPLICATE')
  ),
  sync_error TEXT,
  synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_offline_queue_status ON offline_attendance_queue(sync_status);
```

#### **attendance_audit_log** - Immutable audit trail (NEW)
```sql
CREATE TABLE attendance_audit_log (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  attendance_id UUID NOT NULL REFERENCES attendance(id),
  action TEXT NOT NULL, -- 'CREATED', 'APPROVED', 'REJECTED', 'MODIFIED'
  actor_id UUID NOT NULL REFERENCES users(id),
  actor_role TEXT NOT NULL,
  old_values JSONB,
  new_values JSONB,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_audit_attendance ON attendance_audit_log(attendance_id);
CREATE INDEX idx_audit_created ON attendance_audit_log(created_at DESC);
```

---

## 5. Core Features

### 5.1 Guard Enrollment

**Process Flow:**
1. Personal Details Entry
2. Document Upload (ImageKit with signed URLs)
3. Face Registration (ML Kit - on-device)
4. Employment Details
5. Salary Configuration
6. Bank Details
7. Submit & Generate Guard Code

**Document Storage:**
- All documents uploaded to ImageKit private folders
- Access via signed URLs (expires after configurable time)
- Role-based access control enforced
- No public URLs

**Face Data Handling:**
- Face encodings stored as numerical vectors (JSON)
- Encodings are non-reversible (cannot reconstruct image)
- No face images stored for recognition purposes
- User consent mandatory during enrollment
- Compliance with biometric data regulations

---

## 6. Attendance System (CRITICAL)

### 6.1 Attendance Modes

The system supports three distinct attendance methods, each with specific use cases and controls.

#### **Mode 1: Face Recognition Attendance (Primary)**

**Purpose:** Primary method for guards with smartphones

**Process:**
1. Guard opens mobile app
2. Taps "Mark Attendance"
3. Camera opens (front camera)
4. On-device face detection using Google ML Kit
5. Face landmarks extracted
6. Comparison with stored face encoding
7. Match score calculated (0.00 to 1.00)
8. If match score ≥ threshold (configurable, default 0.80):
   - GPS location captured
   - Attendance auto-approved
   - Record saved with `attendance_method = 'FACE'`
   - `approval_status = 'APPROVED'` (automatic)
   - `face_verified = true`
9. If match score < threshold:
   - Proceed to Mode 2 (Manual Fallback)

**Data Captured:**
- Guard ID
- Date & Shift
- Unit ID
- Check-in timestamp
- Face match score
- GPS location (lat/long)
- GPS accuracy (meters)
- Device ID

**Validation:**
- Unique constraint: One attendance per guard per shift per day
- GPS radius validation (optional, configurable per unit)
- Face match score must meet threshold

---

#### **Mode 2: Manual Fallback Attendance (Conditional)**

**Purpose:** Used ONLY when face recognition fails

**Trigger Conditions:**
- Face match score < threshold
- Face detection failure
- Guard explicitly requests manual mode

**Mandatory Requirements:**

1. **Face Recognition Failure Logged:**
   - System must attempt face recognition first
   - Failure reason recorded

2. **GPS Location Required:**
   - GPS coordinates must be captured
   - No attendance without GPS

3. **Live Photo Required:**
   - Camera must capture live photo (no gallery access)
   - Photo uploaded to ImageKit
   - Photo reviewed during approval

4. **Reason Selection Required:**
   - Guard must select reason from dropdown:
     - Poor lighting
     - Camera issue
     - Face mismatch
     - Device issue
     - Other (requires text explanation)

**System Behavior:**
- Attendance saved with `attendance_method = 'MANUAL_FALLBACK'`
- `approval_status = 'PENDING_APPROVAL'`
- Cannot be auto-approved
- Triggers supervisor approval workflow

**Data Captured:**
- All data from Mode 1 (except face match score)
- Fallback reason
- Fallback reason text (if "other")
- Fallback photo URL
- Device ID

**Anti-Fraud Controls:**
- Photo must be live capture (no gallery)
- Photo timestamp validated (recent)
- GPS coordinates validated (within unit radius)
- Frequency tracking (alerts if guard uses fallback too often)

---

#### **Mode 3: Supervisor Bulk Attendance**

**Purpose:** 
- Guards with feature phones (no smartphone)
- Emergency situations (network down, app issues)
- Site-level attendance marking

**Process:**
1. Supervisor logs into mobile/web app
2. Selects unit, date, shift
3. Views list of guards
4. Marks Present/Absent
5. Optionally adds OT hours
6. Submits

**System Behavior:**
- Attendance saved with `attendance_method = 'SUPERVISOR'`
- `approval_status = 'APPROVED'` (supervisor is authority)
- GPS optional (supervisor's location, not guard's)

**Data Captured:**
- Guard ID
- Date & Shift
- Unit ID
- Supervisor ID
- Check-in timestamp
- OT hours (if any)

**Validation:**
- Supervisor can only mark for their assigned unit
- Field Officer can mark for units in their area
- Admin can mark for any unit

---

### 6.2 Supervisor Approval Workflow

**Approval Required For:**
- All `MANUAL_FALLBACK` attendance records
- Records with `approval_status = 'PENDING_APPROVAL'`

**Approval Interface:**

Supervisor Dashboard shows:
- List of pending approvals
- Guard name, code, date, shift
- Fallback reason
- GPS location (shown on map)
- Captured photo (inline preview)

**Supervisor Actions:**

1. **Review:**
   - View GPS location on map
   - Verify location is within unit radius
   - View captured photo
   - Check fallback reason

2. **Approve:**
   - Click "Approve"
   - Optional: Add approval notes
   - System updates:
     - `approval_status = 'APPROVED'`
     - `approved_by = supervisor_id`
     - `approved_at = current_timestamp`
   - Audit log entry created

3. **Reject:**
   - Click "Reject"
   - Required: Add rejection reason
   - System updates:
     - `approval_status = 'REJECTED'`
     - Attendance treated as absent
     - `approved_by = supervisor_id`
     - `approved_at = current_timestamp`
     - `approval_notes = rejection_reason`
   - Audit log entry created
   - Guard notified (optional)

**Audit Requirements:**
- All approvals/rejections logged in `attendance_audit_log`
- Supervisor ID recorded
- Timestamp recorded
- Notes/reasons recorded
- Immutable log (cannot be deleted/edited)

**Notification Rules:**
- Supervisor receives notification for pending approvals
- Auto-reminder if pending > 24 hours
- Admin receives alert if pending > 48 hours

---

### 6.3 Offline Attendance

**Purpose:** Handle network outages and poor connectivity areas

**Offline Capabilities:**

All three attendance modes support offline operation:

1. **Mode 1 (Face Recognition):**
   - Face detection works offline (ML Kit is on-device)
   - Face matching works offline
   - Data stored in local SQLite database
   - Queued for sync when online

2. **Mode 2 (Manual Fallback):**
   - GPS capture works offline
   - Photo capture works offline
   - Photo stored in local device storage
   - All data queued for sync

3. **Mode 3 (Supervisor Bulk):**
   - Supervisor can mark offline
   - Data stored locally
   - Queued for sync

**Offline Data Storage:**

Local SQLite schema:
```sql
CREATE TABLE offline_attendance (
  local_id INTEGER PRIMARY KEY AUTOINCREMENT,
  guard_id TEXT NOT NULL,
  unit_id TEXT NOT NULL,
  attendance_date TEXT NOT NULL,
  shift TEXT NOT NULL,
  attendance_method TEXT NOT NULL,
  check_in_time TEXT NOT NULL,
  gps_latitude REAL,
  gps_longitude REAL,
  gps_accuracy REAL,
  face_match_score REAL,
  fallback_reason TEXT,
  fallback_reason_text TEXT,
  fallback_photo_path TEXT, -- Local file path
  device_id TEXT NOT NULL,
  created_at TEXT NOT NULL,
  sync_status TEXT DEFAULT 'PENDING',
  sync_attempts INTEGER DEFAULT 0,
  last_sync_error TEXT
);
```

**Sync Process:**

1. **Trigger Sync:**
   - Automatic when network detected
   - Manual: User taps "Sync Now"
   - Background: Every 15 minutes (if network available)

2. **Upload Photos First:**
   - If attendance has photo, upload to ImageKit
   - Get signed URL
   - Update attendance record with URL

3. **Upload Attendance:**
   - For each pending record:
     - Prepare data payload
     - POST to `/api/attendance/sync`
     - Server validates:
       - Unique constraint
       - GPS within radius
       - Required fields present

4. **Handle Conflicts:**
   - **Duplicate:** Already exists for (guard, date, shift)
     - Server returns `DUPLICATE` status
     - Local record marked as synced
     - Warning shown to user
   
   - **Validation Error:**
     - Server returns error details
     - Local record marked as `FAILED`
     - Error shown to user
     - Retry allowed

5. **Update Local Status:**
   - On success: Mark as `SYNCED`
   - On failure: Increment `sync_attempts`
   - If attempts > 3: Flag for manual review

**Server-Side Sync Endpoint:**

```
POST /api/attendance/sync
Headers:
  Authorization: Bearer {token}
Body:
{
  "guard_id": "uuid",
  "unit_id": "uuid",
  "attendance_date": "2026-01-29",
  "shift": "day",
  "attendance_method": "FACE",
  "check_in_time": "2026-01-29T08:05:00Z",
  "gps_location": {"lat": 22.3039, "lng": 70.8022},
  "gps_accuracy": 10.5,
  "face_match_score": 0.92,
  "device_id": "device-123",
  "offline_created_at": "2026-01-29T08:05:00Z",
  "synced_from_offline": true
}

Response (Success):
{
  "status": "success",
  "attendance_id": "uuid",
  "message": "Attendance synced successfully"
}

Response (Duplicate):
{
  "status": "duplicate",
  "message": "Attendance already exists for this guard, date, and shift",
  "existing_attendance_id": "uuid"
}

Response (Error):
{
  "status": "error",
  "message": "GPS location outside unit radius",
  "code": "GPS_VALIDATION_FAILED"
}
```

**Offline Mode UI Indicators:**
- Network status icon (online/offline)
- Pending sync count badge
- Sync progress indicator
- Last successful sync timestamp

---

### 6.4 Anti-Fraud Controls

**System-Level Controls:**

1. **One Attendance Per Guard Per Shift Per Day:**
   - Database unique constraint enforced
   - Duplicate attempts rejected
   - Prevents multiple check-ins

2. **Device Binding (Optional Configuration):**
   - Admin can enable per-guard
   - Guard can only mark from registered device
   - Device ID validated on each attendance
   - Useful for high-security units

3. **GPS Radius Validation (Configurable Per Unit):**
   - Admin sets allowed radius per unit (e.g., 100 meters)
   - Attendance rejected if GPS outside radius
   - Can be disabled for mobile patrol units

4. **Manual Fallback Frequency Tracking:**
   - System tracks fallback usage per guard
   - Threshold configurable (e.g., >30% fallback = alert)
   - Alert sent to Field Officer if threshold exceeded
   - Dashboard shows fallback % by guard

5. **Photo Timestamp Validation:**
   - Manual fallback photos must be recent
   - Validation: Photo timestamp within 5 minutes of attendance time
   - Prevents using old photos

6. **Supervisor Override Tracking:**
   - All supervisor approvals/rejections logged
   - Frequency monitored
   - Alert if supervisor rejects >20% of manual fallbacks
   - Alert if supervisor approves all without review

**Reporting & Alerts:**

1. **Manual Attendance % by Guard:**
   - Shows which guards frequently use manual fallback
   - Red flag if >30% manual

2. **Manual Attendance % by Unit:**
   - Shows which units have high manual fallback rates
   - May indicate poor lighting or equipment issues

3. **Supervisor Override Frequency:**
   - Shows approval/rejection patterns
   - Identifies supervisors who may need training

4. **Red-Flag Reports:**
   - Guards with suspicious patterns
   - Units with unusual behavior
   - Devices with multiple guard usage
   - Attendance outside working hours

**Alert Rules:**

| Condition | Threshold | Action |
|-----------|-----------|--------|
| Guard manual fallback % | >30% in a month | Alert Field Officer |
| Unit manual fallback % | >50% in a week | Alert Admin |
| Supervisor reject rate | >40% | Alert Admin |
| Supervisor approve rate | 100% for >10 records | Alert Admin (possible rubber-stamping) |
| GPS outside radius | Any occurrence | Block attendance + Alert |
| Device shared between guards | Any occurrence | Alert Admin |

---

### 6.5 Attendance Data Model (Complete)

**Table: attendance**

| Field | Type | Purpose | Required | Validation |
|-------|------|---------|----------|------------|
| id | UUID | Primary key | Auto | - |
| guard_id | UUID | FK to guards | Yes | Must exist |
| attendance_date | DATE | Date of attendance | Yes | - |
| shift | TEXT | Day/Night | Yes | IN ('day', 'night') |
| unit_id | UUID | FK to units | Yes | Must exist |
| is_temporary_assignment | BOOLEAN | Temp assignment flag | Yes | Default false |
| check_in_time | TIMESTAMPTZ | Check-in time | Yes | - |
| check_out_time | TIMESTAMPTZ | Check-out time | No | > check_in_time |
| **attendance_method** | TEXT | Method used | Yes | IN ('FACE', 'MANUAL_FALLBACK', 'SUPERVISOR') |
| face_verified | BOOLEAN | Face match success | Conditional | Required if method=FACE |
| face_match_score | DECIMAL(5,2) | Match confidence | Conditional | 0.00-1.00 if method=FACE |
| fallback_reason | TEXT | Reason for manual | Conditional | Required if method=MANUAL_FALLBACK |
| fallback_reason_text | TEXT | Custom reason | Conditional | Required if reason='other' |
| fallback_photo_url | TEXT | Photo URL | Conditional | Required if method=MANUAL_FALLBACK |
| **approval_status** | TEXT | Approval state | Yes | IN ('PENDING_APPROVAL', 'APPROVED', 'REJECTED') |
| approved_by | UUID | Approver user ID | Conditional | Required if approved/rejected |
| approved_at | TIMESTAMPTZ | Approval time | Conditional | Required if approved/rejected |
| approval_notes | TEXT | Approval notes | No | - |
| gps_location | POINT | GPS coordinates | Conditional | Required for FACE & MANUAL_FALLBACK |
| gps_accuracy | DECIMAL(10,2) | GPS accuracy (m) | No | - |
| is_ot | BOOLEAN | OT flag | Yes | Default false |
| ot_hours | DECIMAL(5,2) | OT hours | No | 0-24 |
| ot_rate_applied | DECIMAL(10,2) | OT rate | Conditional | Required if is_ot=true |
| synced_from_offline | BOOLEAN | Offline sync flag | Yes | Default false |
| device_id | TEXT | Device identifier | No | - |
| offline_created_at | TIMESTAMPTZ | Offline creation time | Conditional | Required if synced_from_offline=true |
| marked_by_user_id | UUID | User who marked | No | - |
| created_at | TIMESTAMPTZ | Record creation | Auto | - |
| updated_at | TIMESTAMPTZ | Last update | Auto | - |

---

## 7. Salary Processing

### 7.1 Calculation Logic

**Working Days Calculation:**
```
Working Days = Count DISTINCT attendance_date 
               WHERE approval_status = 'APPROVED'
               AND guard_id = X
               AND attendance_date BETWEEN start_date AND end_date
               
For double shifts: Each shift counts as separate working day
Example: Day shift + Night shift on same date = 2 working days
```

**Salary Formula:**
```
Step 1: Per Day Rate
  = Basic Salary / Total Days in Month

Step 2: Calculated Basic Pay
  = Per Day Rate × Working Days

Step 3: OT Pay
  If ot_calculation_method = 'hourly':
    OT Pay = Sum(ot_hours) × OT Rate Per Hour
  If ot_calculation_method = 'monthly':
    OT Pay = OT Rate Per Hour (fixed monthly amount)

Step 4: Gross Pay
  = Calculated Basic Pay + OT Pay

Step 5: Deductions
  - Canteen (manual)
  - Uniform (manual)
  - Advance (manual)
  - PF = Basic Salary × PF% (if applicable)
  - Penalty (manual)
  - Other deductions (manual)

Step 6: Net Pay
  = Gross Pay - Total Deductions
```

**Example:**
```
Guard: Pritam Kumar (BH001)
Month: January 2026 (31 days)
Basic Salary: ₹12,000
OT Rate: ₹50/hour (hourly method)

Working Days: 25 (approved attendance)
OT Hours: 12

Calculation:
Per Day Rate = 12,000 / 31 = ₹387.10
Calculated Basic = 387.10 × 25 = ₹9,677.42
OT Pay = 12 × 50 = ₹600
Gross Pay = 9,677.42 + 600 = ₹10,277.42

Deductions:
  Canteen: ₹500
  Uniform: ₹200
  Advance: ₹1,000
  PF: 12,000 × 12% = ₹1,440
  Total: ₹3,140

Net Pay = 10,277.42 - 3,140 = ₹7,137.42
```

### 7.2 Salary Processing Workflow

```
1. Select Month & Scope
   - Choose month/year
   - Select: All Units / Specific Area / Specific Unit

2. Validate Attendance Data
   - Check for pending approvals
   - Alert if any MANUAL_FALLBACK records not approved
   - Admin can choose to:
     - Wait for approvals
     - Process excluding pending records
     - Auto-reject pending (mark as absent)

3. Configure Default Deductions
   - Set bulk amounts for:
     - Canteen
     - Uniform
   - These apply to all guards in scope

4. Edit Individual Deductions
   - Table editor for per-guard adjustments
   - Fields: Canteen, Uniform, Advance, PF (Y/N), Penalty, Other

5. Calculate Salaries
   - System processes each guard:
     - Fetch approved attendance
     - Calculate working days
     - Calculate basic & OT
     - Apply deductions
     - Calculate net pay
   - Progress indicator shown

6. Review & Preview
   - Summary statistics
   - Guard-by-guard breakdown
   - Payment mode split (cash/account)
   - Validation warnings (if any)

7. Generate Excel Sheets
   - Sheet 1: Unit-wise Salary Summary
   - Sheet 2: Bank Transfer List

8. Create Ledger Entries
   - Salary payment entries
   - Deduction entries
   - All entries immutable

9. Save Salary Records
   - Save to salary_records table
   - Status: PENDING (until marked paid)

10. Download & Distribute
    - Download Excel files
    - Optional: Email payslips
    - Optional: Print payslips
```

### 7.3 Excel Export Format

**Sheet 1: Salary Summary**

| Guard Code | Name | Unit | Days | OT Hrs | Basic | OT Pay | Gross | Deductions | Net Pay | Mode | Status |
|------------|------|------|------|--------|-------|--------|-------|------------|---------|------|--------|
| BH001 | Pritam K. | BH | 25 | 12 | 9,677.42 | 600.00 | 10,277.42 | 3,140.00 | 7,137.42 | AC | Pending |
| BH002 | Rajesh S. | BH | 28 | 0 | 10,838.71 | 0.00 | 10,838.71 | 2,640.00 | 8,198.71 | Cash | Pending |

**Summary Row:**
- Total Guards: 45
- Total Working Days: 1,170
- Total Gross: ₹4,85,000
- Total Deductions: ₹45,000
- Total Net: ₹4,40,000
- Cash Payments: ₹2,00,000 (20 guards)
- Account Payments: ₹2,40,000 (25 guards)

**Sheet 2: Bank Transfers** (Account mode only)

| Guard Code | Name | Account Number | IFSC Code | Bank Name | Amount | Status |
|------------|------|----------------|-----------|-----------|--------|--------|
| BH001 | Pritam Kumar | 1234567890 | SBIN0001234 | State Bank of India | 7,137.42 | Pending |
| BH004 | Suresh Yadav | 9876543210 | HDFC0000123 | HDFC Bank | 8,500.00 | Pending |

**Note:** Account numbers stored as TEXT to preserve leading zeros

---

## 8. Admin Web Panel

### 8.1 Dashboard

**Key Metrics:**
- Active Guards: 180 (▲ 2% vs last month)
- Attendance Rate: 98.5% (▲ 3%)
- Monthly Billing: ₹5,20,000 (▲ 5%)
- Pending Payments: ₹45,000 (▼ 10%)
- Pending Approvals: 12 (Manual fallback attendance)
- Manual Fallback Rate: 8.5% (↓ target <10%)

**Charts:**
1. Attendance Trend (6 months line chart)
2. Unit Distribution (pie chart)
3. OT Analysis (bar chart by unit)
4. Manual Fallback Trend (line chart)

**Financial Pivot Table:**
- Interactive drill-down
- Group by: Area > Unit > Guard
- Values: Billing, Deductions, Net Pay, Payment Status
- Export to Excel

**Alerts & Notifications:**
- Pending manual attendance approvals (count with link)
- Guards exceeding manual fallback threshold (list)
- Units with low attendance rate (list)
- Salary processing due date reminder

### 8.2 Attendance Management

**Pending Approvals Dashboard:**

View for supervisors/field officers/admin:

| Guard | Date | Shift | Reason | Photo | GPS | Actions |
|-------|------|-------|--------|-------|-----|---------|
| BH001 Pritam K. | Jan 29 | Day | Poor lighting | 🖼️ View | 📍 Map | ✅ Approve / ❌ Reject |
| RJ005 Amit P. | Jan 29 | Night | Camera issue | 🖼️ View | 📍 Map | ✅ Approve / ❌ Reject |

**Bulk Actions:**
- Select multiple
- Approve selected
- Reject selected (requires reason)

**Attendance Reports:**
- Calendar view (monthly)
- List view (detailed)
- Unit summary
- Guard history
- Manual fallback analysis
- Export options (Excel, PDF, CSV)

---

## 9. Mobile App

### 9.1 Guard App

**Home Screen:**
```
┌─────────────────────────────┐
│ 👋 Hello, Pritam            │
│ BH001 • Bhawani Unit        │
│ [Offline Mode] 📶           │ <-- Shows if offline
├─────────────────────────────┤
│ 📅 Wednesday, Jan 29, 2026  │
│ ⏰ 8:05 AM                  │
│                             │
│ Today's Status:             │
│ ✅ Marked (Day Shift)       │
│ Method: Face Recognition    │
│ Time: 8:05 AM               │
│                             │
│ ┌─────────────────────────┐ │
│ │ Mark Attendance (Night) │ │
│ │ [Tap to Scan Face]      │ │
│ └─────────────────────────┘ │
│                             │
│ [📊 Pending Sync: 2]        │ <-- If offline records
│ [🔄 Sync Now]               │
│                             │
│ This Week: 5/7 days         │
│ This Month: 22/28 days      │
│ Manual Fallback: 2 (9%)     │ <-- Self-awareness
│                             │
├─────────────────────────────┤
│ [🏠] [📅] [📊] [👤]         │
└─────────────────────────────┘
```

**Face Scan Screen:**
```
┌─────────────────────────────┐
│ 📸 Face Recognition         │
├─────────────────────────────┤
│ [Camera Preview with Oval]  │
│                             │
│ Status: 🔍 Scanning...      │
│ Match: [██████░░░░] 75%     │
│                             │
│ Tips:                       │
│ • Look straight             │
│ • Ensure good lighting      │
│ • Remove glasses            │
│                             │
│ [Cancel] [Switch to Manual] │
└─────────────────────────────┘
```

**Manual Fallback Screen:**
```
┌─────────────────────────────┐
│ ⚠️ Manual Attendance        │
├─────────────────────────────┤
│ Face recognition failed.    │
│ This requires supervisor    │
│ approval.                   │
│                             │
│ Why did face scan fail?     │
│ ○ Poor lighting             │
│ ○ Camera issue              │
│ ○ Face mismatch             │
│ ○ Device issue              │
│ ● Other                     │
│   [Explain:____________]    │
│                             │
│ 📸 Take Photo (Required)    │
│ [Tap to Capture]            │
│                             │
│ 📍 GPS: Capturing...        │
│ Location: ✓ Verified        │
│                             │
│ ⚠️ Note: This will be      │
│ reviewed by your supervisor │
│                             │
│ [Cancel] [Submit]           │
└─────────────────────────────┘
```

### 9.2 Supervisor App

**Pending Approvals Screen:**
```
┌─────────────────────────────┐
│ ⏳ Pending Approvals (12)  │
├─────────────────────────────┤
│ Filter: [All ▼] [Today ▼]  │
│                             │
│ ┌─────────────────────────┐ │
│ │ BH001 - Pritam Kumar    │ │
│ │ Jan 29, Day Shift       │ │
│ │ Reason: Poor lighting   │ │
│ │                         │ │
│ │ 📍 GPS: View on Map     │ │
│ │ 📸 Photo: View          │ │
│ │                         │ │
│ │ [✅ Approve] [❌ Reject]│ │
│ └─────────────────────────┘ │
│                             │
│ ┌─────────────────────────┐ │
│ │ BH005 - Dinesh Patel    │ │
│ │ Jan 29, Night Shift     │ │
│ │ Reason: Camera issue    │ │
│ │ [✅ Approve] [❌ Reject]│ │
│ └─────────────────────────┘ │
│                             │
│ [Select All] [Bulk Approve] │
├─────────────────────────────┤
│ [🏠] [📋] [📊] [👤]         │
└─────────────────────────────┘
```

**Approval Detail Screen:**
```
┌─────────────────────────────┐
│ ← Review Attendance         │
├─────────────────────────────┤
│ Guard: BH001 Pritam Kumar   │
│ Date: Jan 29, 2026          │
│ Shift: Day                  │
│ Time: 8:05 AM               │
│                             │
│ Reason Selected:            │
│ Poor lighting               │
│                             │
│ Photo Captured:             │
│ ┌─────────────────────────┐ │
│ │                         │ │
│ │   [Guard's Photo]       │ │
│ │   Timestamp: 8:05 AM    │ │
│ │                         │ │
│ └─────────────────────────┘ │
│                             │
│ GPS Location:               │
│ [📍 Map showing location]   │
│ Distance from unit: 45m     │
│ ✓ Within allowed radius     │
│                             │
│ Guard's Fallback History:   │
│ This month: 2/22 (9%)       │
│ Last month: 1/26 (4%)       │
│                             │
│ Decision:                   │
│ ┌─────────────────────────┐ │
│ │ ✅ Approve              │ │
│ │ Location verified       │ │
│ │ Photo clear             │ │
│ │ Reasonable explanation  │ │
│ └─────────────────────────┘ │
│                             │
│ ┌─────────────────────────┐ │
│ │ ❌ Reject               │ │
│ │ Reason: [___________]   │ │
│ └─────────────────────────┘ │
│                             │
│ [Submit Decision]           │
└─────────────────────────────┘
```

---

## 10. Data Management

### 10.1 Image Storage (ImageKit)

**Implementation:**

All images stored in ImageKit with private folders and role-based access.

**Folder Structure:**
```
/guards
  /{guard_id}
    /aadhar_front.jpg
    /aadhar_back.jpg
    /pan.jpg
    /photo.jpg
    /police_verification.pdf

/attendance
  /{year}/{month}
    /fallback_{attendance_id}.jpg
```

**Access Control:**

1. **Upload:**
   - Server generates signed upload URL
   - Client uploads directly to ImageKit
   - Server saves URL in database

2. **View:**
   - Server generates signed view URL (expires in 1 hour)
   - Client displays image
   - URL cannot be reused after expiration

3. **Download:**
   - Admin/Field Officer can download
   - Signed URL with download flag
   - Audit log entry created

**Code Example:**

```dart
class ImageKitService {
  final String publicKey = 'YOUR_PUBLIC_KEY';
  final String privateKey = 'YOUR_PRIVATE_KEY';
  final String urlEndpoint = 'https://ik.imagekit.io/your_id';
  
  Future<String> uploadImage(File file, String folder, String fileName) async {
    // 1. Get signed upload URL from server
    final uploadUrl = await _getSignedUploadUrl(folder, fileName);
    
    // 2. Upload file
    final bytes = await file.readAsBytes();
    final response = await http.post(
      Uri.parse(uploadUrl),
      body: bytes,
      headers: {'Content-Type': 'image/jpeg'},
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      return data['url']; // Private URL
    }
    
    throw Exception('Upload failed');
  }
  
  Future<String> getSignedViewUrl(String filePath) async {
    // Generate signed URL from server
    final response = await supabase.functions.invoke(
      'imagekit-signed-url',
      body: {'file_path': filePath, 'expires_in': 3600}, // 1 hour
    );
    
    return response.data['signed_url'];
  }
}
```

**Server-Side Function (Supabase Edge Function):**

```typescript
// imagekit-signed-url function
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import ImageKit from 'imagekit'

const imagekit = new ImageKit({
  publicKey: Deno.env.get('IMAGEKIT_PUBLIC_KEY'),
  privateKey: Deno.env.get('IMAGEKIT_PRIVATE_KEY'),
  urlEndpoint: Deno.env.get('IMAGEKIT_URL_ENDPOINT')
})

serve(async (req) => {
  const { file_path, expires_in } = await req.json()
  
  // Verify user has permission to access this file
  // ... RLS checks ...
  
  const signedUrl = imagekit.url({
    path: file_path,
    signed: true,
    expireSeconds: expires_in
  })
  
  return new Response(
    JSON.stringify({ signed_url: signedUrl }),
    { headers: { 'Content-Type': 'application/json' } }
  )
})
```

---

### 10.2 Archive Strategy (Secured)

**Archive Storage:** Private GitHub Repository (GitHub Education Pack)

**Monthly Archive Process:**

```
Trigger: 1st of every month (Supabase cron job)

Steps:
1. Fetch attendance older than 3 months
2. Fetch salary records older than 12 months
3. Convert to JSON
4. Encrypt data:
   - Algorithm: AES-256-GCM
   - Key: Stored in Supabase secrets
   - IV: Generated per archive
5. Compress with gzip
6. Calculate SHA-256 checksum
7. Upload to private GitHub repo via API
8. Save archive reference in database:
   - archive_url
   - encryption_iv
   - checksum
   - total_records
   - file_size_bytes
9. Verify upload (download & verify checksum)
10. If verified: Delete old records from main tables
11. If failed: Alert admin, retry next day
```

**Encryption Implementation:**

```dart
import 'package:encrypt/encrypt.dart' as encrypt;

class ArchiveService {
  final key = encrypt.Key.fromSecureRandom(32); // 256-bit
  
  Future<Map<String, dynamic>> encryptAndArchive(List<Map> data) async {
    // 1. Convert to JSON
    final jsonData = json.encode(data);
    
    // 2. Encrypt
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.gcm)
    );
    
    final encrypted = encrypter.encrypt(jsonData, iv: iv);
    
    // 3. Compress
    final compressed = gzip.encode(encrypted.bytes);
    
    // 4. Calculate checksum
    final checksum = sha256.convert(compressed).toString();
    
    // 5. Upload to GitHub
    final githubUrl = await _uploadToGitHub(compressed);
    
    return {
      'archive_url': githubUrl,
      'encryption_iv': iv.base64,
      'checksum': checksum,
      'file_size_bytes': compressed.length,
      'total_records': data.length,
    };
  }
  
  Future<List<Map>> retrieveAndDecrypt(String archiveUrl, String ivBase64) async {
    // 1. Download from GitHub
    final response = await http.get(
      Uri.parse(archiveUrl),
      headers: {'Authorization': 'token ${GITHUB_TOKEN}'},
    );
    
    // 2. Decompress
    final decompressed = gzip.decode(response.bodyBytes);
    
    // 3. Decrypt
    final iv = encrypt.IV.fromBase64(ivBase64);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(key, mode: encrypt.AESMode.gcm)
    );
    
    final encrypted = encrypt.Encrypted(decompressed);
    final decrypted = encrypter.decrypt(encrypted, iv: iv);
    
    // 4. Parse JSON
    return List<Map>.from(json.decode(decrypted));
  }
}
```

**GitHub API Upload:**

```dart
Future<String> _uploadToGitHub(List<int> data) async {
  final repo = 'your-org/guard-management-archives';
  final branch = 'main';
  final fileName = 'attendance_${DateFormat('yyyy_MM').format(DateTime.now())}.dat';
  final path = 'archives/${DateTime.now().year}/$fileName';
  
  // Encode as base64 for GitHub API
  final base64Data = base64Encode(data);
  
  final response = await http.put(
    Uri.parse('https://api.github.com/repos/$repo/contents/$path'),
    headers: {
      'Authorization': 'token ${GITHUB_TOKEN}',
      'Accept': 'application/vnd.github.v3+json',
    },
    body: json.encode({
      'message': 'Archive: ${DateFormat('MMMM yyyy').format(DateTime.now())}',
      'content': base64Data,
      'branch': branch,
    }),
  );
  
  if (response.statusCode == 201) {
    final data = json.decode(response.body);
    return data['content']['download_url'];
  }
  
  throw Exception('GitHub upload failed');
}
```

**Archive Access Control:**

- Archives stored in private GitHub repo
- Access token stored in Supabase secrets
- Only Admin and authorized roles can trigger retrieval
- Retrieval logged in audit_logs
- Decryption key never exposed to client

---

## 11. Security & Compliance

### 11.1 Data Security

**Encryption:**
- ✅ SSL/TLS for all network communication
- ✅ Database encryption at rest (Supabase managed)
- ✅ Archive encryption (AES-256-GCM)
- ✅ Password hashing (bcrypt with salt)
- ✅ Face encodings are non-reversible

**Access Control:**
- ✅ Row Level Security (RLS) enforced
- ✅ Role-based permissions
- ✅ JWT token authentication
- ✅ API key rotation policy
- ✅ Image access via signed URLs only

**Audit Trail:**
- ✅ All data changes logged (attendance_audit_log, audit_logs)
- ✅ User actions tracked with IP and user agent
- ✅ Financial transactions immutable
- ✅ Document access logged
- ✅ Supervisor approvals/rejections logged

### 11.2 Compliance

**Data Privacy (GDPR-Ready):**
- ✅ User consent for biometric data collection
- ✅ Data retention policies configurable
- ✅ Right to access: Users can view their data
- ✅ Right to erasure: Admin can delete guard records (archive first)
- ✅ Data portability: Export in JSON/Excel format
- ✅ Privacy policy and terms displayed during enrollment

**Biometric Data Handling:**
- Face encodings stored as numerical vectors (non-reversible)
- No face images stored for recognition
- User consent mandatory
- Can be deleted on request
- Compliance with biometric data regulations (varies by country)

**Financial Compliance:**
- ✅ Complete audit trail (financial_ledger)
- ✅ Immutable salary records
- ✅ Export for tax filing (Excel/PDF)
- ✅ Bank account data encrypted
- ✅ Payment tracking with status

**Employment Records:**
- ✅ All employment history maintained
- ✅ Document retention (7 years default)
- ✅ Audit-ready records
- ✅ Compliance with labor laws (varies by country)

---

## 12. Implementation Plan

### Timeline: 24 Weeks (~6 Months)

#### **Phase 1: Foundation (Weeks 1-3)**
- Project setup (Flutter + Supabase)
- Database schema with revised attendance table
- Authentication with role-based access
- Basic UI structure
- ImageKit integration
- Local SQLite setup for offline mode

#### **Phase 2: Guard Management (Weeks 4-6)**
- Enrollment form with all fields
- Document upload to ImageKit
- Face registration with ML Kit
- CRUD operations
- Search & filters
- Guard profile viewer

#### **Phase 3: Attendance System (Weeks 7-11)** [EXTENDED]
- **Week 7-8:** Face recognition attendance
  - ML Kit integration
  - Face encoding storage
  - Match threshold configuration
  - GPS capture
  
- **Week 9:** Manual fallback mechanism
  - Fallback UI flow
  - Photo capture (live only)
  - Reason selection
  - GPS validation
  
- **Week 10:** Supervisor approval workflow
  - Pending approvals dashboard
  - Approval/rejection interface
  - GPS map view
  - Photo viewer
  - Audit logging
  
- **Week 11:** Offline mode
  - Local SQLite implementation
  - Sync queue
  - Conflict resolution
  - UI indicators

#### **Phase 4: Salary Processing (Weeks 12-14)**
- Calculation engine with attendance validation
- Deductions management
- Processing wizard
- Excel export (2 sheets)
- Ledger entries
- Payment status tracking

#### **Phase 5: Admin Panel (Weeks 15-18)**
- Dashboard with charts
- Financial pivot tables
- Anti-fraud reports
- User management
- System settings
- Audit log viewer

#### **Phase 6: Data Management (Weeks 19-20)**
- Archive automation
- Encryption implementation
- GitHub integration
- Retrieval system
- Report builder

#### **Phase 7: Testing (Weeks 21-23)**
- Unit testing (all components)
- Integration testing
- Face recognition accuracy testing
- Offline mode testing
- Load testing (simulate 500+ guards)
- Security testing
- UAT with real users

#### **Phase 8: Deployment (Week 24)**
- Production environment setup
- Data migration (if from existing system)
- User training (Admin, FO, Supervisors)
- Go-live
- Post-launch monitoring

---

## 13. Success Metrics

### KPIs

| Metric | Target | Measurement |
|--------|--------|-------------|
| System Adoption | 95% guards registered | 30 days post-launch |
| Face Recognition Success Rate | >90% | Continuous monitoring |
| Manual Fallback Rate | <10% | Monthly |
| Supervisor Approval Time | <24 hours avg | Weekly |
| Salary Processing Time | <2 hours | Monthly |
| Offline Sync Success Rate | >98% | Daily |
| Admin Satisfaction | 4.5/5 | Quarterly survey |
| System Uptime | 99.5% | Monthly |

### ROI Calculation

**Before (Manual):**
- Admin time: 40 hours/month × ₹500/hr = ₹20,000
- Attendance fraud/errors: ~₹10,000/month
- Salary errors & rework: ₹5,000/month
- **Total: ₹35,000/month = ₹4,20,000/year**

**After (Automated):**
- System cost: ₹500/month
- Admin time: 5 hours/month × ₹500/hr = ₹2,500
- Reduced fraud: Multiple controls reduce misuse and provide traceability
- **Total: ₹3,000/month = ₹36,000/year**

**Annual Savings: ₹3,84,000 (91% reduction)**
**ROI: 1,067% in first year**

---

## 14. Appendices

### A. Glossary

| Term | Definition |
|------|------------|
| Guard Code | Unique identifier (e.g., BH001) |
| Unit Code | Short code for unit (e.g., BH for Bhawani) |
| OT | Overtime hours |
| PF | Provident Fund (retirement savings) |
| RLS | Row Level Security |
| ML Kit | Google's machine learning toolkit |
| ImageKit | Private media storage with signed URLs |
| Face Encoding | Numerical vector representing face (non-reversible) |
| Manual Fallback | Attendance method when face recognition fails |
| Offline Sync | Process of syncing locally stored attendance to server |

### B. System Requirements

**Mobile App:**
- Android 6.0+ or iOS 12+
- 2GB RAM minimum
- Camera (front-facing for face recognition)
- GPS (required for attendance)
- 100MB storage for offline data

**Web Admin:**
- Modern browser (Chrome 90+, Firefox 88+, Safari 14+)
- 1920x1080 resolution minimum
- Stable internet connection

**Server:**
- Supabase (managed)
- ImageKit (managed)
- GitHub (managed)

### C. Support & Maintenance

**Support Channels:**
- Email: support@example.com
- Phone: +91-XXXXXXXXXX
- In-app help center

**Maintenance Schedule:**
- Daily: Automated backups
- Weekly: Database optimization
- Monthly: Security updates, archive process
- Quarterly: Feature releases

### D. Training Requirements

**Admin Training (8 hours):**
- System overview
- Guard management
- Attendance approval
- Salary processing
- Reports & analytics
- Troubleshooting

**Field Officer Training (4 hours):**
- Mobile app usage
- Guard enrollment
- Attendance management
- Reports

**Supervisor Training (2 hours):**
- Attendance approval workflow
- Bulk attendance marking
- Reports

**Guard Training (1 hour):**
- App installation
- Face registration
- Mark attendance (face + manual fallback)
- View history

---

## Document Approval

| Role | Name | Signature | Date |
|------|------|-----------|------|
| Product Owner | | | |
| Tech Lead | | | |
| Security Officer | | | |
| Stakeholder | | | |

---

**END OF DOCUMENT**

*This PRD v2.1 incorporates critical changes to ensure operational defensibility and legal compliance while maintaining usability. The attendance system now balances automation with accountability through supervisor approval workflows and comprehensive audit controls.*
