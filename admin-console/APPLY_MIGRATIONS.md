# Quick Migration Guide

## Step 1: Go to Supabase Dashboard

1. Open https://supabase.com
2. Select your project
3. Click **SQL Editor** in the left sidebar

## Step 2: Apply Migrations (IN ORDER!)

### Migration 1: Workforce Core
1. Open: `admin-console/supabase/migrations/001_workforce_core.sql`
2. Copy ALL content
3. Paste into SQL Editor
4. Click **Run** (or press Ctrl+Enter)
5. ✅ Wait for "Success. No rows returned"

### Migration 2: Work Events
1. Open: `admin-console/supabase/migrations/002_work_events.sql`
2. Copy ALL content
3. Paste into SQL Editor
4. Click **Run**
5. ✅ Wait for "Success. No rows returned"

### Migration 3: Multi-Tenant (CRITICAL!)
1. Open: `admin-console/supabase/migrations/003_multi_tenant.sql`
2. Copy ALL content
3. Paste into SQL Editor
4. Click **Run**
5. ✅ Wait for "Success. No rows returned"

## Step 3: Verify Tables Exist

In SQL Editor, run:
```sql
SELECT table_name 
FROM information_schema.tables 
WHERE table_schema = 'public'
ORDER BY table_name;
```

You should see:
- ✅ guards
- ✅ organizations
- ✅ organization_users
- ✅ platform_admins
- ✅ units
- ✅ work_events

## Step 4: Test Signup Again

Go back to http://localhost:3000/signup and try creating an organization!

---

**Current Error:** Table `organizations` doesn't exist = Migrations not applied yet
