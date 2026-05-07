#!/bin/bash
# Build Claude Sessions as a release .app bundle and package it as a .dmg.
#
# Usage: ./scripts/make_dmg.sh [version]
#   version: optional, e.g. "0.1.0". Defaults to a date stamp.
#
# Output: build/Claude-Sessions-<version>.dmg
#
# Requirements: macOS, Xcode command line tools (Swift 5.9+), hdiutil.
# No external tools needed (no create-dmg, no fastlane).

set -euo pipefail

VERSION="${1:-$(date +%Y%m%d)}"
APP_NAME="Claude Sessions"
BUNDLE_ID="com.signedadam.claude-sessions"
EXEC_NAME="ClaudeSessions"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PKG_DIR="$ROOT_DIR/ClaudeSessions"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/Claude-Sessions-$VERSION.dmg"

echo "==> Cleaning"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Building release binary"
cd "$PKG_DIR"
swift build -c release --arch arm64 --arch x86_64

# SwiftPM puts a universal binary at this path when both arches are requested.
BINARY_PATH="$PKG_DIR/.build/apple/Products/Release/$EXEC_NAME"
if [ ! -f "$BINARY_PATH" ]; then
  # Fall back to single-arch path.
  BINARY_PATH="$PKG_DIR/.build/release/$EXEC_NAME"
fi
if [ ! -f "$BINARY_PATH" ]; then
  echo "Could not find built binary. Looked at:"
  echo "  $PKG_DIR/.build/apple/Products/Release/$EXEC_NAME"
  echo "  $PKG_DIR/.build/release/$EXEC_NAME"
  exit 1
fi

echo "==> Assembling .app bundle at $APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/$EXEC_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$EXEC_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$EXEC_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
</dict>
</plist>
EOF

# Ad-hoc sign so macOS doesn't immediately quarantine it on first launch.
echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP_DIR"

echo "==> Building DMG at $DMG_PATH"
# Stage a folder with the .app and an /Applications shortcut so the
# user can drag-to-install in the standard way.
STAGE_DIR="$BUILD_DIR/stage"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_DIR" "$STAGE_DIR/"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo
echo "Done."
echo "  App:  $APP_DIR"
echo "  DMG:  $DMG_PATH"
echo
echo "Upload the DMG to a GitHub Release:"
echo "  gh release create v$VERSION '$DMG_PATH' --title 'v$VERSION' --notes 'See README for known issues.'"
