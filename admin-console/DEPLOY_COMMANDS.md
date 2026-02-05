# 🚀 Quick Deployment Commands

## Step 1: Check Git Status
```bash
cd "c:\Users\ASUS\OneDrive - Manipal University Jaipur\Desktop\Prabhat\JDS MANAGEMENT SAAS\admin-console"
git status
```

## Step 2: Push to GitHub

### If you haven't set up remote yet:
```bash
# Add your GitHub repository
git remote add origin https://github.com/YOUR_USERNAME/voylox-admin.git

# Push to main branch
git push -u origin main
```

### If remote already exists:
```bash
# Just push
git push
```

## Step 3: Deploy to Vercel

### Option A: Vercel Dashboard (Easiest)
1. Go to https://vercel.com
2. Click **"New Project"**
3. **Import Git Repository** → Select your GitHub repo
4. Vercel auto-detects **Next.js**
5. **Add Environment Variables:**
   ```
   NEXT_PUBLIC_SUPABASE_URL=https://fcpbexqyyzdvbiwplmjt.supabase.co
   NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key
   NEXT_PUBLIC_SITE_URL=https://your-project.vercel.app
   NEXT_PUBLIC_IMAGEKIT_PUBLIC_KEY=your_key
   NEXT_PUBLIC_IMAGEKIT_URL_ENDPOINT=https://ik.imagekit.io/your_id
   ```
6. Click **"Deploy"**

### Option B: Vercel CLI
```bash
# Install Vercel CLI globally
npm i -g vercel

# Login to Vercel
vercel login

# Deploy (first time - you'll be prompted for settings)
vercel

# For production deployment
vercel --prod
```

## Step 4: Post-Deployment Setup

### 1. Update Supabase Auth URLs
Go to: **Supabase Dashboard → Authentication → URL Configuration**

Add:
```
Site URL: https://your-project.vercel.app
Redirect URLs:
  https://your-project.vercel.app/auth/callback
  https://your-project.vercel.app/*
```

### 2. Update NEXT_PUBLIC_SITE_URL
In Vercel Dashboard → Settings → Environment Variables:
- Update `NEXT_PUBLIC_SITE_URL` with actual Vercel URL
- Redeploy (Vercel → Deployments → ... → Redeploy)

## ✅ Verify Deployment

Visit your deployed URL and test:
- [ ] Landing page loads (`/`)
- [ ] Click "Login" → Role selector appears
- [ ] Login as Platform Admin works
- [ ] Guard login page accessible
- [ ] ImageKit uploads functional

---

## 📝 Environment Variables Needed

Copy-paste these into Vercel (get values from Supabase & ImageKit dashboards):

```bash
NEXT_PUBLIC_SUPABASE_URL=https://fcpbexqyyzdvbiwplmjt.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=
NEXT_PUBLIC_SITE_URL=
NEXT_PUBLIC_IMAGEKIT_PUBLIC_KEY=
NEXT_PUBLIC_IMAGEKIT_URL_ENDPOINT=
```

---

## 🔧 Troubleshooting

**Build fails?**
- Check all environment variables are set
- Ensure no TypeScript errors locally

**Can't login?**
- Update Supabase redirect URLs
- Clear browser cache/cookies

**Images not loading?**
- Verify ImageKit env vars
- Check `next.config.js` has ImageKit domain

---

## 📊 Current Commit Status

✅ **Committed Files:** 57 files
✅ **Commit Hash:** 8a2e98a
✅ **Message:** "Complete Voylox system - Landing page, guard onboarding, photo attendance, role-based auth"

**Next:** Push to GitHub, then deploy to Vercel!
