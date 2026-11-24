#!/bin/bash
# Installs ASCII Wallpaper into ~/Applications and tries to enable autostart.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/AsciiWallpaper.app"
DEST="$HOME/Applications/AsciiWallpaper.app"
PLIST="$HOME/Library/LaunchAgents/ru.disa.asciiwallpaper.plist"
LABEL="ru.disa.asciiwallpaper"

if [ ! -x "$APP/Contents/MacOS/AsciiWallpaper" ]; then
    "$ROOT/build.sh" || exit 1
fi

mkdir -p "$HOME/Applications" "$HOME/Library/LaunchAgents" || exit 1

pkill -f "AsciiWallpaper.app/Contents/MacOS/AsciiWallpaper" 2>/dev/null || true
sleep 0.3

rm -rf "$DEST"
if ! cp -R "$APP" "$DEST"; then
    echo "Failed to copy the app to $DEST"
    exit 1
fi

cat >"$PLIST" <<PLIST_EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>$DEST/Contents/MacOS/AsciiWallpaper</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>LimitLoadToSessionType</key>
    <string>Aqua</string>
</dict>
</plist>
PLIST_EOF

launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
AUTOSTART=0
if launchctl bootstrap "gui/$(id -u)" "$PLIST" >/dev/null 2>&1; then
    launchctl kickstart -k "gui/$(id -u)/$LABEL" >/dev/null 2>&1 || true
    AUTOSTART=1
fi

# Start the installed copy right now.
if ! pgrep -f "$DEST/Contents/MacOS/AsciiWallpaper" >/dev/null 2>&1; then
    open -g "$DEST" 2>/dev/null || nohup "$DEST/Contents/MacOS/AsciiWallpaper" >/dev/null 2>&1 &
    sleep 1
fi

if pgrep -f "AsciiWallpaper.app/Contents/MacOS/AsciiWallpaper" >/dev/null 2>&1; then
    echo "ASCII Wallpaper installed to $DEST and started."
else
    echo "The app is installed but could not be started. Start it manually:"
    echo "  open -g \"$DEST\""
fi

if [ "$AUTOSTART" = 1 ]; then
    echo "Autostart at login is enabled (LaunchAgent $LABEL)."
else
    echo "Could not enable autostart automatically (the system blocked launchctl in this session)."
    echo "Check again after logging back in, or add the app manually:"
    echo "  System Settings → General → Login Items → \"+\" → $DEST"
fi
