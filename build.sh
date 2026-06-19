#!/bin/bash
set -e

APP_NAME="RepoRadar"
BUNDLE_ID="com.reporadar.app"
CONFIG="${1:-debug}"          # ./build.sh debug  |  ./build.sh release

echo "▶︎ Building $APP_NAME ($CONFIG)…"
swift build -c "$CONFIG"
BIN_DIR=$(swift build -c "$CONFIG" --show-bin-path)

APP="$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"

# Copy SwiftPM-generated resource bundles (localizations live here). Placed in
# Contents/Resources so `Bundle.module` resolves them next to the main bundle.
cp -R "$BIN_DIR"/*.bundle "$APP/Contents/Resources/" 2>/dev/null || true

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <!-- Dock icon AND menu bar item are both shown.
         (Set LSUIElement to true if you ever want a pure menu-bar app.) -->
    <key>LSUIElement</key>
    <false/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Ad-hoc code signing. This matters: UserNotifications and the Keychain
# behave much more reliably when the bundle is signed (even ad-hoc).
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
    echo "⚠︎ codesign failed (app still runs, but notifications/keychain may be limited)"

echo "✅ Built $APP"
echo "   Run with:  open $APP"
