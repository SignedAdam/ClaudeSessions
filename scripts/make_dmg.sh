#!/bin/bash
# Build Claude Sessions as a release .app bundle, zip it, and package a DMG.
#
# Usage: ./scripts/make_dmg.sh [version]
#   version: optional, e.g. "0.1.0". Defaults to a date stamp.
#
# Output:
#   build/Claude Sessions.app
#   build/Claude-Sessions-<version>.zip
#   build/Claude-Sessions-<version>.dmg
#   build/SHA256SUMS.txt
#
# Requirements: macOS, Xcode command line tools (Swift 5.9+), hdiutil.
# No fastlane. No create-dmg. No ceremony.

set -euo pipefail

VERSION="${1:-$(date +%Y%m%d)}"
APP_NAME="Claude Sessions"
BUNDLE_ID="com.signedadam.claude-sessions"
MAIN_EXEC="ClaudeSessions"
AGENT_EXEC="ClaudeSessionsBackupAgent"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
DMG_PATH="$BUILD_DIR/Claude-Sessions-$VERSION.dmg"
ZIP_PATH="$BUILD_DIR/Claude-Sessions-$VERSION.zip"
SUMS_PATH="$BUILD_DIR/SHA256SUMS.txt"
ICON_PATH="$ROOT_DIR/Resources/AppIcon.icns"

build_swift() {
  echo "==> Building release binaries"
  cd "$ROOT_DIR"

  if [[ "${CURRENT_ARCH_ONLY:-0}" == "1" ]]; then
    swift build -c release
    return
  fi

  if swift build -c release --arch arm64 --arch x86_64; then
    return
  fi

  if [[ "${ALLOW_SINGLE_ARCH_FALLBACK:-1}" == "1" ]]; then
    echo "==> Universal build failed; falling back to current architecture"
    swift build -c release
  else
    echo "Universal build failed. Set CURRENT_ARCH_ONLY=1 for a local single-arch build."
    exit 1
  fi
}

binary_path() {
  local name="$1"
  local candidates=(
    "$ROOT_DIR/.build/apple/Products/Release/$name"
    "$ROOT_DIR/.build/release/$name"
    "$ROOT_DIR/.build/arm64-apple-macosx/release/$name"
    "$ROOT_DIR/.build/x86_64-apple-macosx/release/$name"
  )

  for p in "${candidates[@]}"; do
    if [[ -f "$p" ]]; then
      echo "$p"
      return 0
    fi
  done

  echo "Could not find built binary for $name. Looked at:" >&2
  printf '  %s\n' "${candidates[@]}" >&2
  return 1
}

write_info_plist() {
  cat > "$APP_DIR/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>$MAIN_EXEC</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
}

echo "==> Cleaning build/"
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

if [[ ! -f "$ICON_PATH" ]]; then
  echo "==> Generating app icon"
  "$ROOT_DIR/scripts/generate_app_icon.sh" "$ICON_PATH"
fi

build_swift
MAIN_BINARY="$(binary_path "$MAIN_EXEC")"
AGENT_BINARY="$(binary_path "$AGENT_EXEC")"

echo "==> Assembling $APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$MAIN_BINARY" "$APP_DIR/Contents/MacOS/$MAIN_EXEC"
cp "$AGENT_BINARY" "$APP_DIR/Contents/MacOS/$AGENT_EXEC"
chmod +x "$APP_DIR/Contents/MacOS/$MAIN_EXEC" "$APP_DIR/Contents/MacOS/$AGENT_EXEC"
cp "$ICON_PATH" "$APP_DIR/Contents/Resources/AppIcon.icns"
write_info_plist

if [[ -d "$ROOT_DIR/Resources" ]]; then
  find "$ROOT_DIR/Resources" -maxdepth 1 -type f ! -name 'AppIcon.icns' -exec cp {} "$APP_DIR/Contents/Resources/" \;
fi

echo "==> Ad-hoc signing"
codesign --force --deep --sign - "$APP_DIR"

echo "==> Building ZIP"
cd "$BUILD_DIR"
ditto -c -k --keepParent "$APP_NAME.app" "$ZIP_PATH"

echo "==> Building DMG"
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

rm -rf "$STAGE_DIR"

shasum -a 256 "$DMG_PATH" "$ZIP_PATH" > "$SUMS_PATH"

echo
echo "Done."
echo "  App:  $APP_DIR"
echo "  DMG:  $DMG_PATH"
echo "  ZIP:  $ZIP_PATH"
echo "  Sums: $SUMS_PATH"
echo
echo "Release locally:"
echo "  gh release create v$VERSION '$DMG_PATH' '$ZIP_PATH' '$SUMS_PATH' --title 'v$VERSION' --notes 'Claude Sessions $VERSION'"
