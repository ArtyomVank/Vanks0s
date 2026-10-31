#!/usr/bin/env bash
# ============================================================================
#  Vanks OS — промо-ролик и карточки нововведений версии (сейчас 0.6).
#
#      tools/delta-promo.sh          запись в build/promo/
#      tools/delta-promo.sh --post   заново подписи, сжатие и карточки (raw.mkv цел)
#
#  Как tools/delta-demo.sh, но короче и быстрее: сцены по 3–6 секунд, у
#  каждой подпись (сцена отмечается в сценарии — mark «заголовок» «пояснение»,
#  подписи накладываются потом). Чистая вложенная сессия 1920×1080 на скрытом
#  спецстоле, всё через IPC — мышь не нужна. Пока идёт запись, основной
#  Hyprland рисует невидимое окно с 60 к/с (misc:render_unfocused_fps), потом
#  значение возвращается.
#
#  Готовое — в build/promo/:
#      vanks-os-<версия>.mp4         ролик 1080p60 с подписями (для релиза)
#      vanks-os-<версия>-small.mp4   он же до ~24 МБ (для README)
#      screens/*.jpg                 снимки как есть
#      cards/*.jpg                   карточки: снимок в рамке, фон и заголовок
# ============================================================================
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=${PROMO_VERSION:-0.6}
OUT=${PROJECT_DIR}/build/promo
WALLS=${PROJECT_DIR}/wallpapers
DEV=${PROJECT_DIR}/tools/delta-dev.sh

export DELTA_DEV_NAME=promo DELTA_DEV_HIDDEN=1 DELTA_DEV_SIZE="1920 1080" DELTA_DEV_PRIVATE_BUS=1
export DELTA_WALLPAPERS=${WALLS}
HOME_DIR=${PROJECT_DIR}/build/delta-home-promo
FONT="Google Sans"

log() { printf '\033[1;35m[delta-promo]\033[0m %s\n' "$*"; }
ipc() { "${DEV}" ipc call "$@" >/dev/null 2>&1 || true; }
set_() { ipc shell set "$1" "$2"; }
wall() { set_ wallpaper.path "\"${WALLS}/$1\""; }
shot() { WAYLAND_DISPLAY=${disp} grim -t jpeg -q 94 "${OUT}/screens/$1.jpg"; }
dx() { "${DEV}" exec "$@" >/dev/null 2>&1 || true; }
run() { "${DEV}" exec "$@" >/dev/null 2>&1 & }
hl() { dx hyprctl dispatch "$1"; }
pause() { sleep "$1"; }
# стиль панелей — со всеми его значениями, как кнопка в «Оформлении»
style() {
    case "$1" in
        material) set_ appearance.glass 0.97; set_ appearance.radius 26; set_ windows.rounding 20; set_ windows.blur false; set_ windows.border 0 ;;
        delta)    set_ appearance.glass 0.62; set_ appearance.radius 18; set_ windows.rounding 16; set_ windows.blur true;  set_ windows.border 2 ;;
        liquid)   set_ appearance.glass 0.4;  set_ appearance.radius 26; set_ windows.rounding 22; set_ windows.blur true;  set_ windows.border 1 ;;
    esac
    set_ appearance.style "\"$1\""
}
look() { set_ appearance.theme "\"$1\""; set_ appearance.accent "\"$2\""; }
# сцена: время от начала записи и подпись
mark() { printf '%s\t%s\t%s\n' "$(awk -v a="${t0}" -v b="$(date +%s.%N)" 'BEGIN { printf "%.2f", b - a }')" "$1" "${2:-}" >> "${OUT}/marks.tsv"; }
# окно вложенной сессии по классу → закрыть (pid вложенного процесса, не хоста)
close_class() {
    local pid
    pid=$("${DEV}" exec hyprctl clients -j 2>/dev/null | jq -r --arg c "$1" '.[] | select(.class == $c) | .pid' | head -n1)
    [ -n "${pid}" ] && [ "${pid}" != null ] && kill "${pid}" 2>/dev/null || true
}

