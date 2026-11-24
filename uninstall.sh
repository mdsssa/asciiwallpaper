#!/bin/bash
# Удаляет автозапуск и установленную копию приложения. Папка проекта не трогается.
set -euo pipefail
DEST="$HOME/Applications/AsciiWallpaper.app"
PLIST="$HOME/Library/LaunchAgents/ru.disa.asciiwallpaper.plist"
LABEL="ru.disa.asciiwallpaper"

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
rm -f "$PLIST"
pkill -f "AsciiWallpaper.app/Contents/MacOS/AsciiWallpaper" 2>/dev/null || true
rm -rf "$DEST"

defaults delete ru.disa.asciiwallpaper 2>/dev/null || true

echo "ASCII Wallpaper удалён. Папка проекта осталась на месте."
