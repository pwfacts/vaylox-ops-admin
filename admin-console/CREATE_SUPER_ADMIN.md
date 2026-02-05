# Create Super Admin Account - Step by Step

## Step 1: Disable Email Confirmation (Required for Testing)

1. Go to **Supabase Dashboard**: https://supabase.com
2. Select your project
3. Go to **Authentication** → **Providers** → **Email**
4. **UNCHECK** "Confirm email"
5. Click **Save**

## Step 2: Sign Up via the App

1. Go to: http://localhost:3000/signup
2. Fill in the form:
   - **Organization Name**: "Platform Admin Org" (or any name)
   - **Slug**: `platform-admin`
   - **Plan**: Starter (doesn't matter)
   - **Your Name**: "Prabhat"
   - **Email**: `prabhatworldtech@gmail.com`
   - **Password**: `Admin@123`
3. Click **"Start Free Trial"**
4. ✅ Account created!

## Step 3: Promote to Platform Super Admin

1. Go to **Supabase Dashboard** → **SQL Editor**
2. Run this SQL:

```sql
-- Find your user ID (should return your user details)
SELECT id, email, created_at 
FROM auth.users 
WHERE email = 'prabhatworldtech@gmail.com';

-- Copy the 'id' from above, then run this (replace YOUR_USER_ID):
INSERT INTO platform_admins (user_id, email)
VALUES ('YOUR_USER_ID_HERE', 'prabhatworldtech@gmail.com');
```

**Or use this one-step version:**

```sql
-- One-step: Get user ID and insert as platform admin
INSERT INTO platform_admins (user_id, email)
SELECT id, email 
FROM auth.users 
WHERE email = 'prabhatworldtech@gmail.com'
ON CONFLICT DO NOTHING;
```

## Step 4: Test Platform Admin Access

1. Visit: http://localhost:3000/login
2. Login with:
   - Email: `prabhatworldtech@gmail.com`
   - Password: `Admin@123`
3. Visit: http://localhost:3000/platform
4. ✅ You should see the Platform Admin dashboard!

---

## Alternative: Quick Test Account (No Email Required)

If you just want to test quickly without email verification:

```sql
-- Create test admin user directly (dev only!)
-- This bypasses normal signup

INSERT INTO auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  created_at,
  updated_at,
  raw_app_meta_data,
  raw_user_meta_data,
  is_super_admin,
  confirmation_token
) VALUES (
  '00000000-0000-0000-0000-000000000000',
  gen_random_uuid(),
  'authenticated',
  'authenticated',
  'prabhatworldtech@gmail.com',
  crypt('Admin@123', gen_salt('bf')),
  NOW(),
  NOW(),
  NOW(),
  '{"provider":"email","providers":["email"]}',
  '{"full_name":"Prabhat"}',
  false,
  ''
)
RETURNING id, email;

-- Then add as platform admin using the returned ID
```

**⚠️ Note:** The alternative method is complex. **Recommended approach** is Step 1-4 above!
