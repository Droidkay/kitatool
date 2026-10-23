#!/bin/bash
# Builds "Notch Player.app" and puts it in your Applications folder.
# Run in Terminal:   bash build.sh
# Needs Apple's free command line tools (the script offers to install them).
set -e
cd "$(dirname "$0")"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "Apple's developer tools aren't installed yet."
  echo "A window will open: click Install, wait for it to finish (5-15 min), then run: bash build.sh"
  xcode-select --install || true
  exit 1
fi

APP="build/Notch Player.app"
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
ARCH="$(uname -m)"
echo "Building for $ARCH…"
xcrun swiftc -O -target "$ARCH-apple-macos13.0" \
  -framework AppKit -framework SwiftUI -framework IOKit -framework ServiceManagement \
  -o "$APP/Contents/MacOS/NotchPlayer" Sources/*.swift
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"

if [ "$1" != "--no-install" ]; then
  pkill -x NotchPlayer 2>/dev/null || true
  rm -rf "/Applications/Notch Player.app"
  cp -R "$APP" /Applications/
  echo "Installed to Applications. Opening…"
  open "/Applications/Notch Player.app"
  echo "Done! Hover over your notch."
fi
