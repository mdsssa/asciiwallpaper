#!/bin/bash
# Removes autostart and the installed copy of the app. The project folder is left untouched.
set -euo pipefail
DEST="$HOME/Applications/AsciiWallpaper.app"
PLIST="$HOME/Library/LaunchAgents/ru.disa.asciiwallpaper.plist"
LABEL="ru.disa.asciiwallpaper"

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
rm -f "$PLIST"
pkill -f "AsciiWallpaper.app/Contents/MacOS/AsciiWallpaper" 2>/dev/null || true
rm -rf "$DEST"

defaults delete ru.disa.asciiwallpaper 2>/dev/null || true

echo "ASCII Wallpaper removed. The project folder was left in place."
