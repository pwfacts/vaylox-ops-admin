# Voylox - Vercel Deployment Guide

## 🚀 Quick Deployment Steps

### 1. Push to GitHub

```bash
# Navigate to admin-console directory
cd "c:\Users\ASUS\OneDrive - Manipal University Jaipur\Desktop\Prabhat\JDS MANAGEMENT SAAS\admin-console"

# Initialize git (if not already)
git init

# Add all files
git add .

# Commit
git commit -m "feat: Complete Voylox security management system with guard onboarding and photo attendance"

# Add remote (replace with your repo URL)
git remote add origin https://github.com/YOUR_USERNAME/voylox-admin.git

# Push to GitHub
git push -u origin main
```

### 2. Deploy to Vercel

**Option A: Via Vercel Dashboard (Recommended)**

1. Go to [vercel.com](https://vercel.com)
2. Click "New Project"
3. Import your GitHub repository
4. Vercel will auto-detect Next.js
5. Add Environment Variables (see below)
6. Click "Deploy"

**Option B: Via Vercel CLI**

```bash
# Install Vercel CLI
npm i -g vercel

# Login
vercel login

# Deploy
vercel
```

---

## 🔐 Environment Variables

Add these in Vercel Dashboard → Project Settings → Environment Variables:

### Required Variables

```bash
# Supabase
NEXT_PUBLIC_SUPABASE_URL=https://fcpbexqyyzdvbiwplmjt.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key_here

# Site URL (Vercel will provide this after first deployment)
NEXT_PUBLIC_SITE_URL=https://your-project.vercel.app

# ImageKit
NEXT_PUBLIC_IMAGEKIT_PUBLIC_KEY=your_public_key
NEXT_PUBLIC_IMAGEKIT_URL_ENDPOINT=https://ik.imagekit.io/your_id
```

**Note:** 
- `IMAGEKIT_PRIVATE_KEY` is already in Supabase Edge Function secrets ✅
- Get your Supabase keys from: Supabase Dashboard → Project Settings → API
- Get ImageKit keys from: ImageKit Dashboard → Developer Options

---

## 📋 Pre-Deployment Checklist

- [x] `.gitignore` configured (excludes `.env*`)
- [x] `next.config.js` has proper image domains
- [x] Environment variables documented
- [x] Database migrations applied in Supabase
- [x] Edge functions deployed
- [ ] Update `NEXT_PUBLIC_SITE_URL` after first deployment
- [ ] Configure Supabase Auth redirect URLs

---

## ⚙️ Post-Deployment Configuration

### 1. Update Supabase Auth URLs

Go to: Supabase Dashboard → Authentication → URL Configuration

Add these URLs:

```
Site URL: https://your-project.vercel.app
Redirect URLs:
  - https://your-project.vercel.app/auth/callback
  - https://your-project.vercel.app/*
```

### 2. Update Environment Variable

After first deployment, update in Vercel:

```bash
NEXT_PUBLIC_SITE_URL=https://your-actual-domain.vercel.app
```

Then redeploy.

### 3. Test Authentication

1. Visit your deployed site
2. Click "Login" → "Select Role"
3. Test Platform Admin login: `prabhatworldtech@gmail.com` / `Admin@123`
4. Verify redirect to `/platform`

---

## 🏗️ Build Configuration

Vercel auto-detects these settings:

```json
{
  "framework": "nextjs",
  "buildCommand": "npm run build",
  "outputDirectory": ".next",
  "installCommand": "npm install",
  "devCommand": "npm run dev"
}
```

---

## 🔍 Troubleshooting

### Build Fails

**Error: "Module not found"**
```bash
# Solution: Ensure all imports use correct paths
# Check: app/(public)/page.tsx exists
```

**Error: "Environment variable not found"**
```bash
# Solution: Add missing env vars in Vercel dashboard
# All NEXT_PUBLIC_* vars must be set before build
```

### Runtime Errors

**Error: "Failed to fetch"**
```bash
# Solution: Check CORS settings in Supabase
# Verify NEXT_PUBLIC_SUPABASE_URL is correct
```

**Error: "ImageKit upload failed"**
```bash
# Solution: Verify ImageKit env vars
# Check edge function has IMAGEKIT_PRIVATE_KEY
```

### Redirect Issues

**Stuck in redirect loop**
```bash
# Solution: Clear browser cookies
# Check middleware.ts logic
# Verify user has proper role assignments
```

---

## 📱 Custom Domain (Optional)

### Add Custom Domain in Vercel

1. Go to Project Settings → Domains
2. Add your domain (e.g., `admin.voylox.com`)
3. Update DNS records as shown by Vercel
4. Update Supabase redirect URLs with new domain

---

## 🎯 Production Optimizations

### Enable These in Vercel:

- ✅ **Compression**: Auto-enabled
- ✅ **Image Optimization**: Auto-enabled
- ✅ **Edge Functions**: Auto-enabled
- ✅ **Analytics**: Enable in project settings

### Environment-Specific Variables

**Production:**
```bash
NEXT_PUBLIC_SITE_URL=https://your-domain.com
```

**Preview (optional):**
```bash
NEXT_PUBLIC_SITE_URL=https://your-preview.vercel.app
```

---

## 🚦 Deployment Status

After deployment, verify:

1. ✅ Landing page loads (`/`)
2. ✅ Role selector works (`/select-role`)
3. ✅ Login redirects properly
4. ✅ Platform admin can access `/platform`
5. ✅ Guard can access `/guard/login`
6. ✅ ImageKit uploads work
7. ✅ Database queries succeed

---

## 📊 Monitoring

### Vercel Analytics

- Real-time visitors
- Performance metrics
- Error tracking

### Supabase Monitoring

- Database queries
- Auth events
- Edge function logs

---

## 🔄 Continuous Deployment

Every push to `main` branch auto-deploys to Vercel!

```bash
# Make changes
git add .
git commit -m "your message"
git push

# Vercel automatically builds and deploys
```

---

## 📝 Important Notes

1. **First Deployment**: Takes ~2-3 minutes
2. **Subsequent Deployments**: ~1 minute
3. **Preview Deployments**: Every PR gets a preview URL
4. **Rollback**: Easy via Vercel dashboard

---

## 🆘 Support

**Vercel Issues:**
- Check: [vercel.com/docs](https://vercel.com/docs)
- Logs: Vercel Dashboard → Deployments → View Function Logs

**Supabase Issues:**
- Check: Supabase Dashboard → Logs
- Edge Functions: Functions → View Logs

**ImageKit Issues:**
- Check: ImageKit Dashboard → Developer Options

---

**Ready to deploy!** 🚀

Run the git commands above to push to GitHub, then deploy via Vercel dashboard.
