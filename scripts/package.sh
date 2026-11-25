#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="0.2.0-beta"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:--}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$ROOT_DIR/build/ClipVoice.app"
ZIP_PATH="$DIST_DIR/ClipVoice-$VERSION-macos-universal.zip"
DMG_PATH="$DIST_DIR/ClipVoice-$VERSION-macos-universal.dmg"
DMG_STAGE="$ROOT_DIR/build/dmg-staging"

CODESIGN_IDENTITY="$CODESIGN_IDENTITY" "$ROOT_DIR/scripts/build.sh"

echo "==> Auditing distributables for leaked machine paths or clipboard data..."
for bin in "$APP_DIR/Contents/MacOS/ClipVoice" "$APP_DIR/Contents/MacOS/clipvoice-cli" "$APP_DIR/Contents/MacOS/clipvoice-mcp"; do
    if strings "$bin" | grep -q "/Users/"; then
        echo "WARNING: Found /Users/ path string inside $bin" >&2
        strings "$bin" | grep "/Users/" | head -n 5 >&2 || true
        exit 1
    fi
done

rm -rf "$DIST_DIR" "$DMG_STAGE"
mkdir -p "$DIST_DIR" "$DMG_STAGE"

echo "==> Packaging ZIP archive..."
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

if [[ -n "$NOTARY_PROFILE" && "$CODESIGN_IDENTITY" != "-" ]]; then
    echo "==> Submitting ClipVoice.app ZIP for Apple notarization (profile: $NOTARY_PROFILE)..."
    xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "==> Stapling notarization ticket to ClipVoice.app..."
    xcrun stapler staple "$APP_DIR"
    xcrun stapler validate "$APP_DIR"
    rm -f "$ZIP_PATH"
    echo "==> Re-packaging stapled ZIP archive..."
    ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"
fi

echo "==> Packaging DMG disk image..."
cp -R "$APP_DIR" "$DMG_STAGE/ClipVoice.app"
ln -s /Applications "$DMG_STAGE/Applications"
cp -R "$ROOT_DIR/skills/clipvoice" "$DMG_STAGE/clipvoice-skill"
cp "$ROOT_DIR/LICENSE" "$DMG_STAGE/LICENSE.txt"

if [[ -n "$NOTARY_PROFILE" && "$CODESIGN_IDENTITY" != "-" ]]; then
    SIGNING_NOTE="2. Developer ID signed and Apple notarized — launch normally from Applications."
else
    SIGNING_NOTE="2. First launch (ad-hoc signed beta):
   Right-click ClipVoice.app -> Open (or run: xattr -dr com.apple.quarantine /Applications/ClipVoice.app)."
fi

cat > "$DMG_STAGE/INSTALL.txt" <<EOF
ClipVoice $VERSION (macOS Universal arm64 + x86_64)

1. Drag ClipVoice.app into Applications.
$SIGNING_NOTE
3. MCP binary path:
   /Applications/ClipVoice.app/Contents/MacOS/clipvoice-mcp
4. CLI binary path:
   /Applications/ClipVoice.app/Contents/MacOS/clipvoice-cli
5. Install agent skill:
   /Applications/ClipVoice.app/Contents/MacOS/clipvoice-cli install-skill --target codex
EOF

hdiutil create \
    -volname "ClipVoice $VERSION" \
    -srcfolder "$DMG_STAGE" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_STAGE"

if [[ "$CODESIGN_IDENTITY" != "-" ]]; then
    echo "==> Signing DMG ($CODESIGN_IDENTITY)..."
    codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"
fi

if [[ -n "$NOTARY_PROFILE" && "$CODESIGN_IDENTITY" != "-" ]]; then
    echo "==> Submitting DMG for Apple notarization (profile: $NOTARY_PROFILE)..."
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    echo "==> Stapling notarization ticket to DMG..."
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
    echo "==> Verifying Gatekeeper assessments..."
    spctl -a -t exec -vv "$APP_DIR"
    spctl -a -t open --context context:primary-signature -vv "$DMG_PATH"
fi

echo "==> Generating SHA256SUMS.txt..."
(
    cd "$DIST_DIR"
    shasum -a 256 "$(basename "$DMG_PATH")" "$(basename "$ZIP_PATH")" > SHA256SUMS.txt
)

echo "==> Packaged artifacts in $DIST_DIR:"
ls -lh "$DIST_DIR"
cat "$DIST_DIR/SHA256SUMS.txt"
