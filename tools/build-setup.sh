#!/usr/bin/env bash
# ============================================================================
#  Vanks Setup одним файлом: dist/vanks-setup.pyz (нужен только python3).
#
#      tools/build-setup.sh
#      python3 dist/vanks-setup.pyz --list
#
#  Окно (setup/vanks_setup/gui) в .pyz тоже есть: оно откроется, если в
#  системе стоит PySide6, иначе программа работает в терминале. Сборку .exe
#  для Windows и отдельного файла для Linux делает GitHub Actions
#  (.github/workflows/setup.yml).
# ============================================================================
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="${PROJECT_DIR}/dist"
tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT

mkdir -p "${DIST}"
cp -r "${PROJECT_DIR}/setup/vanks_setup" "${tmp}/"
find "${tmp}" -name __pycache__ -prune -exec rm -rf {} +
python3 -m zipapp "${tmp}" -m "vanks_setup.__main__:main" -p "/usr/bin/env python3" -c -o "${DIST}/vanks-setup.pyz"
printf '\033[1;35m[build-setup]\033[0m %s\n' "${DIST}/vanks-setup.pyz ($(du -h "${DIST}/vanks-setup.pyz" | cut -f1))"
