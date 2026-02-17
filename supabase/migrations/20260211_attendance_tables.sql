-- Attendance table (from PRD section 4.1)
CREATE TABLE IF NOT EXISTS attendance (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL DEFAULT 'c0a80101-b632-4e6a-9818-1d2f9d5e3f4b' REFERENCES companies(id),
  guard_id UUID NOT NULL REFERENCES guards(id),
  attendance_date DATE NOT NULL,
  shift TEXT NOT NULL CHECK (shift IN ('day', 'night')),
  
  unit_id UUID NOT NULL REFERENCES units(id),
  worked_unit_id UUID REFERENCES units(id),
  primary_unit_id UUID REFERENCES units(id),
  type TEXT DEFAULT 'NORMAL' CHECK (type IN ('NORMAL', 'OT')),
  is_temporary_assignment BOOLEAN DEFAULT false,
  
  check_in_time TIMESTAMPTZ,
  check_out_time TIMESTAMPTZ,
  
  -- Attendance method
  attendance_method TEXT NOT NULL CHECK (
    attendance_method IN ('FACE', 'MANUAL_FALLBACK', 'SUPERVISOR')
  ),
  
  -- Face verification
  face_verified BOOLEAN DEFAULT false,
  face_match_score DECIMAL(5, 2),
  
  -- Manual fallback
  fallback_reason TEXT CHECK (
    fallback_reason IN ('POOR_LIGHTING', 'CAMERA_ISSUE', 'FACE_MISMATCH', 'DEVICE_ISSUE', 'OTHER')
  ),
  fallback_reason_text TEXT,
  fallback_photo_url TEXT,
  
  -- Approval workflow
  approval_status TEXT DEFAULT 'PENDING_APPROVAL' CHECK (
    approval_status IN ('PENDING_APPROVAL', 'APPROVED', 'REJECTED')
  ),
  approved_by UUID REFERENCES users(id),
  approved_at TIMESTAMPTZ,
  approval_notes TEXT,
  
  -- Location
  gps_location POINT,
  gps_accuracy DECIMAL(10, 2),
  
  -- OT
  is_ot BOOLEAN DEFAULT false,
  ot_hours DECIMAL(5, 2) DEFAULT 0,
  ot_rate_applied DECIMAL(10, 2),
  
  -- Offline sync
  synced_from_offline BOOLEAN DEFAULT false,
  device_id TEXT,
  offline_created_at TIMESTAMPTZ,
  
  marked_by_user_id UUID REFERENCES users(id),
  
  -- Soft delete for duplicate resolution
  is_voided BOOLEAN DEFAULT false,
  voided_at TIMESTAMPTZ,
  voided_by UUID REFERENCES users(id),
  void_reason TEXT,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Unique constraint only for non-voided records (partial unique index)
CREATE UNIQUE INDEX idx_attendance_unique_active 
  ON attendance(guard_id, attendance_date, shift) 
  WHERE (is_voided = false);

CREATE INDEX idx_attendance_company ON attendance(company_id);
CREATE INDEX idx_attendance_approval ON attendance(approval_status) WHERE approval_status = 'PENDING_APPROVAL';
CREATE INDEX idx_attendance_guard_date ON attendance(guard_id, attendance_date);
CREATE INDEX idx_attendance_voided ON attendance(is_voided) WHERE is_voided = false;

-- Safe sync RPC with duplicate detection
CREATE OR REPLACE FUNCTION sync_attendance(
  p_guard_id UUID,
  p_attendance_date DATE,
  p_shift TEXT,
  p_data JSONB
)
RETURNS JSONB AS $$
DECLARE
  v_existing_id UUID;
  v_new_id UUID;
BEGIN
  -- Check for existing non-voided record
  SELECT id INTO v_existing_id
  FROM attendance
  WHERE guard_id = p_guard_id
    AND attendance_date = p_attendance_date
    AND shift = p_shift
    AND is_voided = false;
  
  IF v_existing_id IS NOT NULL THEN
    -- Duplicate found
    RETURN jsonb_build_object(
      'status', 'duplicate',
      'existing_id', v_existing_id,
      'message', 'Attendance already exists for this guard, date, and shift'
    );
  END IF;
  
  -- Insert new record
  INSERT INTO attendance (
    guard_id,
    attendance_date,
    shift,
    company_id,
    unit_id,
    attendance_method,
    check_in_time,
    gps_location,
    face_match_score,
    fallback_reason,
    fallback_photo_url,
    approval_status,
    synced_from_offline,
    device_id,
    offline_created_at
  )
  SELECT
    p_guard_id,
    p_attendance_date,
    p_shift,
    (p_data->>'company_id')::UUID,
    (p_data->>'unit_id')::UUID,
    p_data->>'attendance_method',
    (p_data->>'check_in_time')::TIMESTAMPTZ,
    ST_MakePoint(
      (p_data->'gps_location'->>'lng')::FLOAT,
      (p_data->'gps_location'->>'lat')::FLOAT
    ),
    (p_data->>'face_match_score')::DECIMAL,
    p_data->>'fallback_reason',
    p_data->>'fallback_photo_url',
    COALESCE(p_data->>'approval_status', 'PENDING_APPROVAL'),
    true,
    p_data->>'device_id',
    (p_data->>'offline_created_at')::TIMESTAMPTZ
  RETURNING id INTO v_new_id;
  
  RETURN jsonb_build_object(
    'status', 'success',
    'id', v_new_id,
    'message', 'Attendance synced successfully'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
