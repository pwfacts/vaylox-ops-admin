-- FIX MISSING SCHEMA ELEMENTS
-- Prerequisites for supervisor_driven_register.sql

-- 1. Create shift_instances table
CREATE TABLE IF NOT EXISTS shift_instances (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  unit_id UUID NOT NULL REFERENCES units(id),
  shift_id UUID REFERENCES shifts(id),
  shift_date DATE NOT NULL,
  shift_start_time TIMESTAMPTZ, 
  shift_end_time TIMESTAMPTZ,
  current_owner_profile_id UUID REFERENCES workforce_profiles(id),
  previous_owner_profile_id UUID REFERENCES workforce_profiles(id),
  required_guards INTEGER DEFAULT 1,
  status TEXT DEFAULT 'SCHEDULED',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_shift_instances_date ON shift_instances(shift_date);
CREATE INDEX IF NOT EXISTS idx_shift_instances_unit ON shift_instances(unit_id);
CREATE INDEX IF NOT EXISTS idx_shift_instances_owner ON shift_instances(current_owner_profile_id);

-- 2. Add shift_instance_id to attendance
ALTER TABLE attendance 
ADD COLUMN IF NOT EXISTS shift_instance_id UUID REFERENCES shift_instances(id);

CREATE INDEX IF NOT EXISTS idx_attendance_shift_instance ON attendance(shift_instance_id);

-- 3. Create attendance_exceptions table
CREATE TABLE IF NOT EXISTS attendance_exceptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  attendance_id UUID NOT NULL REFERENCES attendance(id),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  exception_type TEXT NOT NULL,
  exception_message TEXT,
  exception_details JSONB,
  resolved BOOLEAN DEFAULT false,
  resolved_at TIMESTAMPTZ,
  resolved_by UUID REFERENCES users(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_attendance_exceptions_attendance ON attendance_exceptions(attendance_id);

-- 4. Create shift_ownership_history table (referenced in transfer_shift_register_model)
CREATE TABLE IF NOT EXISTS shift_ownership_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shift_instance_id UUID NOT NULL REFERENCES shift_instances(id),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  unit_id UUID NOT NULL REFERENCES units(id),
  shift_date DATE NOT NULL,
  from_profile_id UUID REFERENCES workforce_profiles(id),
  to_profile_id UUID REFERENCES workforce_profiles(id),
  change_reason TEXT,
  change_note TEXT,
  changed_by UUID REFERENCES users(id),
  new_status TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE shift_instances IS 'Instances of shifts assigned to specific guards/units for a date';
COMMENT ON TABLE attendance_exceptions IS 'Logs of exceptions/warnings generated during attendance capture';
