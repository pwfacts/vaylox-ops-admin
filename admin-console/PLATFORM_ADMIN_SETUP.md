# Platform Super Admin Setup

## Initial Super Admin Creation

Since platform admins are created manually for security, here's how to add your first super admin:

### Method 1: Direct SQL (Recommended)

1. Go to Supabase SQL Editor
2. Run this query after a user has signed up:

```sql
-- Get user ID (replace with your email)
SELECT id, email FROM auth.users WHERE email = 'youremail@example.com';

-- Add as platform admin (use the ID from above)
INSERT INTO platform_admins (user_id, email)
VALUES ('USER_ID_HERE', 'youremail@example.com');
```

### Method 2: Via Server Action (Development Only)

```typescript
// In your development console or temporary route:
import { addPlatformAdmin } from '@/app/actions/auth'

await addPlatformAdmin('your.email@example.com')
```

## Routes

- **Public Signup:** `/signup` - Self-serve organization creation
- **Login:** `/login` - Email/password authentication  
- **Platform Admin:** `/platform` - Protected, super admin only
- **Org Admin Dashboard:** `/` - Protected, org members only

## Access Flow

### New Organization (Self-Serve)
1. Visit `/signup`
2. Fill organization details + admin account
3. Auto-creates:
   - Organization (with 30-day trial)
   - Admin user account
   - Links user to organization
4. Email verification required
5. Login at `/login`
6. Access org dashboard

### Platform Super Admin
1. Create account via signup OR manually
2. Manually add to `platform_admins` table
3. Login at `/login`
4. Access `/platform` to manage all orgs
5. Can:
   - Create organizations manually
   - Suspend/reactivate orgs
   - Adjust guard limits
   - View platform metrics

## Security Notes

- Platform admins CANNOT access org operational data (respects tenant privacy)
- Org admins can only see their own organization
- RLS (when enabled) enforces tenant isolation
- Super admin access is manually granted (no self-service)
