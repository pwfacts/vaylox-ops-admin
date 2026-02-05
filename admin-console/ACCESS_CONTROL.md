# Access Control & Routing

## User Roles & Routes

### 🔑 Platform Super Admin
**Who:** You (prabhatworldtech@gmail.com) - manually added to `platform_admins` table

**Can Access:**
- ✅ `/platform` - Platform admin dashboard
- ✅ `/platform/*` - All platform routes

**Cannot Access:**
- ❌ `/` - Org dashboard (auto-redirects to `/platform`)
- ❌ `/workforce` - Org workforce
- ❌ `/attendance` - Org attendance
- ❌ `/guard` - Guard terminal

**Purpose:** Manage all organizations, suspend/activate, adjust limits, view platform metrics

---

### 👔 Organization Admin
**Who:** Users created via `/signup` OR added to an organization

**Can Access:**
- ✅ `/` - Command Dashboard
- ✅ `/workforce` - Guard management
- ✅ `/units` - Unit management
- ✅ `/attendance` - Attendance command center

**Cannot Access:**
- ❌ `/platform` - Platform admin (auto-redirects to `/`)
- ❌ `/guard` - Guard terminal (future: can access for testing)

**Purpose:** Manage their organization's workforce, attendance, payroll

---

### 💂 Guard (Mobile App User)
**Who:** Security guards in the field

**Can Access:**
- ✅ `/guard` - Field terminal (QR code check-in/out)
- ✅ Mobile app (Flutter - future)

**Cannot Access:**
- ❌ `/` - Org dashboard
- ❌ `/workforce` - Management features
- ❌ `/platform` - Platform admin

**Purpose:** Check-in/out, view schedules, attendance history

---

## Auto-Redirect Logic

### Login Flow:
```
User Logs In
    ↓
Platform Admin? → Yes → /platform
    ↓ No
Org Admin? → Yes → /
    ↓ No
Guard? → Yes → /guard
    ↓ No
Not Associated → /signup
```

### Route Protection:
- `/platform/*` - Requires platform_admins entry
- `/`, `/workforce`, `/attendance`, `/units` - Requires organization_users entry
- `/guard` - Requires guards table entry (future)
- `/login`, `/signup` - Public (redirects if already logged in)

---

## How It Works

**Middleware (`middleware.ts`)** runs on EVERY request:

1. **Check Authentication** - Is user logged in?
2. **Check Role** - Platform admin? Org admin? Guard?
3. **Enforce Access** - Redirect if accessing wrong route
4. **Prevent Cross-Access** - Platform admin can't access org routes and vice versa

---

## Testing Access Control

### Test 1: Platform Admin Access
1. Login as: `prabhatworldtech@gmail.com`
2. Try visiting `/` → Should redirect to `/platform`
3. Visit `/platform` → Should work ✅

### Test 2: Org Admin Access
1. Create new org via `/signup` (test@example.com)
2. Login as test user
3. Try visiting `/platform` → Should redirect to `/` ❌
4. Visit `/` → Should work ✅

### Test 3: No Access for Unassociated Users
1. Create user without org (via Supabase Auth directly)
2. Try logging in
3. Should redirect to `/signup`

---

## Current Setup

✅ **Platform Admin:** prabhatworldtech@gmail.com (you)
✅ **Access Control:** Middleware active
✅ **Auto Redirects:** Based on role

**Try it now!** Logout and login again - you should auto-redirect to `/platform`
