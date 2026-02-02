#!/bin/bash
set -e

echo "🚀 Starting Flutter Web Build..."

# Setup Flutter
if [ ! -d "flutter" ]; then
    echo "📦 Cloning Flutter repository..."
    git clone https://github.com/flutter/flutter.git -b stable --depth 1
fi

export PATH="$PATH:$(pwd)/flutter/bin"

# Pre-download artifacts to avoid network issues during build
echo "📦 Downloading Flutter artifacts..."
flutter precache --web

echo "🔧 Configuring Flutter..."
flutter config --enable-web

echo "📚 Getting dependencies..."
flutter pub get

echo "🏗️ Building Flutter Web..."
flutter build web --release --web-renderer canvaskit --base-href / --target lib/main_web.dart

echo "✅ Build complete! Folder: build/web"
