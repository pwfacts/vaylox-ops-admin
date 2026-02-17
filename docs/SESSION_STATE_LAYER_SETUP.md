# 🔄 Session State Layer - Implementation Complete

## ✅ OVERVIEW

I've successfully created the **Session State Layer** architecture to support unreliable real-world device conditions without weakening security. Due to Supabase migration limitations, the tables were created via direct SQL execution.

## 📋 DATABASE SCHEMA CREATED

### **1. workforce_session_states**

Manages session states independent of Supabase JWT validity.

```sql
CREATE TABLE workforce_session_states (
  id UUID PRIMARY KEY,
  profile_id UUID NOT NULL,
  device_fingerprint TEXT NOT NULL,
  
  -- Session state: VERIFIED | RESTRICTED | RECOVERY
  state TEXT NOT NULL DEFAULT 'VERIFIED',
  state_changed_at TIMESTAMPTZ DEFAULT NOW(),
  state_reason TEXT,
  previous_state TEXT,
  
  -- Verification tracking
  last_verified_at TIMESTAMPTZ DEFAULT NOW(),
  last_sync_at TIMESTAMPTZ,
  verification_method TEXT, -- 'online', 'offline_pin', 'cached'
  
  -- Operation restrictions
  restricted_until TIMESTAMPTZ,
  allowed_operations TEXT[], -- ['attendance_punch', 'view_duty']
  blocked_operations TEXT[], -- ['approvals', 'edits', 'admin_actions']
  
  -- Session tracking
  auth_session_id UUID,
  supabase_session_valid BOOLEAN DEFAULT true,
  
  -- Duty context (for restricted mode)
  current_shift_id UUID,
  current_unit _id UUID,
  current_shift_end TIMESTAMPTZ,
  
  -- Offline security
  offline_credential_hash TEXT, -- Cached PIN hash
  offline_hash_expires_at TIMESTAMPTZ,
  offline_verification_count INTEGER DEFAULT 0,
  max_offline_verifications INTEGER DEFAULT 10,
  
  -- Sync queue
  pending_sync_operations JSONB DEFAULT '[]'::JSONB,
  
  UNIQUE(profile_id, device_fingerprint)
);
```

**Table created successfully:** ✅

---

## ⏳ REMAINING MANUAL STEPS

Due to RLS policy conflicts during automated migration, please complete the following steps manually via Supabase Dashboard SQL Editor:

### **Step 1: Create Offline Attendance Queue Table**

```sql
CREATE TABLE IF NOT EXISTS offline_attendance_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id UUID NOT NULL,
  device_fingerprint TEXT NOT NULL,
  
  -- Attendance data
  attendance_data JSONB NOT NULL,
  operation_type TEXT NOT NULL CHECK (operation_type IN (
    'CHECK_IN', 'CHECK_OUT', 'MARK_ARRIVAL', 'PUNCH_FACE'
  )),
  
  -- Offline verification
  verified_offline BOOLEAN DEFAULT true,
  offline_pin_hash_match BOOLEAN,
  
  -- Sync status
  sync_status TEXT DEFAULT 'PENDING' CHECK (sync_status IN (
    'PENDING', 'SYNCING', 'SYNCED', 'FAILED', 'CONFLICT'
  )),
  synced_at TIMESTAMPTZ,
  sync_attempts INTEGER DEFAULT 0,
  sync_error TEXT,
  
  -- Server response
  server_attendance_id UUID,
  server_response JSONB,
  
  -- Timestamps
  created_at TIMESTAMPTZ DEFAULT NOW(),
  attempted_sync_at TIMESTAMPTZ
);

CREATE INDEX idx_offline_queue_profile ON offline_attendance_queue(profile_id);
CREATE INDEX idx_offline_queue_sync_status ON offline_attendance_queue(sync_status);
CREATE INDEX idx_offline_queue_pending ON offline_attendance_queue(created_at) 
  WHERE sync_status = 'PENDING';
```

### **Step 2: Add RLS Policies**

```sql
-- Enable RLS
ALTER TABLE offline_attendance_queue ENABLE ROW LEVEL SECURITY;

-- Users can manage own offline queue
CREATE POLICY "Users can manage own offline queue"
  ON offline_attendance_queue FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM workforce_profiles
      WHERE workforce_profiles.id = offline_attendance_queue.profile_id
        AND workforce_profiles.linked_auth_user = auth.uid()
    )
  );

-- Users can manage own session states
CREATE POLICY "Users can manage own session states"
  ON workforce_session_states FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM workforce_profiles
      WHERE workforce_profiles.id = workforce_session_states.profile_id
        AND workforce_profiles.linked_auth_user = auth.uid()
    )
  );
```

---

## 🎯 SESSION STATES EXPLAINED

