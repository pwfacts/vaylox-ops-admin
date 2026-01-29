# Vaylox Ops - Admin Web Portal

## 🚀 Deploying to Vercel

### Prerequisites
- GitHub account
- Vercel account (free tier works!)
- Your Flutter project pushed to GitHub

### Step-by-Step Deployment Guide

#### 1️⃣ **Push to GitHub**
```bash
# Initialize git (if not already done)
git init

# Add all files
git add .

# Commit
git commit -m "Initial commit: Vaylox Ops Admin Portal"

# Add your GitHub repository
git remote add origin https://github.com/YOUR_USERNAME/vaylox-ops-admin.git

# Push
git push -u origin main
```

#### 2️⃣ **Connect to Vercel**
1. Go to [vercel.com](https://vercel.com) and sign in with GitHub
2. Click **"Add New Project"**
3. Import your `vaylox-ops-admin` repository
4. Vercel will auto-detect the `vercel.json` configuration

#### 3️⃣ **Configure Build Settings** (Auto-detected)
- **Build Command**: `chmod +x build.sh && ./build.sh`
- **Output Directory**: `build/web`
- **Install Command**: (leave empty, handled by build script)

#### 4️⃣ **Add Environment Variables** (Optional)
If you want to use different Supabase credentials for web:
- `SUPABASE_URL`: Your Supabase project URL
- `SUPABASE_ANON_KEY`: Your Supabase anon key

#### 5️⃣ **Deploy!**
Click **"Deploy"** and wait 3-5 minutes for the build to complete.

### 🎯 What Gets Deployed

The web version includes:
- ✅ **Executive Dashboard** - Real-time analytics and KPIs
- ✅ **Payroll Wizard** - Complete salary calculation interface
- ✅ **Guard Management** - View and manage all guards
- ✅ **Bulk Attendance** - Mark multiple guards at once
- ✅ **Attendance Approvals** - Review and approve pending attendance
- ✅ **System Settings** - Configure payroll rules
- ✅ **Audit Logs** - Track all system activities
- ✅ **Data Archives** - Secure backup management

### 🔒 Security Features
- Email/Password authentication via Supabase
- Role-based access control (admin-only features)
- Secure HTTPS by default on Vercel
- Client-side encryption for sensitive data

### 📱 Excluded Features (Mobile-Only)
- Face recognition (camera not needed for admin)
- GPS-based attendance (field guard feature)
- Offline SQLite sync (web uses direct Supabase)

### 🌐 Access Your Portal
After deployment, Vercel will give you:
- **Production URL**: `https://vaylox-ops-admin.vercel.app`
- **Preview URLs**: For every new commit

### 🔄 Continuous Deployment
Every push to `main` branch will auto-deploy to production!

### 🛠️ Local Testing
To test the web version locally:
```bash
flutter run -d chrome --target lib/main_web.dart
```

---

## 📞 Need Help?
If the build fails, check:
1. All dependencies are compatible with web (most are!)
2. No mobile-specific plugins are imported in web code
3. Build script has execute permissions

**Your admin portal is now live and accessible from anywhere! 🎉**