W_NEON=ddg_1_1787483202206757186.jpg      # неоновый город
W_SUNSET=ddg_1774716902087709339.jpg      # горы на закате
W_LAKE=ddg_1774713637476461374.jpg        # озеро
W_CANYON=ddg_1776373765829978071.jpg      # каньон, аниме
W_SYNTH=ddg_1_1788813541452677585.jpg     # синтвейв
W_RAIN=ddg_15_1788816512258034258.jpg     # город за окном, дождь
W_WAVES=ddg_10_1788293329304360379.jpg    # бумажные волны
W_LIVE=d339a891-0598-4979-8e32-7e911fbf3cd0.mp4   # живые: чёрная дыра над планетой

old_fps=$(hyprctl getoption misc:render_unfocused_fps -j 2>/dev/null | jq -r '.int // 15')
cleanup() {
    hyprctl eval "hl.config({ misc = { render_unfocused_fps = ${old_fps} } })" >/dev/null 2>&1 || true
    [ -n "${rec:-}" ] && kill -INT "${rec}" 2>/dev/null || true
    "${DEV}" stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

# --- подписи, сжатие и карточки (отдельно: tools/delta-promo.sh --post) ------
post() {
    end=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "${OUT}/raw.mkv")
    mkdir -p "${OUT}/captions" "${OUT}/cards"
    # --- подписи: плашка внизу слева, крупная — на заставке и в финале ------------
    caption() {  # файл заголовок пояснение крупно(0/1)
        local f=$1 big=$4 t s pad=34
        if [ "${big}" = 1 ]; then t=72; s=30; else t=40; s=22; fi
        magick -background none pango:"<span font=\"${FONT} Bold ${t}\" foreground=\"white\">$2</span>
<span font=\"${FONT} ${s}\" foreground=\"#ffffffd0\">$3</span>" +repage "${OUT}/captions/text.png"
        local w h
        read -r w h < <(magick identify -format '%w %h\n' "${OUT}/captions/text.png")
        magick -size $((w + pad * 2 + 14))x$((h + pad * 2)) xc:none \
            -fill 'rgba(10,10,18,0.62)' -draw "roundrectangle 0,0 $((w + pad * 2 + 13)),$((h + pad * 2 - 1)) 30,30" \
            -fill '#8ab4ff' -draw "roundrectangle ${pad},$((pad + 6)) $((pad + 5)),$((h + pad - 6)) 3,3" \
            "${OUT}/captions/text.png" -geometry +$((pad + 22))+${pad} -composite "${f}"
    }
    n=$(wc -l < "${OUT}/marks.tsv")
    inputs=() filter="" last="[0:v]"
    for k in $(seq 1 "${n}"); do
        IFS=$'\t' read -r st title sub < <(sed -n "${k}p" "${OUT}/marks.tsv")
        next=$(sed -n "$((k + 1))p" "${OUT}/marks.tsv" | cut -f1)
        [ -n "${next}" ] || next=${end}
        big=0; { [ "${k}" = 1 ] || [ "${k}" = "${n}" ]; } && big=1
        caption "${OUT}/captions/${k}.png" "${title}" "${sub}" "${big}"
        dur=$(awk -v a="${st}" -v b="${next}" -v l="${big}" 'BEGIN { d = b - a - 0.25; if (d > 3.6 && !l) d = 3.6; printf "%.2f", d }')
        inputs+=(-loop 1 -t "${dur}" -i "${OUT}/captions/${k}.png")
        if [ "${big}" = 1 ]; then pos="x=(W-w)/2:y=(H-h)/2+220"; else pos="x=64:y=H-h-150"; fi
        filter+="[${k}:v]format=rgba,fade=in:st=0:d=0.35:alpha=1,fade=out:st=$(awk -v d="${dur}" 'BEGIN { printf "%.2f", d - 0.35 }'):d=0.35:alpha=1,setpts=PTS-STARTPTS+${st}/TB[c${k}];"
        filter+="${last}[c${k}]overlay=${pos}:eof_action=pass[v${k}];"
        last="[v${k}]"
    done
    ffmpeg -v error -y -i "${OUT}/raw.mkv" "${inputs[@]}" -filter_complex "${filter%;}" -map "${last}" \
        -c:v libx264 -crf 17 -preset slow -pix_fmt yuv420p -movflags +faststart -an "${OUT}/vanks-os-${VERSION}.mp4"
    dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "${OUT}/vanks-os-${VERSION}.mp4")
    kbps=$(awk -v d="${dur}" 'BEGIN { printf "%d", 24 * 8192 / d }')
    ( cd "${OUT}" &&
      ffmpeg -v error -y -i "vanks-os-${VERSION}.mp4" -c:v libx264 -b:v "${kbps}k" -preset slow -pass 1 -an -f null /dev/null &&
      ffmpeg -v error -y -i "vanks-os-${VERSION}.mp4" -c:v libx264 -b:v "${kbps}k" -maxrate "$((kbps * 3))k" -bufsize "$((kbps * 4))k" \
          -preset slow -pass 2 -pix_fmt yuv420p -movflags +faststart -an "vanks-os-${VERSION}-small.mp4" &&
      rm -f ffmpeg2pass-0.log ffmpeg2pass-0.log.mbtree )

    # --- карточки: снимок в скруглённой рамке с тенью на размытом фоне ------------
    card() {  # снимок заголовок пояснение
        local src=${OUT}/screens/$1.jpg dst=${OUT}/cards/$1.jpg
        [ -f "${src}" ] || return 0
        magick "${src}" -resize 1520x855 \
            \( +clone -alpha extract -fill black -colorize 100 -fill white -draw 'roundrectangle 0,0 1519,854 28,28' \) \
            -alpha off -compose CopyOpacity -composite "${OUT}/captions/shot.png"
        magick -background none pango:"<span font=\"${FONT} Bold 54\" foreground=\"white\">$2</span>
<span font=\"${FONT} 26\" foreground=\"#ffffffcc\">$3</span>" +repage "${OUT}/captions/ctext.png"
        magick "${src}" -resize 1920x1080^ -gravity center -extent 1920x1080 -blur 0x40 -modulate 70,130 \
            \( -size 1920x1080 gradient:'rgba(0,0,0,0.15)-rgba(0,0,0,0.55)' \) -composite \
            \( "${OUT}/captions/shot.png" -background 'rgba(0,0,0,0.7)' -shadow 60x24+0+18 \) -gravity north -geometry +0+190 -composite \
            "${OUT}/captions/shot.png" -gravity north -geometry +0+190 -composite \
            "${OUT}/captions/ctext.png" -gravity northwest -geometry +200+46 -composite \
            -quality 92 "${dst}"
    }
    card 01-desktop-material "Vanks OS ${VERSION}" "Material You: цвета панелей и виджетов — из обоев"
    card 03-launcher-menu    "Ярлыки приложений" "Правый щелчок в меню приложений → «Ярлык на рабочий стол»"
    card 04-shortcut-added   "Ярлык на рабочем столе" "Щелчок открывает приложение, ярлык отвечает волной"
    card 06-widget-menu      "Меню виджета" "Правый щелчок по виджету: открыть, настроить, убрать"
    card 08-store-home       "Магазин Delta" "Пакеты Arch и Flathub в одном окне, подборка по разделам"
    card 09-store-app        "Страница приложения" "Источник на выбор: Arch или Flathub, установка в очереди"
    card 11-delta-box        "Delta Box" "Программы Windows в одной общей системе"
    card 12-settings-all     "Настройки по папкам" "Все разделы на одном экране"
    card 13-settings-anim    "Скорость анимаций" "От 0,3x до 4x — для окон и оболочки"
    card 14-lock             "Экран блокировки" "Виджеты, фото и уведомления"
    card 17-style-liquid     "Ваш стиль" "Delta, Жидкое стекло, GNOME или Material You"

    log "готово: ${OUT} (ролик ${dur%.*} с, $(du -h "${OUT}/vanks-os-${VERSION}.mp4" | cut -f1); для README $(du -h "${OUT}/vanks-os-${VERSION}-small.mp4" | cut -f1))"
}

