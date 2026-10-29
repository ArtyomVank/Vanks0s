#!/usr/bin/env bash
# ============================================================================
#  Vanks OS — демо-видео и снимки Delta для README и релиза.
#
#      tools/delta-demo.sh            запись в build/demo/ (видео + снимки)
#
#  Чистая вложенная сессия 1920×1080 на скрытом спецстоле: первая настройка
#  с нуля, музыка на острове, окно приложений, живые и обычные обои, темы
#  (и светлая), меню доков, «джинн», рабочие столы, редактор виджетов,
#  уведомления, «Настройки» на английском, запуск .exe, экран блокировки.
#  Всё ведётся через IPC оболочки, мышь не нужна. Музыка — tools/demo-player.py
#  (MPRIS без звука). Пока идёт запись, основной Hyprland рисует невидимое окно
#  с 60 к/с (misc:render_unfocused_fps), потом значение возвращается.
#
#  Пишется почти без сжатия (x264 ultrafast — меньше нагрузки, ни одного
#  пропущенного кадра), сжимается потом. Готовое — в build/demo/:
#      delta-demo.mp4          1080p60 для README (до ~25 МБ)
#      delta-demo-full.mp4     1080p60 в полном качестве — для релиза
#      poster.jpg, screens/*.jpg
#  В docs/media их кладут руками.
# ============================================================================
set -euo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUT=${PROJECT_DIR}/build/demo
WALLS=${PROJECT_DIR}/wallpapers
DEV=${PROJECT_DIR}/tools/delta-dev.sh

export DELTA_DEV_NAME=demo DELTA_DEV_HIDDEN=1 DELTA_DEV_SIZE="1920 1080" DELTA_DEV_PRIVATE_BUS=1
# первая настройка появится сама, как при первом входе; обои — из папки проекта
export DELTA_OOBE=1 DELTA_WALLPAPERS=${WALLS}
HOME_DIR=${PROJECT_DIR}/build/delta-home-demo

log() { printf '\033[1;35m[delta-demo]\033[0m %s\n' "$*"; }
ipc() { "${DEV}" ipc call "$@" >/dev/null 2>&1 || true; }
set_() { ipc shell set "$1" "$2"; }
wall() { set_ wallpaper.path "\"${WALLS}/$1\""; }
look() { set_ appearance.theme "\"$1\""; set_ appearance.accent "\"$2\""; }
shot() { WAYLAND_DISPLAY=${disp} grim -t jpeg -q 92 "${OUT}/screens/$1.jpg"; }
dx() { "${DEV}" exec "$@" >/dev/null 2>&1 || true; }
run() { "${DEV}" exec "$@" >/dev/null 2>&1 & }
hl() { dx hyprctl dispatch "$1"; }
pause() { sleep "$1"; }

W_SUNSET=ddg_1774716902087709339.jpg      # горы на закате
W_NEON=ddg_1_1787483202206757186.jpg      # неоновый город
W_LIVE=d339a891-0598-4979-8e32-7e911fbf3cd0.mp4   # живые: чёрная дыра над планетой
W_RAIN=ddg_15_1788816512258034258.jpg     # город за окном, дождь
W_WAVES=ddg_10_1788293329304360379.jpg    # бумажные волны (светлая тема)
W_LAKE=ddg_1774713637476461374.jpg        # озеро
W_CANYON=ddg_1776373765829978071.jpg      # каньон, аниме
W_SYNTH=ddg_1_1788813541452677585.jpg     # синтвейв

old_fps=$(hyprctl getoption misc:render_unfocused_fps -j 2>/dev/null | jq -r '.int // 15')
cleanup() {
    hyprctl eval "hl.config({ misc = { render_unfocused_fps = ${old_fps} } })" >/dev/null 2>&1 || true
    [ -n "${rec:-}" ] && kill -INT "${rec}" 2>/dev/null || true
    "${DEV}" stop >/dev/null 2>&1 || true
}
trap cleanup EXIT

