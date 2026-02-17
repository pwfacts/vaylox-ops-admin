-- ============================================
-- SESSION STATE LAYER - MANUAL SETUP SCRIPT
-- Run this in Supabase Dashboard → SQL Editor
-- ============================================

-- STEP 1: Create offline_attendance_queue table
-- ============================================
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

-- Add indexes
CREATE INDEX IF NOT EXISTS idx_offline_queue_profile 
  ON offline_attendance_queue(profile_id);
  
CREATE INDEX IF NOT EXISTS idx_offline_queue_sync_status 
  ON offline_attendance_queue(sync_status);
  
CREATE INDEX IF NOT EXISTS idx_offline_queue_pending 
  ON offline_attendance_queue(created_at) 
  WHERE sync_status = 'PENDING';

-- Add comment
COMMENT ON TABLE offline_attendance_queue IS 
'Queue for attendance punches made offline or in restricted mode';

-- STEP 2: Enable RLS
-- ============================================
ALTER TABLE offline_attendance_queue ENABLE ROW LEVEL SECURITY;

-- STEP 3: Add RLS Policies
-- ============================================

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

-- Admins can view all offline queue in organization
CREATE POLICY "Admins can view organization offline queue"
  ON offline_attendance_queue FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM workforce_profiles wp
      JOIN organization_users ou ON ou.organization_id = wp.organization_id
      WHERE wp.id = offline_attendance_queue.profile_id
        AND ou.user_id = auth.uid()
        AND ou.role IN ('admin', 'super_admin')
    )
  );

-- STEP 4: Verify Tables Created
-- ============================================
SELECT 
  table_name,
  (SELECT COUNT(*) FROM information_schema.columns 
   WHERE table_name = t.table_name) as column_count
FROM information_schema.tables t
WHERE table_schema = 'public'
  AND table_name IN ('workforce_session_states', 'offline_attendance_queue')
ORDER BY table_name;

-- Expected output:
-- workforce_session_states | 25
-- offline_attendance_queue | 13

-- STEP 5: Test Insert (Optional)
-- ============================================
-- Test creating a session state (replace with real UUIDs)
/*
INSERT INTO workforce_session_states (
  profile_id,
  device_fingerprint,
  state
)
VALUES (
  '00000000-0000-0000-0000-000000000000', -- Replace with real profile_id
  'test-device-fingerprint',
  'VERIFIED'
);

-- Verify
SELECT * FROM workforce_session_states LIMIT 1;
*/

-- ============================================
-- SETUP COMPLETE
-- ============================================
-- Next steps:
-- 1. Run supabase/migrations/session_state_functions.sql
-- 2. Test FlutterSessionStateService integration
-- 3. Verify attendance works in offline mode
-- ============================================
