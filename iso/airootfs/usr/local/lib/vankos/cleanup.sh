#!/usr/bin/env bash
# Vanks OS — шаг 3: уборка перед размонтированием цели.
set -uo pipefail

ROOT="${1:-}"
log() { printf '[vankos/cleanup] %s\n' "$*"; }

if [ -z "${ROOT}" ] || [ ! -d "${ROOT}" ]; then
    log "нет цели — нечего убирать"
    exit 0
fi

if mountpoint -q "${ROOT}/var/cache/vankos/repo" 2>/dev/null; then
    log "отмонтирую локальный репозиторий"
    umount "${ROOT}/var/cache/vankos/repo" || log "предупреждение: umount не удался"
fi

rm -rf "${ROOT}/var/cache/vankos"
rm -rf "${ROOT}/usr/local/lib/vankos"
rm -f  "${ROOT}/etc/pacman.d/vankos-repo.conf"

# Обычный pacman.conf для установленной системы (на время установки там был
# только локальный репозиторий).
log "пишу pacman.conf установленной системы"
cat > "${ROOT}/etc/pacman.conf" <<'EOF'
# Vanks OS
[options]
HoldPkg = pacman glibc
Architecture = auto
CheckSpace
ParallelDownloads = 5
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
EOF

# В mirrorlist из пакета все зеркала закомментированы — без этого pacman -Syu
# в установленной системе не работает.
mirrorlist="${ROOT}/etc/pacman.d/mirrorlist"
if ! grep -q '^[[:space:]]*Server' "${mirrorlist}" 2>/dev/null; then
    log "добавляю зеркало по умолчанию"
    install -d "${ROOT}/etc/pacman.d"
    printf '%s\n' 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' >> "${mirrorlist}"
fi

log "готово"
exit 0
