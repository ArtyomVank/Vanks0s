#!/usr/bin/env bash
# ============================================================================
#  Vanks OS — вернуть Delta, если вместо неё встал чужой пакет «delta» из AUR.
#
#  Признак: после «yay» (обновления AUR) и перезагрузки — чёрный экран, в
#  pacman -Q delta версия 20060803. В AUR есть другая программа с тем же именем,
#  и до Delta 2.0.1 yay считал её новее. С 2.0.1 у пакета эпоха — больше не
#  заменится.
#
#  Запуск с чёрного экрана: Ctrl+Alt+F3, войти своим именем и паролем, затем
#      ./fix-delta.sh
#  Пакет delta-*.pkg.tar.zst (и .sha256) рядом со скриптом ставится без
#  интернета; нет его — скрипт скачает последнюю Delta из релизов GitHub.
# ============================================================================
set -euo pipefail

REPO=ArtyomVank/Vanks0s
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\033[1;35m[Delta]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[Delta] ОШИБКА:\033[0m %s\n' "$*" >&2; exit 1; }

[[ ${EUID} -ne 0 ]] || die "запускайте без sudo: ./fix-delta.sh (пароль спросит сам)"

now=$(pacman -Q delta 2>/dev/null | awk '{print $2}') || now=""
log "сейчас стоит: delta ${now:-нет}"

pkg=$(find "${HERE}" -maxdepth 1 -name 'delta-[0-9]*-any.pkg.tar.zst' | sort -V | tail -n1)
if [[ -z ${pkg} ]]; then
    log "пакета рядом нет — скачиваю последнюю Delta с GitHub"
    command -v jq >/dev/null || die "нет jq; положите delta-*.pkg.tar.zst рядом со скриптом"
    url=$(curl -fsSL --max-time 30 "https://api.github.com/repos/${REPO}/releases/latest" |
        jq -r '.assets[] | select(.name | test("^delta-[0-9][^-]*-[0-9]+-any\\.pkg\\.tar\\.zst$")) | .browser_download_url' |
        head -n1) || die "нет связи с GitHub"
    [[ -n ${url} ]] || die "в последнем релизе нет пакета Delta"
    tmp=$(mktemp -d)
    trap 'rm -rf "${tmp:?}"' EXIT
    pkg="${tmp}/${url##*/}"
    curl -fL --retry 3 --max-time 600 -o "${pkg}" "${url}" || die "не удалось скачать ${url##*/}"
    curl -fsL --max-time 60 -o "${pkg}.sha256" "${url}.sha256" || rm -f "${pkg}.sha256"
fi

if [[ -f ${pkg}.sha256 ]]; then
    ( cd "$(dirname "${pkg}")" && sha256sum -c --quiet "$(basename "${pkg}").sha256" ) \
        || die "$(basename "${pkg}") повреждён: контрольная сумма не совпала"
    log "контрольная сумма совпала"
fi

log "ставлю $(basename "${pkg}") — sudo спросит ваш пароль"
# отладочные файлы чужого пакета: без него они не нужны
if pacman -Q delta-debug >/dev/null 2>&1; then
    sudo pacman -R --noconfirm delta-debug
fi
sudo pacman -U --noconfirm "${pkg}"

# сборка чужого пакета в кэше yay: чтобы её не поставить снова по ошибке
rm -rf "${HOME:?}/.cache/yay/delta" "${HOME:?}/.cache/paru/clone/delta"

# вход в систему упал несколько раз подряд — systemd его больше не запускает
sudo systemctl reset-failed greetd.service 2>/dev/null || :

log "готово: $(pacman -Q delta)"
read -r -p "Перезагрузить сейчас? [Д/н] " a || a=""
case ${a,,} in
    н|n|нет|no) log "перезагрузите позже: systemctl reboot" ;;
    *) systemctl reboot ;;
esac
