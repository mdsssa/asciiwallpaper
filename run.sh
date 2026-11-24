#!/bin/bash
# Start ASCII Wallpaper from the project folder.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/AsciiWallpaper.app"
BIN="$APP/Contents/MacOS/AsciiWallpaper"
PATTERN="AsciiWallpaper.app/Contents/MacOS/AsciiWallpaper"

if [ ! -x "$BIN" ]; then
    "$ROOT/build.sh"
fi

if pgrep -f "$PATTERN" >/dev/null 2>&1; then
    echo "ASCII Wallpaper is already running. Switch scene: $BIN --scene <name>"
    exit 0
fi

nohup "$BIN" "$@" >"$ROOT/build/run.log" 2>&1 &
sleep 1

if pgrep -f "$PATTERN" >/dev/null 2>&1; then
    echo "ASCII Wallpaper started."
    echo "Menu bar icon is ready. Stop with: $ROOT/stop.sh"
else
    echo "Failed to start. Log:"
    tail -20 "$ROOT/build/run.log" 2>/dev/null || true
    exit 1
fi
