-- Guards table (MVP - minimal fields)
CREATE TABLE guards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL,
  full_name TEXT NOT NULL,
  phone_number TEXT NOT NULL,
  guard_code TEXT NOT NULL,
  primary_unit_id UUID,
  employment_status TEXT NOT NULL DEFAULT 'active' CHECK (employment_status IN ('active', 'inactive', 'suspended')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  UNIQUE(organization_id, guard_code)
);

-- Units table (lightweight - just enough for assignment)
CREATE TABLE units (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL,
  unit_name TEXT NOT NULL,
  address TEXT,
  required_guard_count INTEGER NOT NULL DEFAULT 1,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ
);

-- Indexes for performance
CREATE INDEX idx_guards_org ON guards(organization_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_guards_unit ON guards(primary_unit_id) WHERE deleted_at IS NULL;
CREATE INDEX idx_guards_code ON guards(organization_id, guard_code) WHERE deleted_at IS NULL;
CREATE INDEX idx_units_org ON units(organization_id) WHERE deleted_at IS NULL;

-- RLS Policies (Tenant isolation)
ALTER TABLE guards ENABLE ROW LEVEL SECURITY;
ALTER TABLE units ENABLE ROW LEVEL SECURITY;

-- Guards policies
CREATE POLICY "Users can view their org guards"
  ON guards FOR SELECT
  USING (organization_id = current_setting('app.current_org_id')::uuid AND deleted_at IS NULL);

CREATE POLICY "Users can insert guards for their org"
  ON guards FOR INSERT
  WITH CHECK (organization_id = current_setting('app.current_org_id')::uuid);

CREATE POLICY "Users can update their org guards"
  ON guards FOR UPDATE
  USING (organization_id = current_setting('app.current_org_id')::uuid);

-- Units policies
CREATE POLICY "Users can view their org units"
  ON units FOR SELECT
  USING (organization_id = current_setting('app.current_org_id')::uuid AND deleted_at IS NULL);

CREATE POLICY "Users can insert units for their org"
  ON units FOR INSERT
  WITH CHECK (organization_id = current_setting('app.current_org_id')::uuid);

CREATE POLICY "Users can update their org units"
  ON units FOR UPDATE
  USING (organization_id = current_setting('app.current_org_id')::uuid);

-- Auto-update updated_at trigger
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ language 'plpgsql';

CREATE TRIGGER update_guards_updated_at BEFORE UPDATE ON guards
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_units_updated_at BEFORE UPDATE ON units
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
