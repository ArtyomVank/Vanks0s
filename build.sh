#!/usr/bin/env bash
# ============================================================================
#  Vanks OS — сборка ISO.
#
#  Запускать на Arch Linux (или в Arch-контейнере) от root:
#      sudo ./build.sh                 # полная сборка с офлайн-репозиторием
#      sudo VANKOS_OFFLINE=0 ./build.sh    # slim-ISO без репозитория (нужен интернет)
#
#  Результат: build/out/vankos-<дата>-x86_64.iso (+ .sha256)
# ============================================================================
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${PROJECT_DIR}/build"
OUT_DIR="${BUILD_DIR}/out"
# Рабочие каталоги (профиль, airootfs, кэш пакетов) задаются в разделе 0.5:
# они должны лежать на файловой системе с владельцами и setuid.
OFFLINE="${VANKOS_OFFLINE:-1}"
JOBS="${VANKOS_JOBS:-$(nproc)}"
LOGFILE="${BUILD_DIR}/build.log"

# Пакеты, которые обязаны быть на сборочной машине.
HOST_PACKAGES=(
    archiso
    arch-install-scripts
    squashfs-tools
    libisoburn
    mtools
    dosfstools
    e2fsprogs
    erofs-utils
    grub
    syslinux
    edk2-shell
)

log()  { printf '\033[1;35m[vankos]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[vankos]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[vankos] ОШИБКА:\033[0m %s\n' "$*" >&2; exit 1; }

on_error() {
    local code=$?
    printf '\033[1;31m[vankos] Сборка прервана (код %s). Лог: %s\033[0m\n' "${code}" "${LOGFILE}" >&2
    exit "${code}"
}
trap on_error ERR

# ---------------------------------------------------------------- 0. проверки
[[ ${EUID} -eq 0 ]] || die "нужны права root: sudo ./build.sh"
[[ -f "${PROJECT_DIR}/iso/profiledef.sh" ]] || die "не найден iso/profiledef.sh"

for cmd in mkarchiso pacstrap repo-add mksquashfs xorriso pacman; do
    command -v "${cmd}" >/dev/null 2>&1 || die "нет команды ${cmd}; установите archiso и зависимости"
done

missing=()
for pkg in "${HOST_PACKAGES[@]}"; do
    pacman -Qq "${pkg}" >/dev/null 2>&1 || missing+=("${pkg}")
