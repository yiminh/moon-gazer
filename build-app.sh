#!/bin/bash
# Builds MoonGazer.app (a double-clickable, non-sandboxed macOS app bundle).
set -e
cd "$(dirname "$0")"

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/MoonGazer"

APP="Moon Gazer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/MoonGazer"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Moon Gazer</string>
    <key>CFBundleDisplayName</key><string>Moon Gazer</string>
    <key>CFBundleIdentifier</key><string>com.moongazer.app</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleVersion</key><string>1.4.2</string>
    <key>CFBundleShortVersionString</key><string>1.4.2</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleExecutable</key><string>MoonGazer</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppTransportSecurity</key>
    <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
</dict>
</plist>
PLIST

# Generate AppIcon.icns from icon.png if present.
if [[ -f icon.png ]]; then
    ICONSET="$(mktemp -d)/AppIcon.iconset"; mkdir -p "$ICONSET"
    for s in 16 32 64 128 256 512; do
        sips -z $s $s icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null 2>&1
        sips -z $((s*2)) $((s*2)) icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null 2>&1
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true
fi

echo "APPL????" > "$APP/Contents/PkgInfo"

# Ad-hoc sign so Keychain ACL / network behave consistently.
codesign --force --deep --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
