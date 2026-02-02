#!/bin/bash
set -e

echo "🚀 Starting Robust Flutter Web Build..."

# 1. Environment Info
echo "📂 Current Directory: $(pwd)"
echo "🌍 OS: $(uname -a)"

# 2. Install Flutter via Tarball (Reliable & Permanent)
FLUTTER_VERSION="3.29.0" # Latest Stable as of now
FLUTTER_TAR="flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/$FLUTTER_TAR"

if [ ! -d "flutter" ]; then
    echo "📦 Downloading Flutter SDK v$FLUTTER_VERSION..."
    curl -o $FLUTTER_TAR $FLUTTER_URL
    echo "📦 Extracting Flutter..."
    tar xf $FLUTTER_TAR
    rm $FLUTTER_TAR
fi

# 3. Setup PATH
export PATH="$(pwd)/flutter/bin:$PATH"
echo "🔍 Flutter Path: $(which flutter)"

# 4. Configure & Precache
echo "🔧 Configuring Flutter..."
flutter config --no-analytics
flutter config --enable-web
flutter doctor -v

echo "📦 Pre-downloading Web artifacts..."
flutter precache --web

# 5. Clean & Dependencies
echo "🧹 Cleaning previous builds..."
flutter clean

echo "📚 Resolving Dependencies..."
flutter pub get

# 6. The Build
echo "🏗️ Building Flutter Web (Target: lib/main_web.dart)..."
# We remove the renderer flag for a moment to ensure basic build works, 
# then we can add it back if needed. Flutter defaults well.
flutter build web --release --base-href / --target lib/main_web.dart

echo "✅ Build Successful!"
ls -la build/web
