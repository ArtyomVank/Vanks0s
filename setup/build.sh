#!/usr/bin/env bash
# ============================================================================
#  Vanks Setup одним исполняемым файлом (PyInstaller):
#      Linux   → dist/vanks-setup-linux-x86_64
#      Windows → dist/VanksSetup.exe   (Git Bash или GitHub Actions)
#
#      setup/build.sh                 # нужен python3 с pip
#
#  Ставит PySide6-Essentials и PyInstaller во временное окружение
#  build/setup-venv. В .exe — запрос прав администратора при запуске
#  (--uac-admin): запись на флешку в Windows без них невозможна.
# ============================================================================
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VENV="${ROOT}/build/setup-venv"
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) WIN=1 ;; *) WIN=0 ;; esac
if [ "${WIN}" = 1 ]; then
    # PyInstaller — обычная программа Windows: /d/a/… ей непонятен, нужен D:/a/…
    ROOT="$(cygpath -m "${ROOT}")"; VENV="${ROOT}/build/setup-venv"; BIN="${VENV}/Scripts"; SEP=";"
else
    BIN="${VENV}/bin"; SEP=":"
fi

[ -x "${BIN}/python" ] || python3 -m venv "${VENV}" 2>/dev/null || python -m venv "${VENV}"
"${BIN}/python" -m pip install -q --upgrade pip
"${BIN}/python" -m pip install -q PySide6-Essentials pyinstaller certifi
# значок .exe из logo.png — PyInstaller переводит его в .ico через Pillow
[ "${WIN}" = 1 ] && "${BIN}/python" -m pip install -q pillow

cd "${ROOT}/setup"
name=$([ "${WIN}" = 1 ] && echo VanksSetup || echo vanks-setup-linux-x86_64)
spec="${ROOT}/build/setup-pyinstaller/${name}.spec"
args=(--onefile --name "${name}" --specpath "${ROOT}/build/setup-pyinstaller"
      --add-data "${ROOT}/setup/vanks_setup/gui${SEP}vanks_setup/gui"
      --hidden-import vanks_setup.gui --hidden-import certifi
      # лишние модули Qt — минус десятки мегабайт
      --exclude-module PySide6.QtWebEngineCore --exclude-module PySide6.QtMultimedia --exclude-module PySide6.Qt3DCore
      --exclude-module tkinter)
if [ "${WIN}" = 1 ]; then
    args+=(--windowed --uac-admin --icon "${ROOT}/setup/vanks_setup/gui/logo.png")
fi
"${BIN}/pyi-makespec" "${args[@]}" vanks-setup.py >/dev/null
if [ "${WIN}" = 0 ]; then
    # fontconfig и freetype — системные: свой старый fontconfig (сборка на
    # Ubuntu 22.04) не понимает настройки шрифтов новых систем (Arch) и сыплет
    # ошибками. Они есть в любом Linux с рабочим столом.
    "${BIN}/python" - "${spec}" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
s = s.replace("pyz = PYZ(", "a.binaries = [b for b in a.binaries if not b[0].startswith(('libfontconfig', 'libfreetype'))]\npyz = PYZ(", 1)
open(p, "w", encoding="utf-8").write(s)
PY
fi
"${BIN}/pyinstaller" --noconfirm --clean --distpath "${ROOT}/dist" --workpath "${ROOT}/build/setup-pyinstaller" "${spec}"
ls -l "${ROOT}/dist" | grep -iE "vanks-?setup"
