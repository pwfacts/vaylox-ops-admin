# 🚀 Netlify Deployment Guide - JDS Management Admin

Since Vercel is having issues, Netlify is a great alternative for hosting the Flutter Web version of your Admin Portal.

## ✅ Prerequisites
1. A GitHub account with your project pushed to it.
2. A [Netlify account](https://app.netlify.com/) (Free tier is fine).

## 🛠️ Step-by-Step Setup

### 1. Update your code
Make sure you have the `netlify.toml` file in your root directory (I have already created it for you).

### 2. Connect to Netlify
1. Log in to your **Netlify Dashboard**.
2. Click **"Add new site"** -> **"Import an existing project"**.
3. Select **GitHub**.
4. Search for and select your repository (`vaylox-ops-admin`).

### 3. Build Settings (Auto-detected)
Netlify should automatically detect the settings from `netlify.toml`, but here they are just in case:
- **Build Command**: `chmod +x build.sh && ./build.sh`
- **Publish Directory**: `build/web`

### 4. Deploy!
1. Click **"Deploy site"**.
2. Deployment will take about 5-8 minutes because it needs to install Flutter first.
3. Once finished, Netlify will provide you with a `.netlify.app` URL.

---

## 🔒 Handling Login issues in APK
I have fixed the issue where the "Login Default Account" button was doing nothing.
1. I added a sign-in handler in `lib/main.dart`.
2. **IMPORTANT**: Open `lib/main.dart` and update the email and password in the `_login` function to your actual default credentials:
   ```dart
   // Change these in lib/main.dart:
   email: 'admin@jaydurga.com', 
   password: 'password123',
   ```

## 📱 Re-building the APK
To get a working APK with the fix:
1. Run `flutter clean`
2. Run `flutter build apk --debug` 

---

## 🔧 Troubleshooting Netlify Build
If the build fails on Netlify:
1. Check the **Deploy Logs**.
2. Ensure `build.sh` is in your repository.
3. If you get a "command not found" for `chmod`, it's usually a platform issue, but Netlify's Linux environment supports it.

Your Admin Portal is ready to go live on Netlify! 🎉