if [ "${1:-}" = --post ]; then trap - EXIT; post; exit 0; fi

# --- чистый дом: Material You, виджеты с ярлыками, фото, Delta Box ----------
"${DEV}" stop >/dev/null 2>&1 || true
rm -rf "${HOME_DIR}" "${OUT}"
mkdir -p "${HOME_DIR}/.config/delta" "${OUT}/screens" "${OUT}/cards" "${OUT}/covers" "${OUT}/captions"
jq -n --arg wall "${WALLS}/${W_SUNSET}" \
      --argjson photos "$(printf '%s\n' "${WALLS}/${W_LAKE}" "${WALLS}/${W_CANYON}" "${WALLS}/${W_NEON}" | jq -R . | jq -s .)" '{
  version: 1,
  oobe: { done: true },
  wallpaper: { path: $wall, video: false },
  weather: { city: "Москва" },
  appearance: { style: "material", glass: 0.97, radius: 26 },
  windows: { rounding: 20, blur: false, border: 0 },
  widgets: {
    desktop: [
      { id: "clock", c: 5, r: 1, w: 7, h: 3, bg: false, style: "tall", tallWidth: 0.35 },
      { id: "weather", c: 0, r: 0, w: 4, h: 2, bg: true, mode: "wide" },
      { id: "photo", c: 0, r: 2, w: 4, h: 3, bg: true, mode: "fast", photos: $photos },
      { id: "cpu", c: 13, r: 0, w: 2, h: 2, bg: true, mode: "wavy" },
      { id: "ram", c: 15, r: 0, w: 2, h: 2, bg: true, mode: "wavy" },
      { id: "music", c: 13, r: 6, w: 4, h: 3, bg: true, mode: "long" },
      { id: "app:org.gnome.Nautilus", c: 5, r: 6, w: 2, h: 2, bg: true, mode: "named" },
      { id: "app:steam", c: 7, r: 6, w: 2, h: 2, bg: true, mode: "named" },
      { id: "app:org.telegram.desktop", c: 9, r: 6, w: 2, h: 2, bg: true, mode: "named" }
    ],
    lock: [
      { id: "clock", c: 4, r: 0, w: 9, h: 4, bg: false, style: "tall", tallWidth: 0.35, color: "accent" },
      { id: "photo", c: 0, r: 5, w: 4, h: 3, bg: true, mode: "fast", photos: $photos },
      { id: "notifs", c: 11, r: 6, w: 6, h: 3, bg: false, mode: "list" },
      { id: "weather", c: 0, r: 0, w: 4, h: 2, bg: true, mode: "row" },
      { id: "music", c: 13, r: 0, w: 4, h: 2, bg: true, mode: "wide" }
    ]
  }
}' > "${HOME_DIR}/.config/delta/settings.json"