# --- чистый дом сессии: виджеты, город, стартовые обои -----------------------
"${DEV}" stop >/dev/null 2>&1 || true
rm -rf "${HOME_DIR}" "${OUT}"
mkdir -p "${HOME_DIR}/.config/delta" "${OUT}/screens" "${OUT}/covers"
jq -n --arg wall "${WALLS}/${W_SUNSET}" '{
  version: 1,
  wallpaper: { path: $wall, video: false },
  weather: { city: "Москва" },
  widgets: {
    desktop: [
      { id: "clock", c: 5, r: 1, w: 7, h: 3, bg: false, style: "tall", tallWidth: 0.35 },
      { id: "music", c: 13, r: 6, w: 4, h: 3, bg: true, mode: "long" },
      { id: "weather", c: 0, r: 0, w: 4, h: 2, bg: true, mode: "wide" },
      { id: "cpu", c: 13, r: 0, w: 2, h: 2, bg: true, mode: "wavy" },
      { id: "ram", c: 15, r: 0, w: 2, h: 2, bg: true, mode: "wavy" },
      { id: "calendar", c: 0, r: 6, w: 4, h: 3, bg: true }
    ],
    lock: [
      { id: "clock", c: 4, r: 0, w: 9, h: 4, bg: false, style: "tall", tallWidth: 0.35, color: "accent" },
      { id: "notifs", c: 11, r: 6, w: 6, h: 3, bg: false, mode: "list" },
      { id: "weather", c: 0, r: 0, w: 4, h: 2, bg: true, mode: "row" },
      { id: "music", c: 13, r: 0, w: 4, h: 2, bg: true, mode: "wide" }
    ]
  }
}' > "${HOME_DIR}/.config/delta/settings.json"
printf 'MZ' > "${OUT}/Setup.exe"

# обложки для проигрывателя: закатное солнце, вихрь, затмение
C=${OUT}/covers
magick -size 600x600 gradient:'#2a0b4a-#ff4f8b' \
    \( -size 600x600 xc:none -fill '#ffd36e' -draw 'circle 300,330 300,170' \
       -fill '#2a0b4a' -draw 'rectangle 0,300 600,312' -draw 'rectangle 0,345 600,360' \
       -draw 'rectangle 0,392 600,410' -draw 'rectangle 0,440 600,600' \) -composite \
    -quality 90 "${C}/cover-1.jpg"
magick -size 600x600 gradient:'#ff9a3c-#7a1fa2' -swirl 220 -blur 0x4 -quality 90 "${C}/cover-2.jpg"
magick -size 600x600 xc:'#05060f' \
    \( -size 600x600 xc:none -stroke '#ffcf8a' -strokewidth 26 -fill none -draw 'circle 300,300 300,165' -blur 0x22 \) -compose screen -composite \
    \( -size 600x600 xc:none -fill '#05060f' -draw 'circle 300,300 300,180' \) -compose over -composite \
    -quality 90 "${C}/cover-3.jpg"

# --- запись -------------------------------------------------------------------
hyprctl eval 'hl.config({ misc = { render_unfocused_fps = 60 } })' >/dev/null
log "вложенная сессия"
"${DEV}" nested 1200 >/dev/null
disp=$(cat "${HOME_DIR}/.nested-display" 2>/dev/null || true)
[ -n "${disp}" ] || { log "не нашёл дисплей вложенной сессии"; exit 1; }
# курсор не нужен: в user.lua, чтобы пережил перезагрузку конфига при смене темы
echo 'hl.config({ cursor = { invisible = true } })' >> "${HOME_DIR}/.config/delta/hypr/user.lua"
dx hyprctl eval 'hl.config({ cursor = { invisible = true } })'
WAYLAND_DISPLAY=${disp} wf-recorder -y -r 60 -c libx264 -p crf=10 -p preset=ultrafast \
    -f "${OUT}/raw.mkv" >/dev/null 2>&1 &
rec=$!
log "запись идёт (${disp})"

# 1. первая настройка: капли стекаются, язык (на миг — английский), шаги
pause 7.0;  shot 01-oobe-language
set_ language.ui '"en"'; pause 2.0
set_ language.ui '"ru"'; pause 1.4
ipc oobe next;  pause 1.8
look cosmos "#B07CFF"; pause 1.8
shot 02-oobe-look
ipc oobe next;  pause 1.5
wall "${W_NEON}"; pause 2.2
shot 03-oobe-wallpaper
ipc oobe next;  pause 1.2
set_ docks.top.length '"tiles"'; pause 1.5
set_ docks.top.length '"full"';  pause 1.2
ipc oobe next;  pause 1.6
ipc oobe next;  pause 1.8
ipc oobe finish; pause 4.5
shot 04-desktop-neon

# 2. музыка: остров на верхнем доке, меню с обложкой, следующий трек
run python3 "${PROJECT_DIR}/tools/demo-player.py" "${C}"
pause 3.0;  shot 05-island-music
ipc docks menu media; pause 2.8
shot 06-menu-media
dx playerctl next; pause 2.4
ipc docks menu media; pause 1.0
ipc docks toggleMedia; pause 1.6        # обратно к модулям, музыка играет дальше

# 3. окно приложений
ipc shell overlay launcher; pause 2.6
shot 07-launcher
ipc shell overlay launcher; pause 1.4

