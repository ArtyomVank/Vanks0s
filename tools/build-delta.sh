#!/usr/bin/env bash
# ============================================================================
#  Vanks OS — пакет окружения Delta для live-образа и офлайн-репозитория.
#
#  Рецепт — packaging/delta/PKGBUILD, исходники — delta/ в этом репозитории.
#  Пакет собирается при каждом запуске: компилировать нечего (arch=any),
#  а версия в PKGBUILD не меняется при каждой правке QML.
#  Готовый пакет кладётся в build/pkgs/ рядом с Calamares ([vankos-pkgs]).
#
#  Запуск:  sudo ./tools/build-delta.sh   (обычно его вызывает build.sh)
# ============================================================================
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# build.sh передаёт сюда свой рабочий каталог (на NTFS это ext4-образ).
BUILD_DIR="${VANKOS_BUILD_DIR:-${PROJECT_DIR}/build}"
SRC_DIR="${BUILD_DIR}/delta-src"
OUT_DIR="${BUILD_DIR}/pkgs"
BUILD_USER="${VANKOS_BUILD_USER:-vankosbuild}"

log()  { printf '\033[1;35m[vankos/delta]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[vankos/delta] ОШИБКА:\033[0m %s\n' "$*" >&2; exit 1; }

[[ ${EUID} -eq 0 ]] || die "нужен root: sudo ./tools/build-delta.sh"
command -v makepkg >/dev/null 2>&1 || die "нет makepkg — установите base-devel"

case "$(findmnt -no FSTYPE -T "${BUILD_DIR}" 2>/dev/null)" in
    ntfs|ntfs3|fuseblk|vfat|msdos|exfat)
        die "${BUILD_DIR} на NTFS/FAT — запускайте через sudo ./build.sh (он соберёт в ext4-образе) или задайте VANKOS_BUILD_DIR на ext4" ;;
esac

# Шейдеры ставятся уже собранными (.qsb): устаревший .qsb — это старая анимация в ISO.
"${PROJECT_DIR}/tools/delta-shaders.sh" --check \
    || die "шейдеры Delta не пересобраны: запустите tools/delta-shaders.sh (нужен qt6-shadertools)"

# --- пользователь для makepkg (makepkg нельзя запускать от root) ---
if ! id "${BUILD_USER}" >/dev/null 2>&1; then
    log "создаю пользователя сборки ${BUILD_USER}"
    useradd --system --create-home --home-dir "/var/tmp/${BUILD_USER}" --shell /bin/bash "${BUILD_USER}"
fi

# --- исходники: та же раскладка, что в репозитории (PKGBUILD берёт ../../delta) ---
rm -rf "${SRC_DIR}"
install -d "${SRC_DIR}/packaging/delta"
cp -r "${PROJECT_DIR}/delta" "${SRC_DIR}/delta"
install -m 0644 "${PROJECT_DIR}/packaging/delta/PKGBUILD" "${SRC_DIR}/packaging/delta/PKGBUILD"
chown -R "${BUILD_USER}:${BUILD_USER}" "${SRC_DIR}"

log "собираю пакет delta"
# --nodeps: зависимости (Hyprland, Quickshell…) нужны в образе, а не на сборочной машине
if ! ( cd "${SRC_DIR}/packaging/delta" && sudo -u "${BUILD_USER}" \
        makepkg -f --nodeps --noconfirm ); then
    die "makepkg не смог собрать delta — смотрите вывод выше"
fi

built=$(find "${SRC_DIR}/packaging/delta" -maxdepth 1 -name 'delta-*.pkg.tar.zst' -type f | head -n1)
[[ -n "${built}" ]] || die "makepkg завершился, но пакет не найден"

install -d "${OUT_DIR}"
# прежняя сборка с тем же именем, но другим содержимым не должна остаться рядом
rm -f "${OUT_DIR}"/delta-*.pkg.tar.zst "${OUT_DIR}"/delta-*.pkg.tar.zst.sig
install -m 0644 "${built}" "${OUT_DIR}/"
chown root:root "${OUT_DIR}/$(basename "${built}")"
log "готово: ${OUT_DIR}/$(basename "${built}")"

# --- обои Vanks OS: отдельный пакет, пересобираем только при новой версии ---
# (180 МБ картинок — сжимать их на каждой сборке ISO незачем)
wp_ver=$(sed -n 's/^pkgver=//p; s/^pkgrel=//p' "${PROJECT_DIR}/packaging/vankos-wallpapers/PKGBUILD" | paste -sd-)
if compgen -G "${OUT_DIR}/vankos-wallpapers-${wp_ver}-any.pkg.tar.zst" >/dev/null; then
    log "обои ${wp_ver} уже собраны"
else
    log "собираю пакет vankos-wallpapers ${wp_ver}"
    install -d "${SRC_DIR}/packaging/vankos-wallpapers"
    cp -r "${PROJECT_DIR}/wallpapers" "${SRC_DIR}/wallpapers"
    install -m 0644 "${PROJECT_DIR}/packaging/vankos-wallpapers/PKGBUILD" "${SRC_DIR}/packaging/vankos-wallpapers/PKGBUILD"
    chown -R "${BUILD_USER}:${BUILD_USER}" "${SRC_DIR}"
    ( cd "${SRC_DIR}/packaging/vankos-wallpapers" && sudo -u "${BUILD_USER}" makepkg -f --nodeps --noconfirm ) \
        || die "makepkg не смог собрать vankos-wallpapers"
    wp=$(find "${SRC_DIR}/packaging/vankos-wallpapers" -maxdepth 1 -name 'vankos-wallpapers-*.pkg.tar.zst' -type f | head -n1)
    [[ -n "${wp}" ]] || die "пакет vankos-wallpapers не найден после сборки"
    rm -f "${OUT_DIR}"/vankos-wallpapers-*.pkg.tar.zst
    install -m 0644 "${wp}" "${OUT_DIR}/"
    log "готово: ${OUT_DIR}/$(basename "${wp}")"
fi
