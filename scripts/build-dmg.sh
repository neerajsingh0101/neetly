#!/bin/bash
set -euo pipefail

VERSION="${1:-1.0.0}"
VARIANT="${2:-stable}"

echo "==> Building release..."
swift build -c release

BUILD_DIR=".build/arm64-apple-macosx/release"

# Stable and beta differ only in bundle identity, update feed, and terminal
# engine — so the beta installs side-by-side with a tester's stable Neetly.
if [ "$VARIANT" = "beta" ]; then
    APP_NAME="Neetly Beta"
    BUNDLE_ID="com.neetly.app.beta"
    DISPLAY_NAME="Neetly Beta"
    DMG_NAME="neetly-beta-macos.dmg"
    VOL_NAME="Neetly Beta"
    FEED_URL="https://github.com/neetozone/neetly/releases/download/beta/appcast-beta.xml"
elif [ "$VARIANT" = "stable" ]; then
    APP_NAME="neetly"
    BUNDLE_ID="com.neetly.app"
    DISPLAY_NAME="neetly"
    DMG_NAME="neetly-macos.dmg"
    VOL_NAME="neetly"
    FEED_URL="https://github.com/neetozone/neetly/releases/latest/download/appcast.xml"
else
    echo "ERROR: unknown variant '$VARIANT' (expected 'stable' or 'beta')" >&2
    exit 1
fi

APP_DIR=".build/${APP_NAME}.app"
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
SPARKLE_FRAMEWORK=$(find .build -name "Sparkle.framework" -type d 2>/dev/null | head -1)

echo "==> Creating ${APP_NAME}.app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"
mkdir -p "$FRAMEWORKS_DIR"

# Copy binaries
cp "$BUILD_DIR/neetly-app" "$APP_DIR/Contents/MacOS/neetly-app"
cp "$BUILD_DIR/neetly" "$APP_DIR/Contents/MacOS/neetly"

# Copy SwiftPM-generated resource bundles (what Bundle.module resolves to).
# Without this, Bundle.module traps at launch with an assertion failure.
for bundle in "$BUILD_DIR"/*.bundle; do
    [ -e "$bundle" ] || continue
    echo "==> Copying resource bundle: $(basename "$bundle")"
    cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done

# Copy app icon
ICON_SRC="Sources/NeetlyApp/Resources/AppIcon.icns"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP_DIR/Contents/Resources/AppIcon.icns"
else
    echo "==> WARNING: $ICON_SRC not found; run scripts/build-icon.sh first"
fi

# Copy Sparkle framework if found
if [ -n "$SPARKLE_FRAMEWORK" ] && [ -d "$SPARKLE_FRAMEWORK" ]; then
    echo "==> Copying Sparkle.framework from $SPARKLE_FRAMEWORK"
    cp -R "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/"

    # SPM doesn't add the @loader_path/../Frameworks rpath automatically.
    # The executable links @rpath/Sparkle.framework/... so we need to tell dyld
    # to look in Contents/Frameworks/ relative to the executable.
    echo "==> Adding @loader_path/../Frameworks rpath to executable"
    install_name_tool -add_rpath "@loader_path/../Frameworks" "$APP_DIR/Contents/MacOS/neetly-app" 2>&1 || true
else
    echo "==> WARNING: Sparkle.framework not found"
fi

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>neetly-app</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>SUFeedURL</key>
    <string>${FEED_URL}</string>
    <key>SUPublicEDKey</key>
    <string>L0ljaNTkCDOrcaLiMg8NIPHt+XLj5dr+Fp4dZ9AmsR8=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
</dict>
</plist>
PLIST

# Re-sign the whole .app ad-hoc so the outer bundle has a proper
# _CodeSignature/CodeResources manifest (linker-signed leaves the bundle
# resources unsealed, which interacts badly with translocation on some Macs).
echo "==> Re-signing app bundle ad-hoc..."
codesign --force --deep --sign - "$APP_DIR"

echo "==> Creating DMG..."
rm -f "$DMG_NAME"
hdiutil create -volname "$VOL_NAME" \
    -srcfolder "$APP_DIR" \
    -ov -format UDZO \
    "$DMG_NAME"

echo "==> Done: $DMG_NAME"
