#!/bin/bash
set -euo pipefail

MAC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$MAC_DIR/.." && pwd)"
BUILD_DIR="$MAC_DIR/build"
APP_DIR="$BUILD_DIR/ToastFish.app"

swift build --package-path "$MAC_DIR" -c release
BIN_DIR="$(swift build --package-path "$MAC_DIR" -c release --show-bin-path)"

mkdir -p "$BUILD_DIR"
STAGING_DIR="$(mktemp -d "$BUILD_DIR/.package.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
CONTENTS="$STAGING_DIR/ToastFish.app/Contents"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/ToastFish" "$CONTENTS/MacOS/ToastFish"

ICONSET="$STAGING_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$MAC_DIR/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$MAC_DIR/Resources/AppIcon.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
cp "$MAC_DIR/Resources/AppIcon.png" "$CONTENTS/Resources/AppIcon.png"
for resource in inami.db 使用说明.html Star.pdf mute.mp3 自定义模板.xlsx; do
    cp "$REPO_DIR/Resources/$resource" "$CONTENTS/Resources/$resource"
done
cp -R "$REPO_DIR/Resources/Goin" "$CONTENTS/Resources/Goin"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.toastfish.mac</string>
    <key>CFBundleName</key><string>ToastFish</string>
    <key>CFBundleDisplayName</key><string>ToastFish</string>
    <key>CFBundleExecutable</key><string>ToastFish</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSUIElement</key><true/>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>CFBundleDevelopmentRegion</key><string>zh_CN</string>
</dict>
</plist>
PLIST

codesign --force --deep -s - "$STAGING_DIR/ToastFish.app"
codesign --verify --deep --strict "$STAGING_DIR/ToastFish.app"
# Replace only this script's output after the new bundle has been verified.
rm -rf "$APP_DIR"
mv "$STAGING_DIR/ToastFish.app" "$APP_DIR"
printf '已生成：%s\n' "$APP_DIR"
