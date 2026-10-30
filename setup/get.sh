#!/usr/bin/env bash
# ============================================================================
#  Vanks Setup одной командой (Arch Linux и другие дистрибутивы):
#
#      bash <(curl -fsSL https://raw.githubusercontent.com/ArtyomVank/Vanks0s/main/setup/get.sh)
#
#  Аргументы передаются дальше: … get.sh) --usb /dev/sdb, --list, --folder ~/Загрузки
#
#  Берёт свежую версию программы из репозитория (только Python, без
#  зависимостей) в ~/.cache/vanks-setup/app и запускает её в терминале.
#  Для раздела с выбранной версией оболочки на флешке нужны sfdisk,
#  mkfs.fat и mtools — если их нет, предложит поставить через pacman.
# ============================================================================
set -euo pipefail

REPO=${VANKS_SETUP_REPO:-ArtyomVank/Vanks0s}
REF=${VANKS_SETUP_REF:-main}
RAW="https://raw.githubusercontent.com/${REPO}/${REF}/setup/vanks_setup"
APP="${XDG_CACHE_HOME:-${HOME}/.cache}/vanks-setup/app"
FILES=(__init__.py __main__.py releases.py download.py devices.py writer.py cli.py)

say() { printf '\033[1;35m[vanks-setup]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[vanks-setup]\033[0m %s\n' "$*" >&2; exit 1; }

# вопросы — с клавиатуры, даже если скрипт пришёл через трубу
TTY=/dev/tty
# -r не годится: без управляющего терминала файл есть, но не открывается
{ : < "${TTY}"; } 2>/dev/null || TTY=/dev/stdin

ask_install() {  # пакеты…
    command -v pacman >/dev/null || die "поставьте: $* — и запустите ещё раз"
    printf 'Нужно поставить: %s. Поставить через sudo pacman? [Д/н] ' "$*"
    read -r ans < "${TTY}" || ans=""
    case "${ans,,}" in н|n|no|нет) die "без них не получится" ;; esac
    sudo pacman -S --needed --noconfirm "$@"
}

command -v python3 >/dev/null || ask_install python
need=()
command -v mkfs.fat >/dev/null || need+=(dosfstools)
command -v mcopy >/dev/null || need+=(mtools)
command -v sfdisk >/dev/null || need+=(util-linux)
if [ "${#need[@]}" -gt 0 ]; then
    say "без ${need[*]} флешка запишется, но выбранную версию оболочки на неё не положить"
    ask_install "${need[@]}" || true
fi

say "загружаю программу (${REPO}@${REF})…"
tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT
mkdir -p "${tmp}/vanks_setup"
for f in "${FILES[@]}"; do
    curl -fsSL --retry 3 -o "${tmp}/vanks_setup/${f}" "${RAW}/${f}" || die "не удалось загрузить ${f}"
done
rm -rf "${APP}"
mkdir -p "$(dirname "${APP}")"
mv "${tmp}" "${APP}"
trap - EXIT

cd "${APP}"
exec python3 -m vanks_setup --cli "$@" < "${TTY}"
