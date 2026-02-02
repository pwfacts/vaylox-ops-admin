#!/bin/bash
set -e

echo "🚀 Starting Flutter Web Build..."

# Setup Flutter
# We prepend the path to ensure our version takes priority over any system-installed version
export PATH="$(pwd)/flutter/bin:$PATH"

if [ ! -d "flutter" ]; then
    echo "📦 Cloning Flutter repository..."
    # If FLUTTER_VERSION is set, use it. Otherwise, use stable.
    if [ -n "$FLUTTER_VERSION" ]; then
        echo "   Targeting version: $FLUTTER_VERSION"
        git clone https://github.com/flutter/flutter.git -b "$FLUTTER_VERSION" --depth 1
    else
        echo "   Targeting stable branch"
        git clone https://github.com/flutter/flutter.git -b stable --depth 1
    fi
fi

echo "🔍 Checking Flutter version..."
flutter --version

# Pre-download artifacts to avoid network issues during build
echo "📦 Downloading Flutter artifacts..."
flutter precache --web

echo "🔧 Configuring Flutter..."
flutter config --enable-web

echo "📚 Getting dependencies..."
flutter pub get

echo "🏗️ Building Flutter Web..."
# Using the main_web.dart as entry point for the Admin Portal
# If --web-renderer fails, it's usually because the Flutter version is too old
# but since we're cloning stable/3.10.4+, it should work.
flutter build web --release --web-renderer canvaskit --base-href / --target lib/main_web.dart

echo "✅ Build complete! Folder: build/web"
