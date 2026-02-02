# 🔐 GitHub Secrets Setup for Vercel Deployment

## Quick Setup Guide

### Step 1: Go to GitHub Secrets Page

Open this URL in your browser:
```
https://github.com/pwfacts/vaylox-ops-admin/settings/secrets/actions
```

(Or navigate: Repository → Settings → Secrets and variables → Actions)

---

### Step 2: Add VERCEL_TOKEN

1. Click **"New repository secret"**
2. **Name**: `VERCEL_TOKEN`
3. **Value**: `zcGc0vsFt9jAcHxoltBsZLu5`
4. Click **"Add secret"**

---

### Step 3: Get Vercel Organization ID

1. Go to: https://vercel.com/account
2. Click on your organization/team
3. Go to **Settings**
4. Copy your **Organization ID** (looks like: `team_xxxxxxxxxxxx`)

**Then add to GitHub:**
- **Name**: `VERCEL_ORG_ID`
- **Value**: (paste your org ID)

---

### Step 4: Get Vercel Project ID

#### Option A: From Vercel Dashboard
1. Go to: https://vercel.com/dashboard
2. Click on your `vaylox-ops-admin` project
3. Go to **Settings**
4. Copy **Project ID** (looks like: `prj_xxxxxxxxxxxx`)

#### Option B: Create New Project First
If you haven't created the Vercel project yet:

1. Go to: https://vercel.com/new
2. Import `vaylox-ops-admin` from GitHub
3. Configure:
   - **Framework**: Other
   - **Root Directory**: `web`
   - Skip build settings for now
4. Click **"Deploy"** (it will fail, that's okay!)
5. Go to **Settings** → Copy **Project ID**

**Then add to GitHub:**
- **Name**: `VERCEL_PROJECT_ID`
- **Value**: (paste your project ID)

---

### Step 5: Verify Secrets

You should now have **3 secrets**:
- ✅ `VERCEL_TOKEN`: zcGc0vsFt9jAcHxoltBsZLu5
- ✅ `VERCEL_ORG_ID`: team_xxxxxxxxxxxx
- ✅ `VERCEL_PROJECT_ID`: prj_xxxxxxxxxxxx

---

### Step 6: Trigger Deployment

Once all secrets are added:

```bash
# Make a small change to trigger deployment
git commit --allow-empty -m "Trigger GitHub Actions deployment"
git push
```

Then:
1. Go to: https://github.com/pwfacts/vaylox-ops-admin/actions
2. Watch the build process live!
3. It will take ~5-10 minutes
4. Once done, your Flutter Web admin will be live!

---

## 🎯 Alternative: Use Simple HTML Admin (Instant!)

If GitHub Actions seems complex, you can skip all this and:

1. Go to Vercel: https://vercel.com/new
2. Import repository
3. Set **Root Directory**: `web`
4. Deploy!
5. Access: `https://YOUR-PROJECT.vercel.app/admin.html`

**The HTML admin is ready NOW and works perfectly!**

---

## 📞 Need My Help?

Tell me:
1. Do you want to use **GitHub Actions** (full Flutter) or **HTML Admin** (simple)?
2. Share your Vercel Organization ID and Project ID if you need help adding them to GitHub.

Choose whichever is easier! Both work great 🚀
