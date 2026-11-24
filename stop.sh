#!/bin/bash
# Останавливает ASCII Wallpaper (автозапуск при этом остаётся настроенным).
set -euo pipefail
PATTERN="AsciiWallpaper.app/Contents/MacOS/AsciiWallpaper"

if pgrep -f "$PATTERN" >/dev/null 2>&1; then
    pkill -f "$PATTERN" 2>/dev/null || true
    echo "ASCII Wallpaper остановлен."
else
    echo "ASCII Wallpaper не запущен."
fi
