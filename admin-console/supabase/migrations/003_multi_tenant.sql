-- Multi-Tenant SaaS Infrastructure - Phase 1
-- Organizations and tenant association (RLS DISABLED for testing)

-- ============================================
-- STEP 1: Organizations Table
-- ============================================

CREATE TABLE organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  subscription_status TEXT NOT NULL DEFAULT 'trial' CHECK (subscription_status IN ('trial', 'active', 'suspended', 'cancelled')),
  plan TEXT NOT NULL DEFAULT 'starter' CHECK (plan IN ('starter', 'professional', 'enterprise')),
  guard_limit INTEGER NOT NULL DEFAULT 50,
  trial_ends_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '30 days'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  
  -- Settings
  settings JSONB DEFAULT '{}'::jsonb
);

-- Auto-update timestamp
CREATE TRIGGER update_organizations_updated_at BEFORE UPDATE ON organizations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Indexes
CREATE INDEX idx_organizations_slug ON organizations(slug) WHERE deleted_at IS NULL;
CREATE INDEX idx_organizations_status ON organizations(subscription_status) WHERE deleted_at IS NULL;

-- ============================================
-- STEP 2: Platform Admins Table
-- ============================================

CREATE TABLE platform_admins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  email TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id)
);

CREATE INDEX idx_platform_admins_user ON platform_admins(user_id);

-- ============================================
-- STEP 3: Organization Users Table
-- ============================================

CREATE TABLE organization_users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES organizations(id),
  user_id UUID NOT NULL,
  email TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'admin' CHECK (role IN ('admin', 'manager', 'viewer')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(organization_id, user_id)
);

CREATE INDEX idx_org_users_org ON organization_users(organization_id);
CREATE INDEX idx_org_users_user ON organization_users(user_id);

-- ============================================
-- STEP 4: Add organization_id to existing tables
-- ============================================

-- Add to guards
ALTER TABLE guards ADD COLUMN organization_id UUID REFERENCES organizations(id);

-- Add to units
ALTER TABLE units ADD COLUMN organization_id UUID REFERENCES organizations(id);

-- Add to work_events
ALTER TABLE work_events ADD COLUMN organization_id_new UUID REFERENCES organizations(id);

-- ============================================
-- STEP 5: Create default organization and migrate data
-- ============================================

-- Insert default organization
INSERT INTO organizations (id, name, slug, subscription_status, plan, guard_limit)
VALUES (
  '00000000-0000-0000-0000-000000000000',
  'Default Organization',
  'default-org',
  'active',
  'enterprise',
  999999
) ON CONFLICT (id) DO NOTHING;

-- Backfill organization_id for existing data
UPDATE guards SET organization_id = '00000000-0000-0000-0000-000000000000' WHERE organization_id IS NULL;
UPDATE units SET organization_id = '00000000-0000-0000-0000-000000000000' WHERE organization_id IS NULL;
UPDATE work_events SET organization_id_new = '00000000-0000-0000-0000-000000000000' WHERE organization_id_new IS NULL;

-- Make organization_id NOT NULL after backfill
ALTER TABLE guards ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE units ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE work_events ALTER COLUMN organization_id_new SET NOT NULL;

-- Drop old organization_id from work_events and rename new one
ALTER TABLE work_events DROP COLUMN organization_id;
ALTER TABLE work_events RENAME COLUMN organization_id_new TO organization_id;

-- ============================================
-- STEP 6: Create composite indexes
-- ============================================

-- Guards
CREATE INDEX idx_guards_org_status ON guards(organization_id, employment_status) WHERE deleted_at IS NULL;
CREATE INDEX idx_guards_org_unit ON guards(organization_id, primary_unit_id) WHERE deleted_at IS NULL;

-- Units
CREATE INDEX idx_units_org ON units(organization_id) WHERE deleted_at IS NULL;

-- Work Events
CREATE INDEX idx_work_events_org_date ON work_events(organization_id, shift_date) WHERE deleted_at IS NULL;
CREATE INDEX idx_work_events_org_guard ON work_events(organization_id, guard_id) WHERE deleted_at IS NULL;

-- ============================================
-- STEP 7: RLS Policies (CREATED BUT NOT ENABLED)
-- ============================================

-- Organizations
CREATE POLICY "org_tenant_isolation_select"
  ON organizations FOR SELECT
  USING (id = current_setting('app.current_org_id', true)::uuid);

CREATE POLICY "org_tenant_isolation_update"
  ON organizations FOR UPDATE
  USING (id = current_setting('app.current_org_id', true)::uuid);

-- Guards
CREATE POLICY "guards_tenant_isolation_select"
  ON guards FOR SELECT
  USING (organization_id = current_setting('app.current_org_id', true)::uuid);

CREATE POLICY "guards_tenant_isolation_insert"
  ON guards FOR INSERT
  WITH CHECK (organization_id = current_setting('app.current_org_id', true)::uuid);

CREATE POLICY "guards_tenant_isolation_update"
  ON guards FOR UPDATE
  USING (organization_id = current_setting('app.current_org_id', true)::uuid);

CREATE POLICY "guards_tenant_isolation_delete"
  ON guards FOR DELETE
  USING (organization_id = current_setting('app.current_org_id', true)::uuid);

-- Units
CREATE POLICY "units_tenant_isolation_select"
  ON units FOR SELECT
  USING (organization_id = current_setting('app.current_org_id', true)::uuid);

CREATE POLICY "units_tenant_isolation_insert"
  ON units FOR INSERT
  WITH CHECK (organization_id = current_setting('app.current_org_id', true)::uuid);

CREATE POLICY "units_tenant_isolation_update"
  ON units FOR UPDATE
  USING (organization_id = current_setting('app.current_org_id', true)::uuid);

CREATE POLICY "units_tenant_isolation_delete"
  ON units FOR DELETE
  USING (organization_id = current_setting('app.current_org_id', true)::uuid);

-- Work Events
CREATE POLICY "work_events_tenant_isolation_select"
  ON work_events FOR SELECT
  USING (organization_id = current_setting('app.current_org_id', true)::uuid);

CREATE POLICY "work_events_tenant_isolation_insert"
  ON work_events FOR INSERT
  WITH CHECK (organization_id = current_setting('app.current_org_id', true)::uuid);

CREATE POLICY "work_events_tenant_isolation_update"
  ON work_events FOR UPDATE
  USING (organization_id = current_setting('app.current_org_id', true)::uuid);

-- ============================================
-- NOTE: RLS NOT ENABLED YET
-- ============================================
-- To enable RLS later, run:
-- ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE guards ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE units ENABLE ROW LEVEL SECURITY;
-- ALTER TABLE work_events ENABLE ROW LEVEL SECURITY;

-- ============================================
-- STEP 8: Helper Functions
-- ============================================

-- Set tenant context (for future RLS use)
CREATE OR REPLACE FUNCTION set_current_org_id(org_id UUID)
RETURNS void AS $$
BEGIN
  PERFORM set_config('app.current_org_id', org_id::text, false);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Get guard count for organization
CREATE OR REPLACE FUNCTION get_active_guard_count(org_id UUID)
RETURNS INTEGER AS $$
  SELECT COUNT(*)::INTEGER
  FROM guards
  WHERE organization_id = org_id
    AND employment_status = 'active'
    AND deleted_at IS NULL;
$$ LANGUAGE sql STABLE;
