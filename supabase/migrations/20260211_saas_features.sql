-- 1. Companies Table (Tenant)
CREATE TABLE IF NOT EXISTS companies (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  address TEXT,
  subscription_status TEXT DEFAULT 'ACTIVE' CHECK (subscription_status IN ('ACTIVE', 'SUSPENDED', 'TRIAL')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Public read access for registration dropdown
ALTER TABLE companies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS public_companies_read ON companies;
CREATE POLICY public_companies_read ON companies FOR SELECT USING (true); 

-- 2. Update Users Table
ALTER TABLE users ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'PENDING' CHECK (status IN ('ACTIVE', 'PENDING', 'SUSPENDED', 'REJECTED'));
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_super_admin BOOLEAN DEFAULT false;
ALTER TABLE users ADD COLUMN IF NOT EXISTS company_id UUID REFERENCES companies(id);

-- 3. Super Admin Helper
CREATE OR REPLACE FUNCTION is_super_admin()
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND is_super_admin = true);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 4. RLS Updates: Allow Super Admin to bypass tenant checks
-- Start with users table
DROP POLICY IF EXISTS users_isolation_policy ON users;
CREATE POLICY users_isolation_policy ON users
  FOR ALL USING (
    (company_id = current_setting('app.company_id', true)::UUID) 
    OR is_super_admin()
    OR (auth.uid() = id) -- Users can always see themselves
  );

-- Registration policy (Public Insert into users pending approval)
-- Note: 'users' is usually managed by Auth, but we have a public profile table 'users'.
-- We need to allow new users to insert their profile.
CREATE POLICY users_registration_insert ON users
  FOR INSERT WITH CHECK (
    auth.uid() = id -- Can only insert own profile
  );

-- Update status trigger for new registrations
-- Auto-set status to PENDING (already default, but good to be explicit)
