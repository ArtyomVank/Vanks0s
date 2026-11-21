#!/usr/bin/env bash
# Обои под акриловое стекло Delta: мягкие тёплые пятна света без мелких
# деталей — под стеклом панелей они размываются в ровный цветной фон, а
# «ленты» света дают стеклу блик и глубину. Рисуются с нуля (ImageMagick),
# одинаково при каждом запуске.
#
#   tools/gen-acrylic-walls.sh [папка]     по умолчанию delta/wallpapers/acrylic
#
# Заодно — живые варианты в delta/shell/wallpaper/super (1920×1080): кадр
# acrylic-<имя>.jpg, фон без лент …-base.jpg и ленты на чёрном …-rib.jpg —
# их оживляет шейдер super/acrylic.frag (пятна плывут, ленты колышутся).
#
# Каждый вариант: фон-градиент, большие пятна цвета (рисуются в 1/8 размера
# и размываются — так быстро), две-три размытые световые ленты и лёгкое
# зерно, чтобы на 10-битных и 8-битных экранах не было ступенек.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-"${ROOT}/delta/wallpapers/acrylic"}
LIVE=${ROOT}/delta/shell/wallpaper/super
W=3840 H=2160
w=$((W / 8)) h=$((H / 8))
mkdir -p "${OUT}"
command -v magick >/dev/null || { echo "нужен ImageMagick 7 (magick)" >&2; exit 1; }

# name  фон-верх  фон-низ  "пятна: цвет:x:y:rx:ry …" (в долях маленького холста, ×100)  "ленты: цвет:толщина:изгиб"
wall() {
    local name=$1 top=$2 bottom=$3 blobs=$4 ribbons=$5
    local args=() b c x y rx ry r t k
    for b in ${blobs}; do
        IFS=: read -r c x y rx ry <<<"${b}"
        args+=(-fill "${c}" -draw "ellipse $((w * x / 100)),$((h * y / 100)) $((w * rx / 100)),$((h * ry / 100)) 0,360")
    done
    # пятна: маленький холст, сильное размытие, растянуть до 4K
    magick -size "${w}x${h}" "gradient:${top}-${bottom}" "${args[@]}" \
        -depth 16 -blur 0x$((h / 5)) -resize "${W}x${H}!" -depth 16 \
        "${TMP}/base.miff"
    # ленты света: кривые Безье поперёк экрана, мягкие края
    args=()
    for r in ${ribbons}; do
        IFS=: read -r c t k <<<"${r}"
        args+=(-stroke "${c}" -strokewidth "${t}" -fill none
               -draw "path 'M -200,$((H * k / 100)) C $((W / 3)),$((H * (k - 30) / 100)) $((W * 2 / 3)),$((H * (k + 35) / 100)) $((W + 200)),$((H * (k - 10) / 100))'")
    done
    # живой вариант: фон без лент (лёгкое зерно — чтобы и он был без ступенек)
    magick "${TMP}/base.miff" -resize 1920x1080 -attenuate 0.12 +noise Gaussian \
        -sampling-factor 4:4:4 -quality 92 -strip "${LIVE}/acrylic-${name}-base.jpg"
    if [ "${#args[@]}" -gt 0 ]; then
        magick -size "${W}x${H}" xc:none "${args[@]}" -blur 0x60 "${TMP}/rib.miff"
        magick "${TMP}/rib.miff" -background black -flatten -resize 1920x1080 \
            -sampling-factor 4:4:4 -quality 92 -strip "${LIVE}/acrylic-${name}-rib.jpg"
        magick "${TMP}/base.miff" "${TMP}/rib.miff" -compose screen -composite "${TMP}/base.miff"
    fi
    # зерно против ступенек градиента
    magick "${TMP}/base.miff" -attenuate 0.18 +noise Gaussian \
        -sampling-factor 4:4:4 -quality 90 -strip "${OUT}/delta-acrylic-${name}.jpg"
    # готовый кадр живых обоев: его берут темы, линза стекла и экран входа
    magick "${OUT}/delta-acrylic-${name}.jpg" -resize 1920x1080 -quality 90 -strip "${LIVE}/acrylic-${name}.jpg"
    echo "${OUT}/delta-acrylic-${name}.jpg"
}

TMP=$(mktemp -d)
trap 'rm -rf "${TMP:?}"' EXIT

# Янтарь — цвета превью «Акрила»: бирюзовая ночь сверху, тёплое свечение снизу
wall amber "#1B2C31" "#3A2A1E" \
    "#B0702E:70:95:55:45 #E39A4A:28:100:30:30 #2E5560:15:10:40:35 #6B3F24:90:40:30:30" \
    "#F4B36A55:90:62 #FFD9A033:50:80"
# Закат — сливовый, коралловый, золото
wall sunset "#241732" "#4A2233" \
    "#E0567F:25:80:40:35 #F09A2B:75:95:45:40 #7C5CFF:80:15:35:30 #3B2A8F:10:20:30:30" \
    "#FFB38A55:110:55 #FF7FA833:60:30"
# Лагуна — глубокая синь, бирюза, мята
wall lagoon "#0C1A2B" "#0F2E3A" \
    "#1F8A99:30:75:45:40 #2BC4F0:80:30:30:30 #3FB37A:70:95:35:30 #1A3D6B:10:15:35:30" \
    "#8FF0E055:90:58 #6FD3FF33:50:28"
# Графит — почти чёрный с медным светом, для тёмных столов без пестроты
wall graphite "#121214" "#1E1A18" \
    "#8A4B2A:80:85:40:35 #3A3A44:20:20:40:35 #C0703A:95:100:20:20" \
    "#E0905044:70:70"
# Утро — светлая: сливки, персик, небо (под светлую тему)
wall morning "#F4EDE4" "#F7D9C4" \
    "#FFC9A8:25:85:45:40 #BFD9F2:80:20:40:35 #F6B98A:85:90:30:30 #E9E2FF:10:15:30:30" \
    "#FFFFFF88:100:60 #FFF3E066:50:30"
