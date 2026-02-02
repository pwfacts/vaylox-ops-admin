@echo off
echo ========================================
echo Vaylox Ops - APK Builder
echo ========================================
echo.

REM Navigate to android directory
cd android

echo [1/3] Cleaning previous builds...
call gradlew clean

echo [2/3] Building release APK...
call gradlew assembleRelease

echo [3/3] Build complete!
echo.
echo ========================================
echo APK Location:
echo app\build\outputs\apk\release\app-release.apk
echo ========================================
pause
