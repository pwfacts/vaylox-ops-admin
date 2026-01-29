#!/bin/bash

# Vercel Build Script for Flutter Web

echo "🚀 Starting Flutter Web Build for Vaylox Ops Admin..."

# Install Flutter if not available
if ! command -v flutter &> /dev/null; then
    echo "📦 Installing Flutter..."
    git clone https://github.com/flutter/flutter.git -b stable --depth 1
    export PATH="$PATH:`pwd`/flutter/bin"
fi

# Get Flutter version
flutter --version

# Enable web support
flutter config --enable-web

# Get dependencies
echo "📚 Getting dependencies..."
flutter pub get

# Build for web with custom entry point
echo "🏗️ Building Flutter Web..."
flutter build web --release --web-renderer canvaskit --base-href / --target lib/main_web.dart

echo "✅ Build complete! Output in build/web"
