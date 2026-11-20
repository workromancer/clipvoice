#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="0.1.1-beta"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$ROOT_DIR/build/ClipVoice.app"
ZIP_PATH="$DIST_DIR/ClipVoice-$VERSION-macos-universal.zip"
DMG_PATH="$DIST_DIR/ClipVoice-$VERSION-macos-universal.dmg"
DMG_STAGE="$ROOT_DIR/build/dmg-staging"

"$ROOT_DIR/scripts/build.sh"

rm -rf "$DIST_DIR" "$DMG_STAGE"
mkdir -p "$DIST_DIR" "$DMG_STAGE"

echo "==> Packaging ZIP archive..."
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo "==> Packaging DMG disk image..."
cp -R "$APP_DIR" "$DMG_STAGE/ClipVoice.app"
ln -s /Applications "$DMG_STAGE/Applications"
cp -R "$ROOT_DIR/skills/clipvoice" "$DMG_STAGE/clipvoice-skill"
cp "$ROOT_DIR/LICENSE" "$DMG_STAGE/LICENSE.txt"

cat > "$DMG_STAGE/INSTALL.txt" <<EOF
ClipVoice $VERSION (macOS Universal arm64 + x86_64)

1. Drag ClipVoice.app into Applications.
2. First launch (ad-hoc signed beta):
   Right-click ClipVoice.app -> Open (or run: xattr -dr com.apple.quarantine /Applications/ClipVoice.app).
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

echo "==> Auditing distributables for leaked machine paths or clipboard data..."
for bin in "$APP_DIR/Contents/MacOS/ClipVoice" "$APP_DIR/Contents/MacOS/clipvoice-cli" "$APP_DIR/Contents/MacOS/clipvoice-mcp"; do
    if strings "$bin" | grep -q "/Users/"; then
        echo "WARNING: Found /Users/ path string inside $bin" >&2
        strings "$bin" | grep "/Users/" | head -n 5 >&2 || true
        exit 1
    fi
done

echo "==> Packaged artifacts in $DIST_DIR:"
ls -lh "$DIST_DIR"
