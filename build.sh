#!/bin/bash
# Builds Kita Clips and installs it to /Applications.
# Run with:  bash build.sh
set -e
cd "$(dirname "$0")"

APP_NAME="Kita Clips"
APP="$APP_NAME.app"

if ! command -v swift >/dev/null 2>&1; then
  echo ""
  echo "Swift isn't installed yet. Run this once, wait for it to finish, then run build.sh again:"
  echo "    xcode-select --install"
  exit 1
fi

# Quit any older copy that is still running
osascript -e 'tell application "Kita Clips" to quit' >/dev/null 2>&1 || true
pkill -x KitaClips >/dev/null 2>&1 || true
sleep 1

echo "==> Building (the first build takes a minute or two)..."
swift build -c release

BIN="$(swift build -c release --show-bin-path)/KitaClips"
if [ ! -f "$BIN" ]; then
  echo "Build finished but the program wasn't found at $BIN"
  exit 1
fi

echo "==> Making the app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/KitaClips"
cp Info.plist "$APP/Contents/Info.plist"

if [ -f Resources/AppIcon.png ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for size in 16 32 128 256 512; do
    sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z $double $double Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" || true
fi

xattr -cr "$APP" 2>/dev/null || true
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "==> Installing to /Applications..."
if rm -rf "/Applications/$APP" 2>/dev/null && cp -R "$APP" "/Applications/"; then
  echo ""
  echo "Done. Opening Kita Clips..."
  open "/Applications/$APP"
else
  echo ""
  echo "Couldn't write to /Applications, so the app is here instead:"
  echo "    $(pwd)/$APP"
  open "$APP"
fi