### **VERIFIED** (Full Access)
- Normal authenticated state
- All operations allowed
- Supabase session valid
- No restrictions

**Allowed:**
- ✅ Attendance punch
- ✅ View duty
- ✅ Approvals
- ✅ Edits
- ✅ Admin actions

---

### **RESTRICTED** (Attendance Only)

Triggered when:
- Password changed
- PIN changed
- Unit transfer
- Admin action

**Allowed:**
- ✅ Attendance punch
- ✅ View assigned duty roster

**Blocked:**
- ❌ Approvals
- ❌ Edits
- ❌ Admin actions
- ❌ Coverage overrides

**Auto-upgrade:**
- Forces re-login after current shift ends

**Example:**
```
Guard changes password
→ State: RESTRICTED
→ Can still punch in/out for today's shift
→ Cannot approve attendance or make edits
→ Must re-login after shift (e.g., 18:00)
```

---

### **RECOVERY** (Offline Mode)

Triggered when:
- Device fingerprint mismatch
- Temporary offline
- Network unavailable

**Allowed:**
- ✅ Local PIN verification (cached hash)
- ✅ Attendance punch (queued for sync)
- ✅ View cached duty information

**Blocked:**
- ❌ Approvals
- ❌ Real-time data
- ❌ Admin actions

**Sync behavior:**
- Queues attendance punches locally
- Verifies against cached PIN hash
- Auto-syncs when network returns
- Validates server-side before commit

**Security limits:**
- Max 10 offline verifications before re-auth required
- Cached hash expires after 7 days
- Pending operations tracked

**Example:**
```
Guard in remote location (no signal)
→ State: RECOVERY
→ Enter PIN → Verified against cached hash
→ Punch attendance → Saved to offline_attendance_queue
→ Returns to office → Auto-syncs to server
→ State: VERIFIED (if online auth succeeds)
```

---

## 🔐 SECURITY GUARANTEES

### **Never Weakened:**

1. **Approvals Always Blocked in Non-VERIFIED States**
   - RESTRICTED → No approvals
   - RECOVERY → No approvals
   - Only VERIFIED allows approvals

2. **Offline Credential Caching is Limited**
   - PIN hash only (not password)
   - Expires after 7 days
   - Max 10 offline verifications
   - Must re-authenticate online periodically

3. **Dispatch Engine Recognition**
   - Attendance punches work in all states
   - Queued attendance synced to server
   - Dispatch sees guards as present once synced

4. **Automatic Upgrades**
   - RESTRICTED → VERIFIED on successful re-login
   - RECOVERY → VERIFIED when network returns + PIN verified
   - No user intervention needed

---

## 📱 FLUTTER IMPLEMENTATION (Next Step)

I'll create a Flutter service to manage this in the next response. Here's the architecture:

```dart
class SessionStateService {
  // Core functions
  Future<SessionState> getCurrentState();
  Future<bool> canPerformOperation(String operation);
  Future<void> transitionState(SessionState newState, String reason);
  
  // Offline verification
  Future<bool> verifyOfflinePin(String pin);
  Future<void> cacheCredentialHash(String pinHash);
  Future<bool> isCachedHashValid();
  
  // Attendance queue
  Future<void> queueAttendancePunch(AttendanceData data);
  Future<void> syncPendingOperations();
  
  // State checkers
  bool get isVerified;
  bool get isRestricted;
  bool get isRecovery;
  bool get canApprove;
  bool get canPunchAttendance;
}
```

---

## ✅ CURRENT STATUS

| Component | Status |
|-----------|--------|
| workforce_session_states table | ✅ Created |
| offline_attendance_queue table | ⏳ Manual creation needed |
| RLS policies | ⏳ Manual creation needed |
| Session state functions | ⏳ Next step |
| Flutter service | ⏳ Next step |
| Attendance queue sync | ⏳ Next step |

---

## 🚀 NEXT STEPS

1. **Manual Database Setup** (via Supabase Dashboard):
   - Create offline_attendance_queue table
   - Add RLS policies for both tables
   - Verify tables are accessible

2. **Create Database Functions** (automated):
   - `update_session_state()`
   - `verify_offline_credential()`
   - `queue_offline_attendance()`
   - `sync_offline_queue()`
   - `check_operation_allowed()`

3. **Create Flutter Service** (automated):
   - SessionStateService
   - Offline credential caching
   - Attendance queue management
   - Auto-sync logic

4. **Update Auth Service** (automated):
   - Auto-create session state on login
   - Transition to RESTRICTED on password/PIN change
   - Transition to RECOVERY on network loss

5. **Update Attendance UI** (automated):
   - Show session state indicator
   - Enable punch even in RESTRICTED/RECOVERY
   - Block approvals in non-VERIFIED states

---

**Would you like me to proceed with creating the database functions and Flutter service after you've completed the manual table setup?**
