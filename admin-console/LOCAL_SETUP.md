# Local Development Setup Guide

## Prerequisites
- Node.js 18+ installed
- Supabase account with project created
- Git (optional)

## Step 1: Install Dependencies

```bash
cd admin-console
npm install
```

## Step 2: Environment Variables

Create `.env.local` in the `admin-console` directory:

```env
# Supabase Configuration
NEXT_PUBLIC_SUPABASE_URL=your_supabase_project_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_supabase_anon_key
```

**Where to find these:**
1. Go to https://supabase.com
2. Open your project
3. Settings → API
4. Copy "Project URL" and "anon/public" key

## Step 3: Apply Database Migrations

Go to Supabase SQL Editor and run these migrations in order:

### Migration 1: Workforce Core
File: `supabase/migrations/001_workforce_core.sql`
- Run the entire file in SQL Editor

### Migration 2: Work Events
File: `supabase/migrations/002_work_events.sql`
- Run the entire file in SQL Editor

### Migration 3: Multi-Tenant Infrastructure
File: `supabase/migrations/003_multi_tenant.sql`
- Run the entire file in SQL Editor

## Step 4: Start Development Server

```bash
npm run dev
```

Server will start at: **http://localhost:3000**

## Step 5: Create First Platform Super Admin

### Option A: Via SQL (Recommended)

1. First, create an account via signup: http://localhost:3000/signup
2. Then in Supabase SQL Editor, run:

```sql
-- Find your user ID
SELECT id, email FROM auth.users WHERE email = 'your.email@example.com';

-- Add as platform admin (replace USER_ID)
INSERT INTO platform_admins (user_id, email)
VALUES ('YOUR_USER_ID_HERE', 'your.email@example.com');
```

### Option B: Quick Test Account

```sql
-- Create a test super admin directly
-- First sign up via /signup, then promote to platform admin
```

## Step 6: Test the System

### Test Organization Signup
1. Visit http://localhost:3000/signup
2. Create a test organization
3. Choose a plan
4. Complete signup
5. Check email for verification (Supabase sends this)

### Test Platform Admin
1. Visit http://localhost:3000/login
2. Login with super admin account
3. Visit http://localhost:3000/platform
4. You should see:
   - Platform metrics
   - Organization list
   - Create organization button
   - Suspend/activate controls

### Test Org Admin Dashboard
1. Login with organization account (not super admin)
2. Visit http://localhost:3000
3. You should see:
   - Command dashboard
   - Workforce page (/workforce)
   - Units page (/units)
   - Attendance page (/attendance)
   - Guard terminal (/guard)

### Test Guard Limit Enforcement
1. Login as org admin
2. Go to /workforce
3. Try to create guards
4. When you hit the limit (50 for Starter), you should get an error

## Available Routes

### Public
- `/signup` - Organization signup
- `/login` - Login page

### Org Admin (Authenticated)
- `/` - Command Dashboard
- `/workforce` - Guard management
- `/units` - Unit management
- `/attendance` - Attendance command center
- `/guard` - Guard field terminal (mobile-first)

### Platform Admin (Super Admin Only)
- `/platform` - Platform administration

## Development Commands

```bash
# Start dev server
npm run dev

# Build for production
npm run build

# Start production server
npm start

# Type check
npx tsc --noEmit
```

## Troubleshooting

### "Cannot find module" errors
```bash
npm install
```

### Supabase connection issues
- Check `.env.local` has correct URL and key
- Verify project is not paused in Supabase dashboard

### "Organization not found" errors
- Run migration 003_multi_tenant.sql
- Check default organization exists in database

### RLS blocking queries
- RLS is DISABLED by default for testing
- Once tested, uncomment the ALTER TABLE statements in migration 003

## Next Steps After Testing

1. ✅ Test all features locally
2. ✅ Create test organizations
3. ✅ Test guard limits
4. ✅ Test platform admin functions
5. 🚀 Deploy to Vercel
6. 📊 Build payroll module
7. 📱 Build mobile app for guards

## Port Already in Use?

If port 3000 is busy:
```bash
# Use different port
npm run dev -- -p 3001
```

Or kill the process:
```bash
# Windows
netstat -ano | findstr :3000
taskkill /PID <PID> /F

# Mac/Linux
lsof -ti:3000 | xargs kill -9
```
