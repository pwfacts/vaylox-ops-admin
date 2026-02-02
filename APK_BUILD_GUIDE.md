# 📱 Vaylox Ops - APK Build Guide

## Current Status
The APK build script has been created but requires some setup.

---

## ✅ **EASIEST METHOD: Using Android Studio**

### Prerequisites
- Android Studio installed
- Android SDK configured

### Steps:
1. **Open Android Studio**
2. **Open Project**:
   - File → Open
   - Navigate to: `c:\Users\ASUS\OneDrive - Manipal University Jaipur\Desktop\Prabhat\JDS MANAGEMENT SAAS`
   - Click OK

3. **Wait for Gradle Sync** (this may take 2-5 minutes)

4. **Build APK**:
   - **Method A**: Build → Build Bundle(s) / APK(s) → Build APK(s)
   - **Method B**: Terminal in Android Studio:
     ```bash
     cd android
     gradlew assembleRelease
     ```

5. **Locate APK**:
   ```
   android/app/build/outputs/apk/release/app-release.apk
   ```

---

## 🔧 **ALTERNATIVE: Install Flutter (One-time Setup)**

### Download Flutter
1. Go to: https://docs.flutter.dev/get-started/install/windows
2. Download Flutter SDK (latest stable)
3. Extract to: `C:\flutter`

### Add to PATH
1. Press **Win + X** → System → Advanced system settings
2. Environment Variables → System Variables → Path → Edit
3. New → Add: `C:\flutter\bin`
4. Click OK on all windows

### Verify Installation
Open **NEW** terminal (PowerShell):
```bash
flutter doctor
flutter --version
```

### Build APK
```bash
cd "c:\Users\ASUS\OneDrive - Manipal University Jaipur\Desktop\Prabhat\JDS MANAGEMENT SAAS"
flutter pub get
flutter build apk --release
```

Your APK will be at:
```
build/app/outputs/flutter-apk/app-release.apk
```

---

## 📦 **APK Details**

After successful build, you'll get:

**Filename**: `app-release.apk`  
**Package**: `com.vaylox.app`  
**App Name**: Vaylox Ops  
**Version**: 1.0.0+1  
**Size**: ~35-50 MB  

### APK Features:
✅ Face Recognition Attendance  
✅ GPS-based Check-in  
✅ Offline Sync (SQLite)  
✅ Biometric Security  
✅ Real-time Dashboard  
✅ Salary Slip Viewer  

---

## 🚀 **Distributing Your APK**

### Option 1: Internal Testing
- Share APK file via WhatsApp, Email, or Google Drive
- Users need to enable "Install from Unknown Sources"

### Option 2: Google Play Console (Recommended for Production)
1. Create Google Play Developer account ($25 one-time)
2. Upload APK to Internal Testing track
3. Add tester emails
4. Share test link

### Option 3: Firebase App Distribution
```bash
# Install Firebase CLI
npm install -g firebase-tools

# Deploy to testers
firebase appdistribution:distribute app-release.apk \
  --app YOUR_FIREBASE_APP_ID \
  --groups testers
```

---

## ⚠️ **Troubleshooting**

### Error: "Flutter not found"
- Install Flutter SDK (see above)
- OR use Android Studio method

### Error: "Gradle build failed"
1. Check Android SDK is installed
2. Update Android Studio
3. File → Invalidate Caches → Restart

### Error: "Signing key not configured"
For production release, you need a keystore:
```bash
keytool -genkey -v -keystore vaylox-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias vaylox
```

Then update `android/app/build.gradle.kts`:
```kotlin
signingConfigs {
    create("release") {
        storeFile = file("../../vaylox-release.jks")
        storePassword = "your_password"
        keyAlias = "vaylox"
        keyPassword = "your_password"
    }
}
```

---

## 📊 **What's Next?**

1. ✅ **Build APK** (current step)
2. **Test on Device** (install and verify)
3. **Gather Feedback** (from guards/supervisors)
4. **Iterate** (fix bugs, add features)
5. **Play Store Release** (public launch)

---

## 🎯 **Quick Commands Reference**

```bash
# Get dependencies
flutter pub get

# Run on connected device
flutter run

# Build release APK
flutter build apk --release

# Build app bundle (for Play Store)
flutter build appbundle --release

# Clean build
flutter clean
```

---

**Need help? The easiest path is Android Studio → Build → Build APK. It handles everything automatically!**
