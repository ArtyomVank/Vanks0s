#!/usr/bin/env bash
# ============================================================================
#  Vanks OS — сборка Calamares в пакет для live-образа.
#
#  calamares отсутствует в репозиториях Arch, поэтому собираем его сами
#  по рецепту packaging/calamares/PKGBUILD (с модулем packagechooser).
#  Готовый пакет кладётся в build/pkgs/ и подключается как локальный
#  репозиторий [vankos-pkgs] при сборке ISO.
#
#  Запуск:  sudo ./tools/build-calamares.sh
#  Повторный запуск ничего не делает, только если пакет уже собран из
#  текущей версии PKGBUILD (pkgver/pkgrel). После правки рецепта
#  (например, добавления зависимости) пакет пересобирается.
# ============================================================================
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# build.sh передаёт сюда свой рабочий каталог (на NTFS это ext4-образ).
BUILD_DIR="${VANKOS_BUILD_DIR:-${PROJECT_DIR}/build}"
SRC_DIR="${BUILD_DIR}/calamares-src"
OUT_DIR="${BUILD_DIR}/pkgs"
BUILD_USER="${VANKOS_BUILD_USER:-vankosbuild}"
SUDOERS_FILE="/etc/sudoers.d/vankos-build"

log()  { printf '\033[1;35m[vankos/calamares]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[vankos/calamares] ОШИБКА:\033[0m %s\n' "$*" >&2; exit 1; }

[[ ${EUID} -eq 0 ]] || die "нужен root: sudo ./tools/build-calamares.sh"
command -v makepkg >/dev/null 2>&1 || die "нет makepkg — установите base-devel"
pacman -Qq base-devel >/dev/null 2>&1 || die "не установлен base-devel: sudo pacman -S base-devel"

install -d "${OUT_DIR}"

# На NTFS/FAT chown не работает: пользователь сборки не может писать в
# каталог, и makepkg падает с «Не удалось создать каталог $BUILDDIR».
case "$(findmnt -no FSTYPE -T "${BUILD_DIR}" 2>/dev/null)" in
    ntfs|ntfs3|fuseblk|vfat|msdos|exfat)
        die "${BUILD_DIR} на NTFS/FAT — запускайте через sudo ./build.sh (он соберёт в ext4-образе) или задайте VANKOS_BUILD_DIR на ext4" ;;
esac

# Имя готового пакета зависит от pkgver/pkgrel. Проверяем именно актуальное
# имя, иначе после изменения зависимостей в PKGBUILD в build/pkgs остался бы
# старый (сломанный) пакет, и build.sh молча положил бы его в ISO.
PKGBUILD_FILE="${PROJECT_DIR}/packaging/calamares/PKGBUILD"
pkgver="$(sed -n 's/^pkgver=//p' "${PKGBUILD_FILE}" | head -n1)"
pkgrel="$(sed -n 's/^pkgrel=//p' "${PKGBUILD_FILE}" | head -n1)"
[[ -n "${pkgver}" && -n "${pkgrel}" ]] \
    || die "не удалось прочитать pkgver/pkgrel из ${PKGBUILD_FILE}"

EXPECTED_PKG="${OUT_DIR}/calamares-${pkgver}-${pkgrel}-x86_64.pkg.tar.zst"
if [[ -f "${EXPECTED_PKG}" ]]; then
    log "пакет уже собран: $(basename "${EXPECTED_PKG}")"
    exit 0
fi

# Старые сборки (другая pkgrel/зависимости) не должны попасть в [vankos-pkgs]:
# build.sh добавляет туда все calamares-*.pkg.tar.zst, и pacman может выбрать
# не тот пакет.
if compgen -G "${OUT_DIR}/calamares-*.pkg.tar.zst" >/dev/null; then
    log "пакет Calamares устарел (нужен ${pkgver}-${pkgrel}) — пересобираю"
    rm -f "${OUT_DIR}"/calamares-*.pkg.tar.zst "${OUT_DIR}"/calamares-*.pkg.tar.zst.sig
fi

# --- пользователь для makepkg (makepkg нельзя запускать от root) ---
if ! id "${BUILD_USER}" >/dev/null 2>&1; then
    log "создаю пользователя сборки ${BUILD_USER}"
    useradd --system --create-home --home-dir "/var/tmp/${BUILD_USER}" --shell /bin/bash "${BUILD_USER}"
fi

cleanup() { rm -f "${SUDOERS_FILE}"; }
trap cleanup EXIT

# makepkg -s ставит зависимости через pacman: разрешаем только pacman.
printf '%s ALL=(ALL) NOPASSWD: /usr/bin/pacman\n' "${BUILD_USER}" > "${SUDOERS_FILE}"
chmod 0440 "${SUDOERS_FILE}"

# --- исходники и рецепт ---
rm -rf "${SRC_DIR}"
install -d "${SRC_DIR}"
install -m 0644 "${PROJECT_DIR}/packaging/calamares/PKGBUILD" "${SRC_DIR}/PKGBUILD"
chown -R "${BUILD_USER}:${BUILD_USER}" "${SRC_DIR}"

log "собираю Calamares 3.4.2 (первый раз 5–15 минут)"
if ! ( cd "${SRC_DIR}" && MAKEFLAGS="-j$(nproc)" sudo -u "${BUILD_USER}" \
        makepkg -s --noconfirm --nocheck --cleanbuild ); then
    die "makepkg не смог собрать Calamares — смотрите вывод выше"
fi

built=$(find "${SRC_DIR}" -maxdepth 1 -name 'calamares-*.pkg.tar.zst' -type f | head -n1)
[[ -n "${built}" ]] || die "makepkg завершился, но пакет не найден"

install -m 0644 "${built}" "${OUT_DIR}/"
chown root:root "${OUT_DIR}/$(basename "${built}")"
log "готово: $(basename "${built}")"
log "пакет: ${OUT_DIR}/$(basename "${built}")"
