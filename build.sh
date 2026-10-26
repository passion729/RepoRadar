#!/bin/bash
set -e

APP_NAME="RepoRadar"
BUNDLE_ID="com.reporadar.app"
CONFIG="${1:-debug}"          # ./build.sh debug  |  ./build.sh release

source "$(dirname "$0")/clt-env.sh"

echo "▶︎ Building $APP_NAME ($CONFIG)…"
swift build -c "$CONFIG"
BIN_DIR=$(swift build -c "$CONFIG" --show-bin-path)

APP="$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Frameworks"
ditto "$BIN_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

# Sparkle compares build numbers: the commit count only grows on main.
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION:-1.0}</string>
    <key>CFBundleVersion</key>
    <string>$BUILD</string>
    <key>LSMinimumSystemVersion</key>
    <string>26.0</string>
    <!-- Dock icon AND menu bar item are both shown.
         (Set LSUIElement to true if you ever want a pure menu-bar app.) -->
    <key>LSUIElement</key>
    <false/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <!-- Sparkle: appcast.xml on main lists the releases; release.sh signs each with the EdDSA key. -->
    <key>SUFeedURL</key>
    <string>https://raw.githubusercontent.com/passion729/RepoRadar/main/appcast.xml</string>
    <key>SUPublicEDKey</key>
    <string>3XEF3cVXZg//0u9drmJpI9eB1ccjgefm0wv9KVAzZyc=</string>
    <key>SUEnableAutomaticChecks</key>
    <true/>
    <key>SUAutomaticallyUpdate</key>
    <true/>
</dict>
</plist>
EOF

# Sign with the Yuanju Bo team (3JNF4FX993) when its certificate is in the Keychain, so the signature
# stays the same across rebuilds and the Keychain stops asking. Otherwise sign ad hoc.
# Override with SIGN_IDENTITY="…" ./build.sh, or SIGN_IDENTITY=- for ad hoc.
IDENTITY="${SIGN_IDENTITY:-Apple Development: Oscar Passion (8HXY99Y2JK)}"
if [ "$IDENTITY" != "-" ] && ! security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$IDENTITY\""; then
    IDENTITY="-"
fi
# Inside out, without --deep, as Sparkle's docs list it.
SPK="$APP/Contents/Frameworks/Sparkle.framework"
if codesign -f -s "$IDENTITY" -o runtime "$SPK/Versions/B/XPCServices/Installer.xpc" >/dev/null 2>&1 &&
   codesign -f -s "$IDENTITY" -o runtime --preserve-metadata=entitlements "$SPK/Versions/B/XPCServices/Downloader.xpc" >/dev/null 2>&1 &&
   codesign -f -s "$IDENTITY" -o runtime "$SPK/Versions/B/Autoupdate" >/dev/null 2>&1 &&
   codesign -f -s "$IDENTITY" -o runtime "$SPK/Versions/B/Updater.app" >/dev/null 2>&1 &&
   codesign -f -s "$IDENTITY" -o runtime "$SPK" >/dev/null 2>&1 &&
   codesign -f -s "$IDENTITY" "$APP" >/dev/null 2>&1; then
    [ "$IDENTITY" = "-" ] && echo "   Signed ad hoc" || echo "   Signed as $IDENTITY"
else
    echo "⚠︎ codesign failed (app still runs, but notifications/keychain may be limited)"
fi

echo "✅ Built $APP"
echo "   Run with:  open $APP"
