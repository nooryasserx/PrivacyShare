#!/bin/bash
# Builds PrivacyShare.app (needs Xcode or Command Line Tools: xcode-select --install)
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/PrivacyShare.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/PrivacyShare "$APP/Contents/MacOS/PrivacyShare"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep -s - "$APP"

# Every rebuild looks like a "new app" to macOS, so clear the old Screen Recording
# permission; the app will ask for it again on first launch.
tccutil reset ScreenCapture com.privacyshare.app >/dev/null 2>&1 || true

echo ""
echo "✅ Built: $(pwd)/$APP"
echo "Run it with:  open \"$APP\""
