#!/usr/bin/env bash
# Запекание обоев «Вершина» (wallpaper/super/peak.jpg, peak-mask.png) из
# tools/bake/peak.frag. Нужна графическая сессия Wayland (подойдёт вложенная:
# WAYLAND_DISPLAY=… tools/bake/bake.sh). Считается долго — секунды на кадр.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
super="${here}/../../delta/shell/wallpaper/super"
tmp=$(mktemp -d)
trap 'rm -rf "${tmp:?}"' EXIT
qsb=$(command -v qsb || echo /usr/lib/qt6/bin/qsb)
"${qsb}" --glsl "100es,120,150" --hlsl 50 --msl 12 -o "${tmp}/peak.frag.qsb" "${here}/peak.frag"
BAKE_FRAG="${tmp}/peak.frag.qsb" BAKE_OUT="${tmp}/peak" BAKE_SIZE="${BAKE_SIZE:-2560 1440}" \
    timeout 120 qs -p "${here}/bake.qml"
magick "${tmp}/peak.png" -quality 90 "${super}/peak.jpg"
# маски мягкие — хватит половины размера
magick "${tmp}/peak-mask.png" -resize 50% -depth 8 -define png:color-type=2 "${super}/peak-mask.png"
echo "[bake] ${super}/peak.jpg, peak-mask.png"
