#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="0.1.1-beta"
BUILD_NUMBER="2"
BUILD_DIR="$ROOT_DIR/build"
APP_DIR="$BUILD_DIR/ClipVoice.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ICON_SOURCE="$ROOT_DIR/assets/clipvoice-icon.png"

if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "Error: missing parent-supplied app icon at $ICON_SOURCE (refusing to generate a replacement icon)." >&2
    exit 1
fi

echo "==> Building ClipVoice $VERSION (universal arm64 + x86_64)..."
swift build -c release --arch arm64 --arch x86_64

BIN_DIR="$ROOT_DIR/.build/apple/Products/Release"
for bin in ClipVoice clipvoice-cli clipvoice-mcp; do
    if [[ ! -x "$BIN_DIR/$bin" ]]; then
        echo "Error: expected binary missing at $BIN_DIR/$bin" >&2
        exit 1
    fi
done

echo "==> Generating AppIcon.icns from $ICON_SOURCE..."
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
swift "$ROOT_DIR/scripts/build_iconset.swift" "$ICON_SOURCE" "$ICONSET_DIR"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

echo "==> Assembling ClipVoice.app bundle..."
cp "$BIN_DIR/ClipVoice" "$MACOS_DIR/ClipVoice"
cp "$BIN_DIR/clipvoice-cli" "$MACOS_DIR/clipvoice-cli"
cp "$BIN_DIR/clipvoice-mcp" "$MACOS_DIR/clipvoice-mcp"
strip -x "$MACOS_DIR/ClipVoice" "$MACOS_DIR/clipvoice-cli" "$MACOS_DIR/clipvoice-mcp" || true
chmod +x "$MACOS_DIR/ClipVoice" "$MACOS_DIR/clipvoice-cli" "$MACOS_DIR/clipvoice-mcp"

cp "$ICON_SOURCE" "$RESOURCES_DIR/AppLogo.png"

printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

cat > "$CONTENTS_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>ClipVoice</string>
    <key>CFBundleExecutable</key>
    <string>ClipVoice</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>dev.workromancer.clipvoice</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>ko</string>
    </array>
    <key>CFBundleName</key>
    <string>ClipVoice</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Copy localizations & bundled agent skill
cp -R "$ROOT_DIR/Sources/ClipVoiceCore/Resources/en.lproj" "$RESOURCES_DIR/en.lproj"
cp -R "$ROOT_DIR/Sources/ClipVoiceCore/Resources/ko.lproj" "$RESOURCES_DIR/ko.lproj"
mkdir -p "$RESOURCES_DIR/skills"
cp -R "$ROOT_DIR/skills/clipvoice" "$RESOURCES_DIR/skills/clipvoice"

echo "==> Ad-hoc signing ClipVoice.app..."
codesign --force --sign - "$MACOS_DIR/clipvoice-cli"
codesign --force --sign - "$MACOS_DIR/clipvoice-mcp"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "==> Binary architectures:"
lipo -info "$MACOS_DIR/ClipVoice" "$MACOS_DIR/clipvoice-cli" "$MACOS_DIR/clipvoice-mcp"
echo "==> Built: $APP_DIR"
