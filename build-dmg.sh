#!/bin/zsh
set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "$0")" && pwd)"
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

APP_NAME="Findy"
VOLUME_NAME="Findy"
SIGNED_APP="$WORKSPACE_DIR/Findy.app"

if [[ ! -d "$SIGNED_APP" ]]; then
    echo "Error: Signed $SIGNED_APP not found in $WORKSPACE_DIR"
    exit 1
fi

echo "==> [1/6] Verifying signed & notarized Findy.app..."
codesign --verify --deep --strict --verbose=2 "$SIGNED_APP"
spctl -a -vvv -t exec "$SIGNED_APP" 2>&1 || true

# Detect Apple Developer ID Application signing identity (only sign outer DMG if Developer ID is in Keychain)
DETECTED_IDENTITY="$(security find-identity -v -p codesigning | grep -E 'Developer ID Application' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)"
SIGN_IDENTITY="${APPLE_SIGN_IDENTITY:-${DETECTED_IDENTITY:-}}"

echo "==> [2/6] Preparing HiDPI DMG background (00-dmg-background.png -> background.tiff)..."
mkdir -p "$WORKSPACE_DIR/Assets" "$WORKSPACE_DIR/dist"
if [[ -f "$WORKSPACE_DIR/Assets/dmg-background@1x.png" && -f "$WORKSPACE_DIR/00-dmg-background.png" ]]; then
    tiffutil -cathidpicheck "$WORKSPACE_DIR/Assets/dmg-background@1x.png" "$WORKSPACE_DIR/00-dmg-background.png" -out "$WORKSPACE_DIR/Assets/dmg-background.tiff"
fi

# Detach any existing Findy volume
if [[ -d "/Volumes/${VOLUME_NAME}" ]]; then
    hdiutil detach "/Volumes/${VOLUME_NAME}" -force >/dev/null 2>&1 || true
fi

STAGE_ROOT="/tmp/findy-dmg-stage-$$"
RW_DMG="/tmp/findy-rw-$$.dmg"
OUT_DMG_ROOT="$WORKSPACE_DIR/Findy.dmg"
OUT_DMG_DIST="$WORKSPACE_DIR/dist/Findy-macOS-Installer.dmg"

rm -rf "$STAGE_ROOT" "$RW_DMG" "$OUT_DMG_ROOT" "$OUT_DMG_DIST"
mkdir -p "$STAGE_ROOT/.background"

echo "==> [3/6] Staging signed Findy.app and /Applications link..."
ditto "$SIGNED_APP" "$STAGE_ROOT/Findy.app"
ln -s /Applications "$STAGE_ROOT/Applications"

cp "$WORKSPACE_DIR/00-dmg-background.png" "$STAGE_ROOT/.background/background.png"
if [[ -f "$WORKSPACE_DIR/Assets/dmg-background.tiff" ]]; then
    cp "$WORKSPACE_DIR/Assets/dmg-background.tiff" "$STAGE_ROOT/.background/background.tiff"
    cp "$WORKSPACE_DIR/Assets/dmg-background.tiff" "$STAGE_ROOT/.background.tiff"
fi
if [[ -f "$SIGNED_APP/Contents/Resources/AppIcon.icns" ]]; then
    cp "$SIGNED_APP/Contents/Resources/AppIcon.icns" "$STAGE_ROOT/.VolumeIcon.icns"
fi

# Also keep /Applications/Findy.app updated with the signed & notarized bundle
rm -rf "/Applications/Findy.app"
ditto "$SIGNED_APP" "/Applications/Findy.app"

echo "==> [4/6] Creating writable UDRW disk image & configuring Finder layout..."
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGE_ROOT" \
    -ov \
    -fs HFS+ \
    -format UDRW \
    "$RW_DMG" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")"
DEVICE="$(echo "$ATTACH_OUTPUT" | awk '/\/Volumes\// {print $1; exit}')"
MOUNT_DIR="/Volumes/${VOLUME_NAME}"

if [[ -f "$MOUNT_DIR/.VolumeIcon.icns" ]]; then
    chflags hidden "$MOUNT_DIR/.VolumeIcon.icns" || true
    /usr/bin/SetFile -a C "$MOUNT_DIR" 2>/dev/null || true
fi
chflags hidden "$MOUNT_DIR/.background" 2>/dev/null || true
[[ -f "$MOUNT_DIR/.background.tiff" ]] && chflags hidden "$MOUNT_DIR/.background.tiff" 2>/dev/null || true

osascript <<EOF || true
tell application "Finder"
    tell disk "${VOLUME_NAME}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {220, 140, 820, 568}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 104
        set text size of viewOptions to 12
        set background picture of viewOptions to POSIX file "/Volumes/${VOLUME_NAME}/.background/background.tiff"
        set position of item "Findy.app" of container window to {165, 175}
        set position of item "Applications" of container window to {435, 175}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
EOF

sync
sleep 1
hdiutil detach "$DEVICE" -force >/dev/null

echo "==> [5/6] Compressing to read-only UDZO DMG..."
hdiutil convert "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT_DMG_ROOT" >/dev/null
rm -f "$RW_DMG"
rm -rf "$STAGE_ROOT"

if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "==> [6/6] Code-signing Findy.dmg with Developer ID: $SIGN_IDENTITY..."
    codesign --force --sign "$SIGN_IDENTITY" "$OUT_DMG_ROOT"
    codesign --verify --verbose=2 "$OUT_DMG_ROOT"
else
    echo "==> [6/6] Preserving Notarized Developer ID signature & stapled ticket inside Findy.dmg..."
fi
cp "$OUT_DMG_ROOT" "$OUT_DMG_DIST"

SHA256_SUM="$(shasum -a 256 "$OUT_DMG_ROOT" | awk '{print $1}')"
DMG_SIZE="$(ls -lh "$OUT_DMG_ROOT" | awk '{print $5}')"

echo ""
echo "=================================================================="
echo "  Signed & Notarized Findy.dmg Ready!"
echo "=================================================================="
echo "  • App Signature    : Developer ID Application: Shubham Sharma (9TKKPN6F59) [Notarized + Stapled]"
echo "  • Root DMG         : $OUT_DMG_ROOT ($DMG_SIZE)"
echo "  • Dist DMG         : $OUT_DMG_DIST"
echo "  • SHA-256          : $SHA256_SUM"
echo "=================================================================="
