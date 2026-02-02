#!/bin/bash
set -e

echo "🚀 Starting Flutter Web Build..."

# Setup Flutter
FLUTTER_PATH="$(pwd)/flutter/bin"
export PATH="$FLUTTER_PATH:$PATH"

if [ ! -d "flutter" ]; then
    echo "📦 Cloning Flutter repository (branch: ${FLUTTER_VERSION:-stable})..."
    git clone https://github.com/flutter/flutter.git -b "${FLUTTER_VERSION:-stable}" --depth 1
fi

echo "🔍 Flutter environment info:"
flutter --version
which flutter

echo "🔧 Configuring Flutter..."
flutter config --no-analytics
flutter config --enable-web

echo "📚 Getting dependencies..."
flutter pub get

echo "🏗️ Building Flutter Web..."
# We use the full path to flutter to avoid any ambiguity
# We also try to build without explicit renderer first if this persists, 
# but canvaskit is preferred for the admin panel.
"$(pwd)/flutter/bin/flutter" build web --release --web-renderer canvaskit --base-href / --target lib/main_web.dart

echo "✅ Build complete! Folder: build/web"
ls -la build/web
