#!/usr/bin/env bash
# ============================================================================
#  Vanks OS — демо-видео и снимки Delta для README.
#
#      tools/delta-demo.sh            запись в build/demo/ (видео + снимки)
#
#  Чистая вложенная сессия 1920×1080 на скрытом спецстоле: первая настройка
#  с нуля, смена обоев и тем, окно приложений, меню доков, «джинн»,
#  «Настройки» на английском, запуск .exe, экран блокировки. Всё ведётся через
#  IPC оболочки, мышь не нужна. Пока идёт запись, основной Hyprland рисует
#  невидимое окно с 60 к/с (misc:render_unfocused_fps), потом значение
#  возвращается.
#
#  Готовое — в build/demo/: delta-demo.mp4 (полное), delta-demo-github.mp4
#  (до 10 МБ), poster.jpg и screens/*.jpg. В docs/media их кладут руками.
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
shot() { WAYLAND_DISPLAY=${disp} grim -t jpeg -q 90 "${OUT}/screens/$1.jpg"; }
run() { "${DEV}" exec "$@" >/dev/null 2>&1 & }
pause() { sleep "$1"; }

W_SUNSET=ddg_1774716902087709339.jpg      # горы на закате
W_NEON=ddg_1_1787483202206757186.jpg      # неоновый город
W_HOLE=ddg_1776280415303827002.jpg        # чёрная дыра
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

# --- чистый дом сессии: только виджеты, город и стартовые обои ---------------
"${DEV}" stop >/dev/null 2>&1 || true
rm -rf "${HOME_DIR}" "${OUT}"
mkdir -p "${HOME_DIR}/.config/delta" "${OUT}/screens"
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

# --- запись -------------------------------------------------------------------
hyprctl eval 'hl.config({ misc = { render_unfocused_fps = 60 } })' >/dev/null
log "вложенная сессия"
"${DEV}" nested 900 >/dev/null
disp=$(cat "${HOME_DIR}/.nested-display" 2>/dev/null || true)
[ -n "${disp}" ] || { log "не нашёл дисплей вложенной сессии"; exit 1; }
WAYLAND_DISPLAY=${disp} wf-recorder -y -r 60 -c libx264 -p crf=16 -p preset=veryfast \
    -f "${OUT}/raw.mp4" >/dev/null 2>&1 &
rec=$!
log "запись идёт (${disp})"

# 1. первая настройка: капли стекаются, язык (на миг — английский), шаги
pause 6.5;  shot 01-oobe-language
set_ language.ui '"en"'; pause 1.8
set_ language.ui '"ru"'; pause 1.2
ipc oobe next;  pause 1.4
set_ appearance.theme '"cosmos"'; set_ appearance.accent '"#B07CFF"'; pause 1.6
shot 02-oobe-look
ipc oobe next;  pause 1.2
wall "${W_NEON}"; pause 2.0
shot 03-oobe-wallpaper
ipc oobe next;  pause 1.0
set_ docks.top.length '"tiles"'; pause 1.4
set_ docks.top.length '"full"';  pause 1.0
ipc oobe next;  pause 1.6
ipc oobe next;  pause 1.6
shot 04-oobe-start
ipc oobe finish; pause 4.2

# 2. рабочий стол, окно приложений
shot 05-desktop-neon
ipc shell overlay launcher; pause 2.4
shot 06-launcher
ipc shell overlay launcher; pause 1.0

# 3. другие обои и тема
wall "${W_HOLE}"; set_ appearance.theme '"neon"'; set_ appearance.accent '"#00E5FF"'; pause 2.6
shot 07-desktop-blackhole
ipc docks menu sound; pause 2.0
shot 08-menu-sound
ipc docks menu sound; pause 0.6
ipc docks menu calendar; pause 2.0
ipc docks menu calendar; pause 0.8

# 4. окно и «джинн»
run kitty; pause 2.2
addr=$("${DEV}" exec hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.class == "kitty") | .address' | head -n1)
ipc minimize toggle "${addr#0x}"; pause 1.8
ipc minimize toggle "${addr#0x}"; pause 1.6
ipc minimize toggle "${addr#0x}"; pause 1.2

# 5. «Настройки»: язык — English, сразу на лету
wall "${W_LAKE}"; set_ appearance.theme '"aurora"'; set_ appearance.accent '"#3EE6B0"'; pause 1.8
run delta-settings language; pause 3.0
set_ language.ui '"en"'; pause 2.4
shot 09-settings-english
set_ language.ui '"ru"'; pause 1.2
"${DEV}" exec delta-settings ipc call settings quit >/dev/null 2>&1 || true
pause 1.2

# 6. программа Windows: «обычно или через лаунчер»
run delta-exe "${OUT}/Setup.exe"; pause 3.2
shot 10-exe-launcher
"${DEV}" exec pkill -f exe-app.qml >/dev/null 2>&1 || true
pause 1.0

# 7. экран блокировки с уведомлениями
wall "${W_CANYON}"; set_ appearance.theme '"sunset"'; set_ appearance.accent '"#FF8A4C"'; pause 1.6
"${DEV}" exec notify-send -a Telegram "Аня" "Встречаемся в 19:00 у входа?" >/dev/null 2>&1 || true
"${DEV}" exec notify-send -a Steam "Загрузка завершена" "Cyberpunk 2077 готов к запуску" >/dev/null 2>&1 || true
pause 1.5
ipc lock lock; pause 3.5
shot 11-lock
ipc lock unlock; pause 2.6

# 8. финал: синтвейв и плитки
wall "${W_SYNTH}"; set_ appearance.theme '"cosmos"'; set_ appearance.accent '"#B07CFF"'; set_ docks.top.length '"tiles"'; pause 3.0
shot 12-desktop-synthwave
pause 1.0

kill -INT "${rec}"; wait "${rec}" 2>/dev/null || true; rec=""
log "сжимаю"
ffmpeg -v error -y -i "${OUT}/raw.mp4" -c:v libx264 -crf 20 -preset slow -pix_fmt yuv420p -movflags +faststart "${OUT}/delta-demo.mp4"
dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "${OUT}/delta-demo.mp4")
# GitHub показывает видео до 10 МБ: битрейт под 9.5 МБ
kbps=$(awk -v d="${dur}" 'BEGIN { printf "%d", 9.5 * 8192 / d }')
ffmpeg -v error -y -i "${OUT}/delta-demo.mp4" -c:v libx264 -b:v "${kbps}k" -maxrate "${kbps}k" -bufsize "$((kbps * 2))k" \
    -preset slow -pix_fmt yuv420p -movflags +faststart -an "${OUT}/delta-demo-github.mp4"
cp "${OUT}/screens/05-desktop-neon.jpg" "${OUT}/poster.jpg"
rm -f "${OUT}/raw.mp4" "${OUT}/Setup.exe"
log "готово: ${OUT} ($(du -h "${OUT}/delta-demo-github.mp4" | cut -f1) для GitHub, ${dur%.*} с)"
