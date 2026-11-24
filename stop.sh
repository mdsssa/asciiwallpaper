#!/bin/bash
# Stops ASCII Wallpaper (autostart configuration is left untouched).
set -euo pipefail
PATTERN="AsciiWallpaper.app/Contents/MacOS/AsciiWallpaper"

if pgrep -f "$PATTERN" >/dev/null 2>&1; then
    pkill -f "$PATTERN" 2>/dev/null || true
    echo "ASCII Wallpaper stopped."
else
    echo "ASCII Wallpaper is not running."
fi
