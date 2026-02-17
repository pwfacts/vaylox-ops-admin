-- Field officer unit assignments (many-to-many)
CREATE TABLE IF NOT EXISTS field_officer_units (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id),
  unit_id UUID NOT NULL REFERENCES units(id),
  assigned_at TIMESTAMPTZ DEFAULT NOW(),
  assigned_by UUID REFERENCES users(id),
  UNIQUE(user_id, unit_id)
);

CREATE INDEX idx_fo_units_user ON field_officer_units(user_id);
CREATE INDEX idx_fo_units_unit ON field_officer_units(unit_id);

-- Correction requests (append-only)
CREATE TABLE IF NOT EXISTS correction_requests (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  company_id UUID NOT NULL DEFAULT 'c0a80101-b632-4e6a-9818-1d2f9d5e3f4b' REFERENCES companies(id),
  type TEXT NOT NULL CHECK (type IN ('ATTENDANCE', 'SALARY')),
  target_id UUID NOT NULL, -- attendance_id or salary_slip_id
  
  requested_by UUID NOT NULL REFERENCES users(id),
  requested_at TIMESTAMPTZ DEFAULT NOW(),
  reason TEXT NOT NULL,
  
  old_values JSONB NOT NULL,
  new_values JSONB NOT NULL,
  
  status TEXT DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'APPROVED', 'REJECTED')),
  reviewed_by UUID REFERENCES users(id),
  reviewed_at TIMESTAMPTZ,
  review_notes TEXT,
  
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_corrections_status ON correction_requests(status);
CREATE INDEX idx_corrections_type ON correction_requests(type);
