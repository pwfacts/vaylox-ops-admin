# Guard Authentication & Profile System - Quick Setup Guide

## ✅ What's Been Built

### 1. Database Schema
- ✅ `guards` table updated with auth fields (user_id, auth_provider, Google ID)
- ✅ Profile fields added (photo URLs, bio data, addresses, IDs)
- ✅ `guard_documents` table created for ID cards and certificates

### 2. Server Actions (`app/actions/guard-auth.ts`)
- ✅ Admin creates guard accounts with email/password
- ✅ Admin resets guard passwords
- ✅ Admin links Google accounts
- ✅ Guards login via email or Google OAuth
- ✅ Guards manage their profiles
- ✅ ImageKit photo and document uploads

### 3. UI Components
- ✅ **Guard Login** (`/guard/login`) - Email + Google OAuth
- ✅ **Guard Profile** (`/guard/profile`) - Full bio editor + photo upload
- ✅ **ImageKit Upload Component** - Reusable uploader
- ✅ **Admin Auth Management** - Embed in workforce page

### 4. ImageKit Integration
- ✅ Uses existing `imagekit-signature` edge function
- ✅ API route for auth (`/api/imagekit-auth`)
- ✅ Secure uploads with signatures
- ✅ All photos stored on ImageKit (not Supabase Storage)

---

## 🚀 Setup Steps

### Step 1: Add Environment Variables

Add to your `.env.local`:

```bash
# ImageKit (Get from ImageKit dashboard)
NEXT_PUBLIC_IMAGEKIT_PUBLIC_KEY=your_public_key_here
NEXT_PUBLIC_IMAGEKIT_URL_ENDPOINT=https://ik.imagekit.io/your_imagekit_id
```

**Note:** `IMAGEKIT_PRIVATE_KEY` is already set in your Supabase edge function secrets ✅

### Step 2: Enable Google OAuth (Optional)

If you want Google login for guards:

1. Go to Supabase Dashboard → Authentication → Providers
2. Click **Google**
3. Enable it
4. Add your Google Client ID & Secret
5. Save

### Step 3: Test Admin Features

**Create Guard Account:**
1. Go to `/workforce`
2. Click on a guard
3. Use `<GuardAuthManagement />` component (you need to add this to your guard details page)
4. Click "Create Guard Account"
5. Enter email & password
6. ✅ Guard can now login!

**Reset Password:**
1. Open guard details
2. Click "Reset Password"
3. Enter new password
4. Give new credentials to guard

### Step 4: Test Guard Features

**Login:**
- Visit `/guard/login`
- Use email/password or Google
- Redirects to `/guard/dashboard` (you need to create this page)

**Profile:**
- Visit `/guard/profile`
- Upload photo
- Edit bio data
- View documents

---

## 📁 Files Created

```
app/
├── actions/
│   └── guard-auth.ts              ✅ All auth & profile actions
├── api/
│   └── imagekit-auth/
│       └── route.ts               ✅ ImageKit auth API
├── guard/
│   ├── login/
│   │   └── page.tsx               ✅ Login page
│   └── profile/
│       └── page.tsx               ✅ Profile management

components/
├── ImageKitUpload.tsx             ✅ Reusable upload component
└── GuardAuthManagement.tsx        ✅ Admin controls

Database:
├── guards table updates           ✅ Via MCP
└── guard_documents table          ✅ Via MCP
```

---

## 🔐 How It Works

### Admin Creates Guard Account
```
1. Admin clicks "Create Guard Account"
2. Enters email & password
3. System creates auth.users entry
4. Links user_id to guard record
5. Admin gives credentials to guard
```

### Guard Logs In
```
1. Guard visits /guard/login
2. Enters email/password OR clicks Google
3. System verifies account
4. Redirects to dashboard
```

### Guard Uploads Photo
```
1. Guard clicks "Upload Photo"
2. Select file → Preview shown
3. Client calls /api/imagekit-auth
4. API calls edge function for signature
5. Client uploads to ImageKit
6. ImageKit returns URL + fileId
7. Client saves to database via server action
8. ✅ Photo appears in profile
```

### Admin Resets Password
```
1. Guard contacts admin (forgot password)
2. Admin opens guard details
3. Clicks "Reset Password"
4. Enters new password
5. System updates auth.users
6. Admin tells guard new password
```

---

## 🎯 Next Steps

### Immediate
1. **Add environment variables** for ImageKit
2. **Integrate `<GuardAuthManagement/>`** into workforce guard details page
3. **Create `/guard/dashboard`** page
4. **Test guard account creation**
5. **Test profile photo upload**

### Future
- Guard check-in/out terminal
- QR code scanning
- Mobile app (React Native)
- Push notifications

---

## 🧪 Testing

### Test 1: Create Guard Account
```
✓ Go to workforce page
✓ Select a guard
✓ Click "Create Guard Account"
✓ Enter email & password
✓ Verify account created successfully
```

### Test 2: Guard Login
```
✓ Logout from admin
✓ Visit /guard/login
✓ Enter guard credentials
✓ Verify redirect to dashboard
```

### Test 3: Photo Upload
```
✓ Login as guard
✓ Go to /guard/profile
✓ Click "Upload New Photo"
✓ Select image file
✓ Verify upload and preview
✓ Check ImageKit dashboard for file
```

### Test 4: Password Reset
```
✓ Login as admin
✓ Go to guard details
✓ Click "Reset Password"
✓ Enter new password
✓ Logout and test guard login with new password
```

---

## 📝 Notes

- **All photos stored on ImageKit**, not Supabase Storage
- **Guards can only edit their own profile** (enforced by server actions)
- **Admins manage passwords** - guards cannot reset themselves
- **Google OAuth is optional** - email login works standalone
- **RLS policies created but not enabled** - for testing phase

---

## ⚠️ Important

1. **Add ImageKit env vars** - System won't work without them!
2. **Guard Dashboard** - Create this page for after-login redirect
3. **Integrate Admin Component** - Add `<GuardAuthManagement/>  ` to workforce page
4. **Test thoroughly** before enabling RLS

---

## 🆘 Troubleshooting

**Error: "IMAGEKIT_PUBLIC_KEY not defined"**
- Add env vars to `.env.local`
- Restart dev server

**Error: "Not registered as a guard"**
- Make sure guard has user_id linked
- Check guards table in Supabase

**Google login not working**
- Enable Google provider in Supabase
- Add Client ID & Secret
- Configure redirect URLs

**Photo upload fails**
- Check edge function has `IMAGEKIT_PRIVATE_KEY`
- Verify public key in env vars
- Check browser console for errors

---

**Ready to test!** Start with adding ImageKit env vars, then create a guard account.
