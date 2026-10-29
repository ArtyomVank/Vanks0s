#!/usr/bin/env bash
# Сборка шейдеров оболочки Delta: *.vert / *.frag → *.qsb (формат Qt RHI).
# .qsb лежат в репозитории рядом с исходниками, поэтому пакету qsb не нужен;
# запускать после правки шейдера. `--check` — только проверить, что .qsb не
# старее исходника (это делает tools/delta-dev.sh check).
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
qsb=$(command -v qsb || echo /usr/lib/qt6/bin/qsb)
mode=${1:-build}

status=0
while IFS= read -r -d '' src; do
    out=${src}.qsb
    if [ "${mode}" = --check ]; then
        if [ ! -f "${out}" ] || [ "${src}" -nt "${out}" ]; then
            echo "[delta-shaders] не собран: ${src#"${root}"/} (запустите tools/delta-shaders.sh)" >&2
            status=1
        fi
        continue
    fi
    [ -x "${qsb}" ] || { echo "[delta-shaders] нет qsb (пакет qt6-shadertools)" >&2; exit 1; }
    # GLSL для OpenGL/ES, SPIR-V для Vulkan — Quickshell берёт тот, что у него
    "${qsb}" --glsl "100es,120,150" --hlsl 50 --msl 12 -o "${out}" "${src}"
    echo "[delta-shaders] ${out#"${root}"/}"
done < <(find "${root}/delta/shell" \( -name '*.vert' -o -name '*.frag' \) -print0)
exit "${status}"
