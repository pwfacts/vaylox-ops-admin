-- Work Events Table (Production-grade attendance with auditability)
-- This is NOT a simple attendance table - it's a work event ledger

-- Duty Type ENUM
CREATE TYPE duty_type AS ENUM (
  'PRIMARY',
  'TEMP_DEPLOYMENT',
  'OVERTIME',
  'DOUBLE_SHIFT',
  'UNSCHEDULED'
);

-- Event Status ENUM
CREATE TYPE event_status AS ENUM (
  'CHECKED_IN',
  'CHECKED_OUT',
  'NO_SHOW',
  'CANCELLED'
);

-- Approval Status ENUM
CREATE TYPE approval_status AS ENUM (
  'AUTO_APPROVED',
  'PENDING',
  'APPROVED',
  'REJECTED'
);

-- Work Events Table
CREATE TABLE work_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL,
  guard_id UUID NOT NULL REFERENCES guards(id),
  
  -- Unit tracking
  primary_unit_id UUID NOT NULL REFERENCES units(id),
  working_unit_id UUID NOT NULL REFERENCES units(id),
  
  -- Time tracking
  check_in_time TIMESTAMPTZ NOT NULL,
  check_out_time TIMESTAMPTZ,
  shift_date DATE NOT NULL,
  total_hours DECIMAL(5,2),
  
  -- Classification
  duty_type duty_type NOT NULL DEFAULT 'UNSCHEDULED',
  event_status event_status NOT NULL DEFAULT 'CHECKED_IN',
  approval_status approval_status NOT NULL DEFAULT 'PENDING',
  
  -- Anomaly tracking
  anomaly_flag BOOLEAN NOT NULL DEFAULT false,
  anomaly_reason TEXT,
  
  -- Audit & Lock
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  locked_at TIMESTAMPTZ,
  deleted_at TIMESTAMPTZ,
  
  -- Metadata
  created_by UUID,
  approved_by UUID,
  approved_at TIMESTAMPTZ
);

-- CRITICAL: One active shift per guard (duplicate prevention)
CREATE UNIQUE INDEX idx_work_events_one_active_per_guard 
  ON work_events(guard_id) 
  WHERE event_status = 'CHECKED_IN' AND deleted_at IS NULL;

-- Performance indexes
CREATE INDEX idx_work_events_org ON work_events(organization_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_work_events_guard ON work_events(guard_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_work_events_shift_date ON work_events(shift_date) WHERE deleted_at IS NULL;
CREATE INDEX idx_work_events_status ON work_events(event_status) WHERE deleted_at IS NULL;
CREATE INDEX idx_work_events_approval ON work_events(approval_status) WHERE deleted_at IS NULL AND approval_status = 'PENDING';

-- RLS Policies
ALTER TABLE work_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view their org work events"
  ON work_events FOR SELECT
  USING (organization_id = current_setting('app.current_org_id')::uuid AND deleted_at IS NULL);

CREATE POLICY "Users can insert work events for their org"
  ON work_events FOR INSERT
  WITH CHECK (organization_id = current_setting('app.current_org_id')::uuid);

CREATE POLICY "Users can update their org work events"
  ON work_events FOR UPDATE
  USING (
    organization_id = current_setting('app.current_org_id')::uuid 
    AND (locked_at IS NULL OR approval_status = 'PENDING')
  );

-- Auto-update timestamp trigger
CREATE TRIGGER update_work_events_updated_at BEFORE UPDATE ON work_events
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Prevent editing locked events (extra safety)
CREATE OR REPLACE FUNCTION prevent_locked_event_edit()
RETURNS TRIGGER AS $$
BEGIN
  IF OLD.locked_at IS NOT NULL AND OLD.locked_at != NEW.locked_at THEN
    RAISE EXCEPTION 'Cannot edit locked work event. Create correction entry.';
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER prevent_locked_work_event_edit
  BEFORE UPDATE ON work_events
  FOR EACH ROW
  WHEN (OLD.locked_at IS NOT NULL)
  EXECUTE FUNCTION prevent_locked_event_edit();

-- Calculate total hours on checkout
CREATE OR REPLACE FUNCTION calculate_total_hours()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.check_out_time IS NOT NULL AND NEW.check_in_time IS NOT NULL THEN
    NEW.total_hours = EXTRACT(EPOCH FROM (NEW.check_out_time - NEW.check_in_time)) / 3600;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER calculate_work_event_hours
  BEFORE INSERT OR UPDATE ON work_events
  FOR EACH ROW
  EXECUTE FUNCTION calculate_total_hours();