# 4. живые обои и тема «Неон»: меню звука и погоды
wall "${W_LIVE}"; look neon "#00E5FF"; pause 3.4
shot 08-live-wallpaper
ipc docks menu sound; pause 2.4
shot 09-menu-sound
ipc docks menu sound; pause 0.8
ipc docks menu weather; pause 2.4
shot 10-menu-weather
ipc docks menu weather; pause 1.2

# 5. окно, «джинн» и рабочие столы
wall "${W_RAIN}"; look amber "#FFB020"; pause 2.4
run kitty -o background='#16161e' -o background_opacity=0.88 -o foreground='#c0caf5' \
    -o font_size=13 -o window_padding_width=14 sh -c 'fastfetch -s title:separator:os:kernel:wm:terminal:cpu:gpu:memory:break:colors; exec sh'
pause 2.6
addr=$("${DEV}" exec hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.class == "kitty") | .address' | head -n1)
ipc minimize toggle "${addr#0x}"; pause 0.28
shot 11-genie
pause 1.8
ipc minimize toggle "${addr#0x}"; pause 1.8
hl 'hl.dsp.focus({ workspace = 2 })'; pause 1.6
ipc docks menu workspaces; pause 2.4
shot 12-menu-workspaces
ipc docks menu workspaces; pause 0.6
hl 'hl.dsp.focus({ workspace = 1 })'; pause 1.6
ipc minimize toggle "${addr#0x}"; pause 1.8

# 6. светлая тема и редактор виджетов
wall "${W_WAVES}"; look sakura "#E0567F"; pause 2.8
shot 13-light-theme
ipc widgets edit; pause 1.6
ipc widgets select music; pause 2.0
shot 14-widgets-edit
ipc widgets done; pause 1.6

# 7. уведомления: всплывают, потом центр уведомлений
wall "${W_CANYON}"; look sunset "#FF8A4C"; pause 2.2
dx notify-send -a Telegram "Аня" "Встречаемся в 19:00 у входа?"
pause 1.2
dx notify-send -a Steam "Загрузка завершена" "Cyberpunk 2077 готов к запуску"
pause 2.6
ipc shell center; pause 2.4
shot 15-notification-center
ipc shell center; pause 1.2

# 8. «Настройки»: язык — English, сразу на лету
wall "${W_LAKE}"; look aurora "#3EE6B0"; pause 2.0
run delta-settings language; pause 3.0
set_ language.ui '"en"'; pause 2.6
shot 16-settings-english
set_ language.ui '"ru"'; pause 1.4
dx delta-settings ipc call settings quit
pause 1.4

# 9. программа Windows: «обычно или через лаунчер»
run delta-exe "${OUT}/Setup.exe"; pause 3.2
shot 17-exe-launcher
dx pkill -f exe-app.qml
pause 1.4

# 10. экран блокировки: музыка, погода, уведомления
wall "${W_SUNSET}"; look sunset "#FF8A4C"; pause 2.0
ipc lock lock; pause 3.4
shot 18-lock
dx playerctl next; pause 2.4
ipc lock unlock; pause 2.8

# 11. финал: синтвейв и плитки
wall "${W_SYNTH}"; look cosmos "#B07CFF"; set_ docks.top.length '"tiles"'; pause 3.4
shot 19-desktop-synthwave
pause 1.2

kill -INT "${rec}"; wait "${rec}" 2>/dev/null || true; rec=""
log "сжимаю"
ffmpeg -v error -y -i "${OUT}/raw.mkv" -c:v libx264 -crf 16 -preset slow -pix_fmt yuv420p \
    -movflags +faststart -an "${OUT}/delta-demo-full.mp4"
dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "${OUT}/delta-demo-full.mp4")
# для README: два прохода под ~24 МБ — 1080p60 без «мыла» в движении
kbps=$(awk -v d="${dur}" 'BEGIN { printf "%d", 24 * 8192 / d }')
( cd "${OUT}" &&
  ffmpeg -v error -y -i delta-demo-full.mp4 -c:v libx264 -b:v "${kbps}k" -preset slow -pass 1 -an -f null /dev/null &&
  ffmpeg -v error -y -i delta-demo-full.mp4 -c:v libx264 -b:v "${kbps}k" -maxrate "$((kbps * 3))k" -bufsize "$((kbps * 4))k" \
      -preset slow -pass 2 -pix_fmt yuv420p -movflags +faststart -an delta-demo.mp4 &&
  rm -f ffmpeg2pass-0.log ffmpeg2pass-0.log.mbtree )
cp "${OUT}/screens/04-desktop-neon.jpg" "${OUT}/poster.jpg"
rm -f "${OUT}/raw.mkv" "${OUT}/Setup.exe"
log "готово: ${OUT} ($(du -h "${OUT}/delta-demo.mp4" | cut -f1) для README, ${dur%.*} с)"
