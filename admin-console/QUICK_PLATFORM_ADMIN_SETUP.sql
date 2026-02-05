-- Quick Setup: Create Platform Admins Table Only
-- Run this in Supabase SQL Editor to test platform admin features

-- Create platform_admins table
CREATE TABLE IF NOT EXISTS platform_admins (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  email TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE(user_id)
);

CREATE INDEX IF NOT EXISTS idx_platform_admins_user ON platform_admins(user_id);

-- Promote your account to platform admin
INSERT INTO platform_admins (user_id, email)
SELECT id, email 
FROM auth.users 
WHERE email = 'prabhatworldtech@gmail.com'
ON CONFLICT (user_id) DO NOTHING;

-- Verify it worked
SELECT * FROM platform_admins;
