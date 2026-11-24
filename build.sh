#!/bin/bash
# Build ASCII Wallpaper into a self-contained .app bundle.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

APP="$ROOT/build/AsciiWallpaper.app"
BIN="$APP/Contents/MacOS/AsciiWallpaper"
CACHE="$ROOT/build/modulecache"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$CACHE"

swiftc -O -swift-version 5 \
    -module-cache-path "$CACHE" \
    -target "$(uname -m)-apple-macosx14.0" \
    "$ROOT"/Sources/*.swift \
    -o "$BIN" \
    -framework AppKit -framework CoreText -framework ImageIO -framework QuartzCore

cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "Built: $APP"
