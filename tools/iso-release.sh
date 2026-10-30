#!/usr/bin/env bash
# ============================================================================
#  Vanks OS — образ для релиза GitHub и программа установки.
#
#      tools/iso-release.sh build/out/vankos-2026.10.30-x86_64.iso
#
#  GitHub не принимает файлы больше 2 ГБ, поэтому образ режется на куски по
#  1900 МиБ: <образ>.part0, .part1, … и <образ>.sha256 — сумма целого образа.
#  Vanks Setup (setup/) собирает их обратно и сверяет сумму. Ещё собирается
#  dist/vanks-setup.pyz — та же программа одним файлом (python3 vanks-setup.pyz).
#
#  Куски кладутся в dist/<имя образа>/. Выкладывает их человек — команда
#  gh release upload печатается в конце (сам скрипт ничего не публикует).
# ============================================================================
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="${PROJECT_DIR}/dist"
PART=1900M

log() { printf '\033[1;35m[iso-release]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[iso-release] ОШИБКА:\033[0m %s\n' "$*" >&2; exit 1; }

iso=${1:-}
[ -f "${iso}" ] || die "укажите образ: tools/iso-release.sh build/out/vankos-….iso"
name=$(basename "${iso}")
out="${DIST}/${name%.iso}"
mkdir -p "${out}"
rm -f "${out}/${name}".part*

log "режу ${name} на куски по ${PART}"
split -b "${PART}" -d -a 1 "${iso}" "${out}/${name}.part"
log "sha256 целого образа"
(cd "$(dirname "${iso}")" && sha256sum "${name}") > "${out}/${name}.sha256"
ls -l "${out}"

"${PROJECT_DIR}/tools/build-setup.sh"

tag=${2:-vX.Y.Z}
log "готово. Выложить в релиз (тег ${tag}):"
# пути — с кавычками: в них бывают пробелы («Новый том»)
printf '    gh release upload %q %q.part* %q %q\n' \
    "${tag}" "${out}/${name}" "${out}/${name}.sha256" "${DIST}/vanks-setup.pyz"
