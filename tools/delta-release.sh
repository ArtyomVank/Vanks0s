#!/usr/bin/env bash
# ============================================================================
#  Vanks OS — новая версия Delta для обновлений «по воздуху».
#
#      tools/delta-release.sh 0.2.0
#
#  1. ставит pkgver в packaging/delta/PKGBUILD (pkgrel=1);
#  2. собирает пакет без root во временной папке (на NTFS makepkg не работает);
#  3. кладёт dist/delta-0.2.0-1-any.pkg.tar.zst и .sha256.
#
#  Дальше — релиз на GitHub (тег v0.2.0) с этим файлом. Установленные системы
#  найдут его сами: delta-update берёт последний релиз репозитория DELTA_REPO
#  (delta/defaults/update.conf). Файл delta-*.pkg.tar.zst должен быть в каждом
#  релизе, иначе «последний» релиз (например, только с ISO) его не даст.
# ============================================================================
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PKGBUILD="${PROJECT_DIR}/packaging/delta/PKGBUILD"
DIST="${PROJECT_DIR}/dist"

log() { printf '\033[1;35m[delta-release]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[delta-release] ОШИБКА:\033[0m %s\n' "$*" >&2; exit 1; }

ver=${1:-}
[[ ${ver} =~ ^[0-9]+(\.[0-9]+)*$ ]] || die "укажите версию: tools/delta-release.sh 0.2.0"
[[ ${EUID} -ne 0 ]] || die "запускайте без sudo: makepkg не работает от root"
command -v makepkg >/dev/null || die "нет makepkg — установите base-devel"

old=$(sed -n 's/^pkgver=//p' "${PKGBUILD}")
if [[ $(vercmp "${ver}" "${old}") -le 0 ]]; then
    die "версия ${ver} не новее текущей ${old}: установленные системы её не возьмут"
fi

# shellcheck source=/dev/null
DELTA_REPO=""; . "${PROJECT_DIR}/delta/defaults/update.conf"
[[ -n ${DELTA_REPO} ]] || log "внимание: DELTA_REPO в delta/defaults/update.conf пуст — системы не узнают, где искать обновления"

"${PROJECT_DIR}/tools/delta-shaders.sh" --check \
    || die "шейдеры не пересобраны: запустите tools/delta-shaders.sh"

log "версия ${old} → ${ver}"
sed -i -e "s/^pkgver=.*/pkgver=${ver}/" -e "s/^pkgrel=.*/pkgrel=1/" "${PKGBUILD}"

tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT
install -d "${tmp}/packaging/delta" "${DIST}"
cp -r "${PROJECT_DIR}/delta" "${tmp}/delta"
cp "${PKGBUILD}" "${tmp}/packaging/delta/PKGBUILD"
log "собираю пакет"
( cd "${tmp}/packaging/delta" && PKGDEST="${tmp}/out" makepkg -f --nodeps --noconfirm >/dev/null ) \
    || die "makepkg не смог собрать delta"

name="delta-${ver}-1-any.pkg.tar.zst"
[[ -f ${tmp}/out/${name} ]] || die "makepkg завершился, но ${name} не найден"
rm -f "${DIST}"/delta-*.pkg.tar.zst "${DIST}"/delta-*.pkg.tar.zst.sha256
cp "${tmp}/out/${name}" "${DIST}/${name}"
( cd "${DIST}" && sha256sum "${name}" > "${name}.sha256" )

log "готово: dist/${name}"
cat <<EOF

Опубликовать:
  1. GitHub → Releases → Draft a new release, тег v${ver}
  2. прикрепить dist/${name}
  3. Publish release
Через несколько часов (или по кнопке «Проверить» в Настройки → Обновления)
системы с DELTA_REPO="${DELTA_REPO:-не задан}" предложат обновиться.
EOF