# Delta Box: пять программ «уже скопированы» — папки с .exe, список, ярлыки
BOX=${HOME_DIR}/.local/share/delta/prefixes/delta-box
APPS=${HOME_DIR}/.local/share/applications
ICONS=${HOME_DIR}/.local/share/delta/box-icons
mkdir -p "${BOX}/drive_c/Program Files" "${APPS}" "${ICONS}"
db='{"apps":{}}'
i=0
for spec in "Notepad++|#3DBA4E|N++" "Paint.NET|#2F7BFF|P" "7-Zip|#222831|7z" "foobar2000|#F2A541|fb" "IrfanView|#E2364E|iV"; do
    IFS='|' read -r name color label <<<"${spec}"
    dir="${BOX}/drive_c/Program Files/${name}"
    mkdir -p "${dir}"
    printf 'MZ' > "${dir}/${name}.exe"
    magick -size 256x256 xc:none -fill "${color}" -draw 'roundrectangle 8,8 248,248 56,56' \
        \( -background none pango:"<span font=\"${FONT} Bold 64\" foreground=\"white\">${label}</span>" -trim +repage \) \
        -gravity center -geometry +0+0 -composite "${ICONS}/${i}.png"
    cat > "${APPS}/delta-exe-delta-box-${i}.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=${name}
