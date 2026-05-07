#!/bin/bash
# Generate Resources/AppIcon.icns from Resources/AppIcon.png.
# Requires macOS + Xcode command line tools. No third-party dependencies.
#
# Usage:
#   ./scripts/generate_app_icon.sh
#   ./scripts/generate_app_icon.sh path/to/source.png path/to/output.icns
#   ./scripts/generate_app_icon.sh path/to/output.icns   # backwards-compatible

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

if [[ $# -eq 1 && "$1" == *.icns ]]; then
  SOURCE_PATH="$ROOT_DIR/Resources/AppIcon.png"
  OUT_PATH="$1"
else
  SOURCE_PATH="${1:-$ROOT_DIR/Resources/AppIcon.png}"
  OUT_PATH="${2:-$ROOT_DIR/Resources/AppIcon.icns}"
fi

if [[ ! -f "$SOURCE_PATH" ]]; then
  echo "Missing source PNG: $SOURCE_PATH" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$(dirname "$OUT_PATH")"
ICONSET="$TMP_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"

make_icon() {
  local file="$1"
  local px="$2"
  sips -z "$px" "$px" "$SOURCE_PATH" --out "$ICONSET/$file" >/dev/null
}

make_icon icon_16x16.png 16
make_icon icon_16x16@2x.png 32
make_icon icon_32x32.png 32
make_icon icon_32x32@2x.png 64
make_icon icon_128x128.png 128
make_icon icon_128x128@2x.png 256
make_icon icon_256x256.png 256
make_icon icon_256x256@2x.png 512
make_icon icon_512x512.png 512
make_icon icon_512x512@2x.png 1024

iconutil -c icns "$ICONSET" -o "$OUT_PATH"

echo "Generated $OUT_PATH from $SOURCE_PATH"
