#!/usr/bin/env bash
# Поставить Vanks Shell на этот компьютер для проверки с экрана входа:
#
#   tools/install-session.sh            собрать (release) и поставить в /usr/local
#   tools/install-session.sh --remove   убрать
#
# Ставит vanks-shell и vanks-shell-session в /usr/local/bin и пункт сессии
# в /usr/share/wayland-sessions (его покажет экран входа Delta). Delta и
# Hyprland не трогает. Просит sudo.
set -eu
cd "$(dirname "$0")/.."

bin=/usr/local/bin
session=/usr/share/wayland-sessions/vanks-shell.desktop

if [ "${1:-}" = "--remove" ]; then
    sudo rm -f -- "${bin}/vanks-shell" "${bin}/vanks-shell-session" "${session}"
    echo "Vanks Shell убрана с экрана входа."
    exit 0
fi

cargo build --release
sudo install -Dm755 target/release/vanks-shell "${bin}/vanks-shell"
sudo install -Dm755 data/vanks-shell-session "${bin}/vanks-shell-session"
sudo install -Dm644 data/vanks-shell.desktop "${session}"
echo "Готово: на экране входа появится «Vanks Shell (разработка)»."
echo "Выход из неё: Super+Shift+E (или Ctrl+Alt+Backspace)."