done
if ((${#missing[@]})); then
    warn "не хватает пакетов: ${missing[*]}"
    warn "установите: sudo pacman -S --needed ${missing[*]}"
    die "сборка невозможна"
fi

mkdir -p "${BUILD_DIR}"
: > "${LOGFILE}"
exec > >(tee -a "${LOGFILE}") 2>&1

log "проект: ${PROJECT_DIR}"
log "режим:  $([[ "${OFFLINE}" == "1" ]] && echo 'полный (офлайн-репозиторий на ISO)' || echo 'slim (установка из сети)')"
log "ядер:   ${JOBS}"

# ------------------------------------------- 0.5 файловая система для сборки
# airootfs нельзя собирать на NTFS/FAT/exFAT: там нет владельцев и setuid.
# Все файлы образа становятся uid 1000, у sudo/pkexec пропадает setuid-бит,
# live-пользователь (тоже uid 1000) не может получить root — и Calamares
# не запускается. Поэтому на таких дисках собираем внутри ext4-образа.
fs_type() { findmnt -no FSTYPE -T "$1" 2>/dev/null || echo unknown; }
is_posix_fs() {
    case "$(fs_type "$1")" in
        ntfs|ntfs3|fuseblk|vfat|msdos|exfat) return 1 ;;
        *) return 0 ;;
    esac
}

NATIVE_IMG="${VANKOS_BUILD_IMG:-${BUILD_DIR}/vankos-build.ext4}"
NATIVE_IMG_SIZE="${VANKOS_BUILD_IMG_SIZE:-40G}"
NATIVE_MNT="/mnt/vankos-build"
mounted_native=0

if [[ -n "${VANKOS_BUILD_DIR:-}" ]]; then
    NATIVE_DIR="${VANKOS_BUILD_DIR}"
    mkdir -p "${NATIVE_DIR}"
    is_posix_fs "${NATIVE_DIR}" \
        || die "VANKOS_BUILD_DIR на $(fs_type "${NATIVE_DIR}"): нужна ext4/btrfs/xfs"
elif is_posix_fs "${PROJECT_DIR}"; then
    NATIVE_DIR="${BUILD_DIR}"
else
    log "проект на $(fs_type "${PROJECT_DIR}") — собираю внутри ext4-образа ${NATIVE_IMG}"
    if [[ ! -f "${NATIVE_IMG}" ]]; then
        log "создаю образ ${NATIVE_IMG_SIZE} (разрежённый, место занимается по мере сборки)"
        truncate -s "${NATIVE_IMG_SIZE}" "${NATIVE_IMG}"
        mkfs.ext4 -q -L vankos-build "${NATIVE_IMG}"
    fi
    install -d "${NATIVE_MNT}"
    if ! mountpoint -q "${NATIVE_MNT}"; then
        mount -o loop "${NATIVE_IMG}" "${NATIVE_MNT}"
        mounted_native=1
    fi
    NATIVE_DIR="${NATIVE_MNT}"
fi

umount_native() {
    if ((mounted_native)); then
        umount "${NATIVE_MNT}" 2>/dev/null || umount -l "${NATIVE_MNT}" || true
    fi
}
trap umount_native EXIT

PROFILE_DIR="${NATIVE_DIR}/profile"
WORK_DIR="${NATIVE_DIR}/work"
CACHE_DIR="${NATIVE_DIR}/pacman-cache"
PACDB_DIR="${NATIVE_DIR}/pacdb"
REPO_DIR="${NATIVE_DIR}/repo"
export VANKOS_BUILD_DIR="${NATIVE_DIR}"
log "рабочий каталог: ${NATIVE_DIR} ($(fs_type "${NATIVE_DIR}"))"

# ---------------------------------------------------------- 1. брендинг/ассеты
if [[ ! -f "${PROJECT_DIR}/calamares/branding/vankos/logo.png" ]]; then
    if command -v python3 >/dev/null 2>&1 && python3 -c 'import PIL' >/dev/null 2>&1; then
        log "генерирую ассеты брендинга"
        python3 "${PROJECT_DIR}/tools/gen_branding.py" --root "${PROJECT_DIR}"
    else
        die "нет logo.png и нет python3-pillow (pacman -S python-pillow)"
    fi
fi

# ------------------------------------------------------------- 2. стейджинг
log "готовлю профиль в ${PROFILE_DIR}"
rm -rf "${PROFILE_DIR}"
mkdir -p "${PROFILE_DIR}"
cp -a "${PROJECT_DIR}/iso/." "${PROFILE_DIR}/"

# Конфигурация Calamares (в живом образе живёт в /etc/calamares).
install -d "${PROFILE_DIR}/airootfs/etc/calamares"
cp -a "${PROJECT_DIR}/calamares/." "${PROFILE_DIR}/airootfs/etc/calamares/"

# Списки пакетов, которые читают скрипты установщика.
install -d "${PROFILE_DIR}/airootfs/usr/share/vankos"
install -m 0644 "${PROJECT_DIR}"/iso/lists/target-base.txt "${PROFILE_DIR}/airootfs/usr/share/vankos/"
install -m 0644 "${PROJECT_DIR}"/iso/lists/gnome.txt      "${PROFILE_DIR}/airootfs/usr/share/vankos/"
install -m 0644 "${PROJECT_DIR}"/iso/lists/delta.txt      "${PROFILE_DIR}/airootfs/usr/share/vankos/"

chmod 0755 "${PROFILE_DIR}/airootfs/usr/local/bin/vankos-live-setup"
chmod 0755 "${PROFILE_DIR}/airootfs/usr/local/bin/vankos-installer"
chmod 0755 "${PROFILE_DIR}/airootfs/usr/local/bin/vankos-live-session"
chmod 0755 "${PROFILE_DIR}"/airootfs/usr/local/lib/vankos/*.sh
# sudo требует режим 0440, иначе молча игнорирует файл (и live-пользователь
# остаётся без sudo — установщик в этом случае не запускается).
chmod 0440 "${PROFILE_DIR}/airootfs/etc/sudoers.d/10-vankos-live"
chmod 0644 "${PROFILE_DIR}/airootfs/etc/polkit-1/rules.d/49-vankos-installer.rules"

# --- systemd: включённые юниты и цель загрузки ---
SYSTEMD_ETC="${PROFILE_DIR}/airootfs/etc/systemd/system"
install -d "${SYSTEMD_ETC}/multi-user.target.wants" "${SYSTEMD_ETC}/graphical.target.wants"
# Юнит лежит в /etc/systemd/system (а не в /usr/lib), поэтому и цель
# симлинка должна быть /etc/...; иначе systemctl считает его битым.
ln -sfn /etc/systemd/system/vankos-live-setup.service \
    "${SYSTEMD_ETC}/multi-user.target.wants/vankos-live-setup.service"
# Экран входа live-системы — greetd (автовход в Delta). Так же, как это
# делает systemctl enable: greetd.service объявляет Alias=display-manager.service,
# а graphical.target тянет display-manager.service.
ln -sfn /usr/lib/systemd/system/greetd.service "${SYSTEMD_ETC}/display-manager.service"
ln -sfn /usr/lib/systemd/system/graphical.target "${SYSTEMD_ETC}/default.target"

# --- CacheDir: пакеты складываем внутрь build/, а не в /var хоста ---
sed -i "s|^# @@VANKOS_CACHEDIR@@$|CacheDir = ${CACHE_DIR}|" "${PROFILE_DIR}/pacman.conf"
grep -q "CacheDir = ${CACHE_DIR}" "${PROFILE_DIR}/pacman.conf" \
    || die "не удалось подставить CacheDir в pacman.conf"

# --------------------- 2.5 свои пакеты (Calamares, Delta) и локальный репозиторий
# calamares ОТСУТСТВУЕТ в репозиториях Arch (только AUR), а AUR-рецепт
# выкидывает packagechooser — экран выбора рабочего стола. Поэтому собираем
# собственный пакет и подключаем каталог build/pkgs как [vankos-pkgs].
PKGS_DIR="${NATIVE_DIR}/pkgs"
install -d "${PKGS_DIR}"
# Скрипт сам решает, нужна ли пересборка: он сверяет pkgver/pkgrel из PKGBUILD
# с именем готового пакета. Так правка зависимостей (например, kcrash) не
# потеряется из-за старого файла в build/pkgs.
log "проверяю пакет Calamares"
"${PROJECT_DIR}/tools/build-calamares.sh"
# Delta — из исходников проекта, при каждой сборке. Его копию от прошлой сборки
# из кэша pacman убираем: имя то же, содержимое другое, и pacman счёл бы её битой.
log "собираю пакет Delta"
bash "${PROJECT_DIR}/tools/build-delta.sh"
rm -f "${CACHE_DIR}"/delta-*.pkg.tar.zst "${CACHE_DIR}"/delta-*.pkg.tar.zst.sig
mapfile -t local_pkgs < <(find "${PKGS_DIR}" -maxdepth 1 -type f -name '*.pkg.tar.zst' ! -name '*.sig' | sort)
((${#local_pkgs[@]} >= 2)) || die "в ${PKGS_DIR} нет пакетов Calamares и Delta — сборка не удалась"
rm -f "${PKGS_DIR}"/vankos-pkgs.db* "${PKGS_DIR}"/vankos-pkgs.files*
repo-add --quiet "${PKGS_DIR}/vankos-pkgs.db.tar.gz" "${local_pkgs[@]}" >/dev/null
if ! grep -q '^\[vankos-pkgs\]' "${PROFILE_DIR}/pacman.conf"; then
    cat >> "${PROFILE_DIR}/pacman.conf" <<EOF

[vankos-pkgs]
SigLevel = Optional TrustAll
Server = file://${PKGS_DIR}
EOF
fi
log "локальный репозиторий сборки: ${#local_pkgs[@]} пакет(ов) в ${PKGS_DIR}"
# Пакета delta нет в репозиториях Arch: для slim-ISO (установка из сети)
# установщик берёт его из образа (desktop.sh, pacman -U). Это ~1-2 МБ.
install -d "${PROFILE_DIR}/airootfs/usr/share/vankos/pkgs"
install -m 0644 "${PKGS_DIR}"/delta-*.pkg.tar.zst "${PROFILE_DIR}/airootfs/usr/share/vankos/pkgs/"

# ------- 2.6 до долгого скачивания проверяем, что все пакеты вообще существуют
# Раньше отсутствие calamares всплывало через 20 минут внутри mkarchiso.
log "проверяю доступность пакетов live-образа"
PREFLIGHT_DB="${NATIVE_DIR}/pacdb-preflight"
rm -rf "${PREFLIGHT_DB}"
install -d "${PREFLIGHT_DB}" "${CACHE_DIR}"
if pacman -Sy --dbpath "${PREFLIGHT_DB}" --config "${PROFILE_DIR}/pacman.conf" --noconfirm >/dev/null 2>&1; then
    mapfile -t live_pkgs < <(grep -vE '^[[:space:]]*(#|$)' "${PROFILE_DIR}/packages.x86_64")
    resolve_all() {
        pacman -Sp --dbpath "${PREFLIGHT_DB}" --config "${PROFILE_DIR}/pacman.conf" \
            --print-format '%n' "$@" >/dev/null 2>&1
    }
    if resolve_all "${live_pkgs[@]}"; then
        log "все ${#live_pkgs[@]} пакетов live-образа доступны"
    else
        missing_pkgs=()
        for pkg in "${live_pkgs[@]}"; do
            resolve_all "${pkg}" || missing_pkgs+=("${pkg}")
        done
        warn "нет в подключённых репозиториях: ${missing_pkgs[*]:-неизвестный пакет (сломанные зависимости)}"
        die "исправьте iso/packages.x86_64 — иначе mkarchiso упадёт"
    fi
else
    warn "не удалось синхронизировать базы pacman — пропускаю предварительную проверку"
fi

# --- обязательный archiso-хук в initramfs ---
# Без него ядро не находит ISO, root= не выставляется и загрузка уходит
# в emergency mode ("Timed out waiting for device /dev/gpt-auto-root").
MKINITCPIO_CONF="${PROFILE_DIR}/airootfs/etc/mkinitcpio.conf.d/archiso.conf"
[[ -f "${MKINITCPIO_CONF}" ]] || die "нет airootfs/etc/mkinitcpio.conf.d/archiso.conf — образ не загрузится"
grep -q 'archiso' "${MKINITCPIO_CONF}" || die "в archiso.conf нет хука archiso — образ не загрузится"
log "initramfs: archiso-хуки на месте"

# -------------------------------------------------- 3. офлайн-репозиторий
LOCAL_REPO="${PROFILE_DIR}/airootfs/var/cache/vankos/repo"
install -d "${LOCAL_REPO}"

if [[ "${OFFLINE}" == "1" ]]; then
    log "скачиваю пакеты для локального репозитория (может занять время)"
    rm -rf "${CACHE_DIR}" "${PACDB_DIR}" "${REPO_DIR}"
    mkdir -p "${CACHE_DIR}" "${PACDB_DIR}" "${REPO_DIR}"

    mapfile -t repo_pkgs < <(
        cat "${PROJECT_DIR}"/iso/lists/target-base.txt \
            "${PROJECT_DIR}"/iso/lists/gnome.txt \
            "${PROJECT_DIR}"/iso/lists/delta.txt \
        | grep -vE '^[[:space:]]*(#|$)' | sort -u
    )
    log "пакетов в списке: ${#repo_pkgs[@]}"

    # Изолированная база pacman: всё считается неустановленным,
    # поэтому скачиваются и сами пакеты, и все их зависимости.
    pacman -Syw --noconfirm --needed \
        --dbpath "${PACDB_DIR}" \
        --cachedir "${CACHE_DIR}" \
        --config "${PROFILE_DIR}/pacman.conf" \
        "${repo_pkgs[@]}"

    log "создаю базу локального репозитория"
    # Только пакеты: файлы подписей *.sig лежат рядом и ломают repo-add
    # ("bsdtar: Unrecognized archive format").
    mapfile -t pkg_files < <(
        find "${CACHE_DIR}" -maxdepth 1 -type f -name '*.pkg.tar.zst' ! -name '*.sig' | sort
    )
    ((${#pkg_files[@]})) || die "в кэше нет пакетов — проверьте списки и зеркала"
    # Сами пакеты должны лежать рядом с базой: раньше в ISO попадала только
    # vankos.db, и pacstrap в установщике падал. *.sig не копируем — тогда
    # repo-add не встраивает подписи, и офлайн-установке не нужна связка ключей.
    cp -l -- "${pkg_files[@]}" "${REPO_DIR}/" 2>/dev/null || cp -- "${pkg_files[@]}" "${REPO_DIR}/"
    mapfile -t repo_files < <(find "${REPO_DIR}" -maxdepth 1 -type f -name '*.pkg.tar.zst' | sort)
    repo-add --quiet --remove "${REPO_DIR}/vankos.db.tar.gz" "${repo_files[@]}" >/dev/null

    cp -al "${REPO_DIR}/." "${LOCAL_REPO}/" 2>/dev/null || cp -a "${REPO_DIR}/." "${LOCAL_REPO}/"
    repo_count=$(find "${LOCAL_REPO}" -maxdepth 1 -name '*.pkg.tar.zst' | wc -l)
    ((repo_count == ${#pkg_files[@]})) \
        || die "в офлайн-репозитории ${repo_count} пакетов из ${#pkg_files[@]}"
    repo_size=$(du -sh "${LOCAL_REPO}" | cut -f1)
    log "локальный репозиторий: ${#pkg_files[@]} пакетов, ${repo_size}"
else
    log "slim-режим: репозиторий не включается, установка пойдёт из сети"
    rmdir "${LOCAL_REPO}" 2>/dev/null || true
fi

# --------------------------------------------------------------- 4. сборка
log "запускаю mkarchiso (это долго: 20-60 минут)"
rm -rf "${WORK_DIR}"
mkdir -p "${OUT_DIR}"
# .sha256 без самого ISO (от прошлой неудачной сборки) только сбивает с толку.
for sum in "${OUT_DIR}"/*.iso.sha256; do
    if [[ -e "${sum}" && ! -e "${sum%.sha256}" ]]; then
        rm -f "${sum}"
    fi
done
mkarchiso -v -w "${WORK_DIR}" -o "${OUT_DIR}" "${PROFILE_DIR}"

# ------------------------------------------------------- 5. хеш и результат
# Проверяем, что в собранном initramfs действительно есть archiso-хуки.
# initramfs сжат (zstd/xz), поэтому grep по нему бесполезен — только lsinitcpio
# или распаковка. Ошибка здесь не фатальна: образ уже собран, а правду скажет
# только загрузка, поэтому предупреждаем, а не выбрасываем результат.
initrd_file=$(find "${WORK_DIR}" -name 'initramfs-linux.img' -type f 2>/dev/null | head -n1)
if [[ -n "${initrd_file}" ]]; then
    initrd_ok=0
    if command -v lsinitcpio >/dev/null 2>&1 \
        && lsinitcpio "${initrd_file}" 2>/dev/null | grep -q 'hooks/archiso'; then
        initrd_ok=1
    elif command -v zstd >/dev/null 2>&1 \
        && zstd -dc "${initrd_file}" 2>/dev/null | grep -aq 'archisosearchuuid'; then
        initrd_ok=1
    elif command -v xz >/dev/null 2>&1 \
        && xz -dc "${initrd_file}" 2>/dev/null | grep -aq 'archisosearchuuid'; then
        initrd_ok=1
    fi
    if ((initrd_ok)); then
        log "initramfs содержит archiso-хуки — ок"
    else
        warn "не удалось подтвердить archiso-хуки в initramfs — проверьте загрузку ISO"
    fi
fi

# Установщик должен запускаться из live-системы. Проверяем, что динамический
# загрузчик находит все библиотеки /usr/bin/calamares: это ловит забытые
# runtime-зависимости (именно так в ISO не попал libKF6Crash.so.6).
calamares_root="${WORK_DIR}/x86_64/airootfs"

# Без root-владельца и setuid у sudo/pkexec live-пользователь не получит root,
# и установщик не стартует (так бывает, если airootfs собран на NTFS).
for suid_bin in usr/bin/sudo usr/bin/pkexec; do
    f="${calamares_root}/${suid_bin}"
    [[ -e "${f}" ]] || continue
    if [[ "$(stat -c %u "${f}")" != 0 || ! -u "${f}" ]]; then
        die "/${suid_bin} в образе без root/setuid ($(stat -c '%U %a' "${f}")) — рабочий каталог на неподходящей ФС"
    fi
done
log "права sudo/pkexec в образе — ок"

# Скрипты, которые вызывает Calamares, должны быть исполняемыми (иначе код 126).
for script in usr/local/bin/vankos-installer usr/local/bin/vankos-live-session \
              usr/local/bin/vankos-live-setup usr/local/lib/vankos/bootstrap.sh \
              usr/local/lib/vankos/desktop.sh usr/local/lib/vankos/cleanup.sh; do
    [[ -x "${calamares_root}/${script}" ]] \
        || die "/${script} в образе не исполняемый — добавьте его в file_permissions в iso/profiledef.sh"
done
log "скрипты установщика исполняемые — ок"

# Live-сессия — это Delta через greetd: без них образ загрузится в чёрный экран.
for f in usr/bin/delta-session usr/bin/qs usr/bin/start-hyprland usr/bin/greetd usr/bin/cage \
         usr/share/delta/shell/shell.qml etc/systemd/system/display-manager.service; do
    # -L: абсолютные симлинки (display-manager.service) указывают внутрь образа, не хоста
    [[ -e "${calamares_root}/${f}" || -L "${calamares_root}/${f}" ]] \
        || die "в образе нет /${f} — live-сессия Delta не запустится"
done
log "Delta, greetd и безопасный режим в образе — ок"

chroot_bin="$(command -v chroot || true)"
if [[ -x "${calamares_root}/usr/bin/calamares" && -n "${chroot_bin}" ]]; then
    calamares_missing=$(env -i PATH=/usr/bin:/bin "${chroot_bin}" "${calamares_root}" \
        /usr/bin/ldd /usr/bin/calamares 2>&1 | grep 'not found' || true)
    if [[ -n "${calamares_missing}" ]]; then
        die "calamares в образе не запустится, не хватает библиотек: ${calamares_missing}"
    fi
    log "зависимости Calamares в образе на месте"
fi

iso_file=$(find "${OUT_DIR}" -maxdepth 1 -name '*.iso' -type f | sort | tail -n1)
[[ -n "${iso_file}" ]] || die "ISO не создан"
( cd "${OUT_DIR}" && sha256sum "$(basename "${iso_file}")" > "$(basename "${iso_file}").sha256" )

log "готово"
printf '\n  ISO:   %s\n  размер: %s\n  sha256: %s\n\n' \
    "${iso_file}" "$(du -h "${iso_file}" | cut -f1)" "$(cut -d' ' -f1 "${OUT_DIR}/"*.iso.sha256)"

cat <<'EOF'
Дальше:
  1. Проверьте образ в виртуалке:  ./tools/run-qemu.sh
  2. Запишите на флешку:           sudo dd if=build/out/vankos-*.iso of=/dev/sdX bs=4M status=progress oflag=sync
     (или используйте Ventoy / balenaEtcher)
EOF
