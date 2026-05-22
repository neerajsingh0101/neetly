#!/bin/bash
set -euo pipefail

# Build the macOS app icon (.icns) from docs/assets/icon.png.
# Uses sips + iconutil, both built into macOS — no extra tooling needed.

SOURCE="docs/assets/icon.png"
ICONSET="scripts/AppIcon.iconset"
OUTPUT="Sources/NeetlyApp/Resources/AppIcon.icns"

if [ ! -f "$SOURCE" ]; then
    echo "Error: $SOURCE not found"
    exit 1
fi

rm -rf "$ICONSET"
mkdir -p "$ICONSET"

# macOS icons need these sizes: 16, 32, 64, 128, 256, 512, 1024
# with @1x and @2x variants.
sizes=(
    "16:icon_16x16.png"
    "32:icon_16x16@2x.png"
    "32:icon_32x32.png"
    "64:icon_32x32@2x.png"
    "128:icon_128x128.png"
    "256:icon_128x128@2x.png"
    "256:icon_256x256.png"
    "512:icon_256x256@2x.png"
    "512:icon_512x512.png"
    "1024:icon_512x512@2x.png"
)

for entry in "${sizes[@]}"; do
    size="${entry%%:*}"
    name="${entry##*:}"
    echo "Rendering $name at ${size}x${size}"
    sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/$name" >/dev/null
done

echo "Packaging .icns..."
mkdir -p "$(dirname "$OUTPUT")"
iconutil -c icns "$ICONSET" -o "$OUTPUT"

echo "==> Done: $OUTPUT"
