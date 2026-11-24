#!/bin/bash
# Запуск ASCII Wallpaper из папки проекта.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/build/AsciiWallpaper.app"
BIN="$APP/Contents/MacOS/AsciiWallpaper"
PATTERN="AsciiWallpaper.app/Contents/MacOS/AsciiWallpaper"

if [ ! -x "$BIN" ]; then
    "$ROOT/build.sh"
fi

if pgrep -f "$PATTERN" >/dev/null 2>&1; then
    echo "ASCII Wallpaper уже запущен. Сменить сцену: $BIN --scene <имя>"
    exit 0
fi

nohup "$BIN" "$@" >"$ROOT/build/run.log" 2>&1 &
sleep 1

if pgrep -f "$PATTERN" >/dev/null 2>&1; then
    echo "ASCII Wallpaper запущен."
    echo "Иконка — в строке меню. Остановить: $ROOT/stop.sh"
else
    echo "Не удалось запустить. Лог:"
    tail -20 "$ROOT/build/run.log" 2>/dev/null || true
    exit 1
fi
