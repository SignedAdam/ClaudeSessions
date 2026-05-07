#!/bin/bash
# Generate Resources/AppIcon.icns from the programmatic Swift icon.
# Requires macOS + Xcode command line tools. No third-party dependencies.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_PATH="${1:-$ROOT_DIR/Resources/AppIcon.icns}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$(dirname "$OUT_PATH")"
ICONSET="$TMP_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"

cat > "$TMP_DIR/main.swift" <<'SWIFT'
import AppKit
import Foundation

func writePNG(_ image: NSImage, to path: String) throws {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let data = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconGen", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }
    try data.write(to: URL(fileURLWithPath: path))
}

let iconset = CommandLine.arguments[1]
let files: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, size) in files {
    let image = AppIcon.makeImage(size: size)
    try writePNG(image, to: URL(fileURLWithPath: iconset).appendingPathComponent(name).path)
}
SWIFT

swiftc \
  "$ROOT_DIR/Sources/ClaudeSessions/Utilities/AppIcon.swift" \
  "$TMP_DIR/main.swift" \
  -o "$TMP_DIR/icon-gen"

"$TMP_DIR/icon-gen" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$OUT_PATH"

echo "Generated $OUT_PATH"