Exec=true
Icon=${ICONS}/${i}.png
X-Delta-Prefix=delta-box
X-Delta-Exe=${dir}/${name}.exe
EOF
    db=$(jq --arg n "${name}" --arg x "${dir}/${name}.exe" --argjson t "$((1761900000 + i))" '.apps[$n] = { exe: $x, added: $t }' <<<"${db}")
    i=$((i + 1))
done
printf '%s\n' "${db}" > "${BOX}/.delta-box.json"

# обложки проигрывателя
C=${OUT}/covers
magick -size 600x600 gradient:'#2a0b4a-#ff4f8b' \
    \( -size 600x600 xc:none -fill '#ffd36e' -draw 'circle 300,330 300,170' \
       -fill '#2a0b4a' -draw 'rectangle 0,300 600,312' -draw 'rectangle 0,345 600,360' \
       -draw 'rectangle 0,392 600,410' -draw 'rectangle 0,440 600,600' \) -composite \
    -quality 90 "${C}/cover-1.jpg"
magick -size 600x600 gradient:'#ff9a3c-#7a1fa2' -swirl 220 -blur 0x4 -quality 90 "${C}/cover-2.jpg"
magick -size 600x600 gradient:'#0b3d5c-#3ee6b0' -swirl 160 -blur 0x3 -quality 90 "${C}/cover-3.jpg"

# --- запись -------------------------------------------------------------------
hyprctl eval 'hl.config({ misc = { render_unfocused_fps = 60 } })' >/dev/null
log "вложенная сессия"
"${DEV}" nested 900 >/dev/null
disp=$(cat "${HOME_DIR}/.nested-display" 2>/dev/null || true)
[ -n "${disp}" ] || { log "не нашёл дисплей вложенной сессии"; exit 1; }
echo 'hl.config({ cursor = { invisible = true } })' >> "${HOME_DIR}/.config/delta/hypr/user.lua"
dx hyprctl eval 'hl.config({ cursor = { invisible = true } })'
run python3 "${PROJECT_DIR}/tools/demo-player.py" "${C}"
# каталог Flathub для магазина собирается заранее, чтобы подборка открылась сразу
dx delta-store index
pause 6
WAYLAND_DISPLAY=${disp} wf-recorder -y -r 60 -c libx264 -p crf=10 -p preset=ultrafast \
    -f "${OUT}/raw.mkv" >/dev/null 2>&1 &
rec=$!
t0=$(date +%s.%N)
log "запись идёт (${disp})"

# 1. заставка: рабочий стол в Material You
pause 0.6
mark "Vanks OS ${VERSION}" "Большое обновление Delta"
pause 2.6
shot 01-desktop-material

# 2. Material You: обои меняются — цвета панелей и виджетов за ними
mark "Material You" "Цвета панелей берутся из обоев"
wall "${W_NEON}";   pause 1.7
wall "${W_CANYON}"; pause 1.7
shot 02-material-canyon
wall "${W_LAKE}";   pause 1.9

# 3. ярлык из меню приложений: поиск, правый щелчок, «Ярлык на рабочий стол»
mark "Ярлыки приложений" "Правый щелчок в меню → «Ярлык на рабочий стол»"
ipc shell launcher ""; pause 1.0
for q in d di dis disc; do ipc shell launcher "${q}"; pause 0.16; done
pause 0.5
ipc shell launcherMenu; pause 1.5
shot 03-launcher-menu
ipc widgets app discord
pause 0.25; ipc shell overlay launcher
pause 2.2
shot 04-shortcut-added

