#!/bin/bash
set -e

# --- CONFIGURATION ---
FLUTTER_VERSION="3.38.9"
FLUTTER_CHANNEL="stable"
SDK_TAR="flutter_linux_${FLUTTER_VERSION}-${FLUTTER_CHANNEL}.tar.xz"
SDK_URL="https://storage.googleapis.com/flutter_infra_release/releases/${FLUTTER_CHANNEL}/linux/${SDK_TAR}"

echo "🏗️ [CI] Starting Production Web Build..."
echo "📍 Workspace: $(pwd)"

# --- SDK SETUP ---
if [ ! -d "flutter" ]; then
    echo "⬇️ Downloading Flutter SDK v${FLUTTER_VERSION}..."
    curl -o $SDK_TAR $SDK_URL
    echo "📦 Extracting SDK..."
    tar xf $SDK_TAR
    rm $SDK_TAR
fi

# Prepend SDK to path
export PATH="$(pwd)/flutter/bin:$PATH"

echo "🧪 Verifying SDK Environment..."
flutter --version

# --- OPTIMIZATION ---
echo "⚙️ Configuring Build Flags..."
flutter config --no-analytics
flutter precache --web

# --- DEPENDENCIES ---
echo "📚 Resolving Dependencies..."
flutter pub get

# --- BUILD ---
echo "🚀 Compiling Web Assembly & JS..."
# Building web app with environment variables
flutter build web --release \
  --target lib/main_web.dart \
  --dart-define=VITE_SUPABASE_URL="$VITE_SUPABASE_URL" \
  --dart-define=VITE_SUPABASE_ANON_KEY="$VITE_SUPABASE_ANON_KEY"

# --- POST-BUILD ---
echo "✅ Build Completed Successfully."
ls -R build/web | head -n 20
