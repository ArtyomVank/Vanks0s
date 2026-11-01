#!/usr/bin/env bash
# Поставить композитор Delta на этот компьютер для проверки с экрана входа:
#
#   tools/install-session.sh            собрать (release) и поставить в /usr/local
#   tools/install-session.sh --remove   убрать
#
# Ставит delta-compositor и delta-compositor-session в /usr/local/bin и пункт сессии
# в /usr/share/wayland-sessions (его покажет экран входа Delta). Delta и
# Hyprland не трогает. Просит sudo.
set -eu
cd "$(dirname "$0")/.."

bin=/usr/local/bin
session=/usr/share/wayland-sessions/delta-compositor.desktop

if [ "${1:-}" = "--remove" ]; then
    sudo rm -f -- "${bin}/delta-compositor" "${bin}/delta-compositor-session" "${session}"
    echo "композитор Delta убрана с экрана входа."
    exit 0
fi

cargo build --release
sudo install -Dm755 target/release/delta-compositor "${bin}/delta-compositor"
sudo install -Dm755 data/delta-compositor-session "${bin}/delta-compositor-session"
sudo install -Dm644 data/delta-compositor.desktop "${session}"
echo "Готово: на экране входа появится «композитор Delta (разработка)»."
echo "Выход из неё: Super+Shift+E (или Ctrl+Alt+Backspace)."