# 4. щелчок по ярлыку — волна, пружинка, приложение открыто
mark "Щелчок — и приложение открыто" "Ярлык отвечает на нажатие волной"
ipc widgets launch app:org.gnome.Nautilus; pause 0.35
shot 05-shortcut-ripple
pause 2.4
close_class org.gnome.Nautilus; pause 1.2

# 5. правый щелчок по виджету: меню и «Настроить виджет»
mark "Меню виджета" "Правый щелчок: открыть, настроить, убрать"
ipc widgets menu app:steam; pause 1.6
shot 06-widget-menu
ipc widgets menu app:steam; pause 0.3
ipc widgets menu clock; pause 1.3
ipc widgets edit; ipc widgets select clock; pause 2.0
shot 07-widget-edit
ipc widgets done; pause 1.0

# 6. магазин Delta: подборка, раздел, страница приложения, поиск
mark "Магазин Delta" "Пакеты Arch и Flathub в одном окне"
run delta-store; pause 3.0
shot 08-store-home
dx delta-store ipc call store scroll 520; pause 1.4
dx delta-store ipc call store go section games; pause 1.6
dx delta-store ipc call store open com.heroicgameslauncher.hgl; pause 2.2
shot 09-store-app
dx delta-store ipc call store find minecraft; pause 2.2
shot 10-store-search
dx delta-store ipc call store quit; pause 0.9

# 7. Delta Box: одна система Windows на все программы
mark "Delta Box" "Программы Windows в одной общей системе"
run delta-box; pause 2.8
shot 11-delta-box
dx delta-box ipc call box quit; pause 0.9

# 8. «Настройки»: все разделы папками, скорость анимаций
mark "Настройки по папкам" "И новая «Скорость анимаций»"
run delta-settings all; pause 2.4
shot 12-settings-all
dx delta-settings ipc call settings open windows; pause 1.4
dx delta-settings ipc call settings scroll 620; pause 1.2
set_ windows.animSpeed 0.5; pause 1.4
shot 13-settings-anim
set_ windows.animSpeed 1
dx delta-settings ipc call settings quit; pause 0.9

# 9. экран блокировки: виджеты, фото, уведомления
mark "Экран блокировки" "Свои виджеты, фото и уведомления"
dx notify-send -a Telegram "Аня" "Встречаемся в 19:00 у входа?"
dx notify-send -a Steam "Загрузка завершена" "Игра готова к запуску"
pause 0.6
ipc lock lock; pause 3.2
shot 14-lock
ipc lock unlock; pause 2.0

# 10. «желе», «джинн» и рабочие столы
mark "Живые окна" "«Желе», «джинн» и рабочие столы"
run kitty -o background='#16161e' -o background_opacity=0.9 -o foreground='#c0caf5' \
    -o font_size=13 -o window_padding_width=14 sh -c 'fastfetch; exec sh'
pause 2.0
addr=$("${DEV}" exec hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.class == "kitty") | .address' | head -n1)
ipc minimize toggle "${addr#0x}"; pause 0.3
shot 15-genie
pause 1.2
ipc minimize toggle "${addr#0x}"; pause 1.4
hl 'hl.dsp.focus({ workspace = 2 })'; pause 1.1
hl 'hl.dsp.focus({ workspace = 1 })'; pause 1.2
close_class kitty; pause 0.8

# 11. финал: стили и обои сменяются быстро
mark "Ваш стиль" "Delta · Жидкое стекло · Material You · живые обои"
style delta;  look neon "#00E5FF"; wall "${W_SYNTH}"; pause 1.3
shot 16-style-delta
style liquid; look cosmos "#B07CFF"; wall "${W_RAIN}"; pause 1.3
shot 17-style-liquid
style delta;  look sakura "#E0567F"; wall "${W_WAVES}"; pause 1.3
style material; wall "${W_LIVE}"; pause 2.0
shot 18-live-material
mark "Vanks OS ${VERSION}" "github.com/ArtyomVank/Vanks0s"
pause 3.2

kill -INT "${rec}"; wait "${rec}" 2>/dev/null || true; rec=""
log "запись готова, подписи"
post
rm -f "${OUT}/raw.mkv"

