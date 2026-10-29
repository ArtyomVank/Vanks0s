#!/usr/bin/env bash
# Vanks OS — шаг 1 установки: базовая система в ${ROOT} через pacstrap.
# Запускается Calamares (shellprocess, dontChroot) от root в live-системе.
#
# Логика:
#   * если на ISO есть локальный репозиторий /var/cache/vankos/repo — установка
#     полностью офлайновая, репозиторий пробрасывается в цель bind-монтированием;
#   * иначе используются зеркала Arch из /etc/pacman.d/mirrorlist.
set -euo pipefail
export LC_ALL=C

ROOT="${1:-}"
REPO_DIR=/var/cache/vankos/repo
TARGET_REPO=/var/cache/vankos/repo

log()  { printf '[vankos/bootstrap] %s\n' "$*"; }
fail() { printf '[vankos/bootstrap] ОШИБКА: %s\n' "$*" >&2; exit 1; }

[ -n "${ROOT}" ] || fail "не передана точка монтирования цели"
[ -d "${ROOT}" ] || fail "нет каталога ${ROOT}"
command -v pacstrap >/dev/null 2>&1 || fail "не найден pacstrap (нужен пакет arch-install-scripts)"

FALLBACK_MIRROR='Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch'

# Офлайн — только если рядом с базой реально лежат пакеты.
offline=0
if { [ -e "${REPO_DIR}/vankos.db.tar.gz" ] || [ -e "${REPO_DIR}/vankos.db" ]; } \
    && compgen -G "${REPO_DIR}/*.pkg.tar.zst" >/dev/null; then
    offline=1
fi
if [ "${offline}" -eq 1 ]; then
    log "режим: офлайн (локальный репозиторий на ISO)"
else
    log "режим: онлайн (зеркала Arch)"
    # В mirrorlist из пакета все зеркала закомментированы.
    if ! grep -q '^[[:space:]]*Server' /etc/pacman.d/mirrorlist 2>/dev/null; then
        log "в mirrorlist нет зеркал — добавляю ${FALLBACK_MIRROR#Server = }"
        printf '%s\n' "${FALLBACK_MIRROR}" >> /etc/pacman.d/mirrorlist
    fi
    # Связка ключей live-системы (в образе её никто не создаёт).
    if [ ! -f /etc/pacman.d/gnupg/trustdb.gpg ]; then
        log "инициализирую связку ключей pacman в live-системе"
        pacman-key --init
        pacman-key --populate archlinux
    fi
fi

# --- ключи pacman в целевой системе ---
# Нужны для онлайн-режима: pacman в цели должен доверять подписям core/extra.
# Для офлайн-репозитория подписи отключены (TrustAll), поэтому там это не критично.
install -d "${ROOT}/etc/pacman.d" "${ROOT}/var/cache/pacman/pkg"
if [ ! -f "${ROOT}/etc/pacman.d/gnupg/trustdb.gpg" ]; then
    log "инициализирую связку ключей pacman в цели"
    pacman-key --gpgdir "${ROOT}/etc/pacman.d/gnupg" --init >/dev/null 2>&1 || true
    pacman-key --gpgdir "${ROOT}/etc/pacman.d/gnupg" --populate archlinux >/dev/null 2>&1 || true
fi
if [ ! -f "${ROOT}/etc/pacman.d/gnupg/trustdb.gpg" ] && [ -d /etc/pacman.d/gnupg ]; then
    log "копирую связку ключей из live-системы"
    cp -a /etc/pacman.d/gnupg "${ROOT}/etc/pacman.d/"
fi

# --- офлайн-репозиторий: пробрасываем в цель по тому же пути ---
if [ "${offline}" -eq 1 ]; then
    install -d "${ROOT}${TARGET_REPO}"
    if ! mountpoint -q "${ROOT}${TARGET_REPO}"; then
        mount --bind "${REPO_DIR}" "${ROOT}${TARGET_REPO}"
    fi
fi

# --- конфиг pacman ---
# Офлайн: только локальный репозиторий. Если оставить core/extra, pacman -Sy
# падает без сети и без зеркал. CacheDir указывает на сам репозиторий, чтобы
# pacman не копировал ~2 ГБ пакетов в оперативную память live-системы.
write_pacman_conf() {  # $1 — путь к репозиторию, видимый этому pacman
    echo '[options]'
    echo 'HoldPkg = pacman glibc'
    echo 'Architecture = auto'
    echo 'CheckSpace'
    echo 'ParallelDownloads = 5'
    echo 'SigLevel = Required DatabaseOptional'
    echo 'LocalFileSigLevel = Optional'
    if [ "${offline}" -eq 1 ]; then
        echo "CacheDir = $1/"
        echo 'CacheDir = /var/cache/pacman/pkg/'
        echo
        echo '[vankos]'
        echo 'SigLevel = Optional TrustAll'
        echo "Server = file://$1"
    else
        echo
        echo '[core]'
        echo 'Include = /etc/pacman.d/mirrorlist'
        echo
        echo '[extra]'
        echo 'Include = /etc/pacman.d/mirrorlist'
    fi
}

pacconf=$(mktemp /tmp/vankos-pacman.XXXXXX.conf)
trap 'rm -f "${pacconf}"' EXIT
write_pacman_conf "${REPO_DIR}" > "${pacconf}"

mapfile -t pkgs < <(grep -vE '^[[:space:]]*(#|$)' /usr/share/vankos/target-base.txt)
[ "${#pkgs[@]}" -gt 0 ] || fail "пустой список базовых пакетов"

log "ставлю базовую систему: ${#pkgs[@]} пакетов (это самый долгий шаг)"
pacstrap -C "${pacconf}" -c "${ROOT}" "${pkgs[@]}"

# --- конфиг pacman внутри цели на время установки (его использует desktop.sh;
#     обычный конфиг с core/extra пишет cleanup.sh) ---
{
    echo '# Vanks OS — временный конфиг установщика'
    write_pacman_conf "${TARGET_REPO}"
} > "${ROOT}/etc/pacman.conf"

# --- os-release и идентичность дистрибутива ---
install -Dm644 /usr/share/vankos/os-release "${ROOT}/usr/lib/os-release"
ln -sfn ../usr/lib/os-release "${ROOT}/etc/os-release"
install -Dm644 /usr/share/vankos/lsb-release "${ROOT}/etc/lsb-release"
install -d "${ROOT}/etc/vankos"
printf 'base installed by vankos-installer\n' > "${ROOT}/etc/vankos/install.log"

log "базовая система готова"
exit 0
