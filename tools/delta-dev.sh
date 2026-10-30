#!/usr/bin/env bash
# Delta — инструменты разработчика.
#
#   tools/delta-dev.sh check            проверки без запуска: bash -n, JSON, конфиг Hyprland
#   tools/delta-dev.sh nested [сек]     Delta во вложенном Hyprland (окно в текущей сессии)
#   tools/delta-dev.sh fresh [сек]      как первый запуск: чистые настройки, при входе экран
#                                       блокировки, после него — первая настройка (сессия «fresh»)
#   tools/delta-dev.sh ipc <...>        команда оболочке во вложенной сессии:
#                                       tools/delta-dev.sh ipc call shell set docks.apps.autohide false
#   tools/delta-dev.sh shot [файл]      снимок экрана вложенной сессии
#   tools/delta-dev.sh log              журнал оболочки этой сессии
#   tools/delta-dev.sh stop             закрыть вложенную сессию
#   tools/delta-dev.sh exec <команда>   запустить программу внутри вложенной сессии
#
# DELTA_DEV_HIDDEN=1       окно на скрытом спецстоле (для фоновой работы)
# DELTA_DEV_SIZE="W H"     размер скрытого окна (по умолчанию "1280 800"; видео — "1920 1080")
# DELTA_DEV_PRIVATE_BUS=1  своя шина D-Bus (уведомления, MPRIS, трей)
#
# Вложенная сессия работает с отдельным HOME, поэтому ~/.config/delta не
# затрагивается. Несколько сессий одновременно — через имя (-n):
#   DELTA_DEV_NAME=docks DELTA_SHELL_ENTRY=delta/shell/dev-docks.qml tools/delta-dev.sh nested 120
# У каждого имени свой HOME (build/delta-home-<имя>) и своё окно.
set -euo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DELTA=${PROJECT_DIR}/delta
DEV_NAME=${DELTA_DEV_NAME:-$([ "${1:-}" = fresh ] && echo fresh || echo main)}
DEV_HOME=${DELTA_DEV_HOME:-${PROJECT_DIR}/build/delta-home-${DEV_NAME}}
STATE=${DEV_HOME}/.nested-display
PIDFILE=${DEV_HOME}/.nested-pid

export DELTA_DATA=${DELTA}
export PATH=${DELTA}/bin:${PATH}
# обои Vanks OS из проекта вместо /usr/share/backgrounds/vankos
export DELTA_WALLPAPERS=${PROJECT_DIR}/wallpapers
if [ -n "${DELTA_SHELL_ENTRY:-}" ]; then
    DELTA_SHELL_ENTRY=$(realpath "${DELTA_SHELL_ENTRY}")
    export DELTA_SHELL_ENTRY
fi

log()  { printf '[delta-dev] %s\n' "$*"; }
fail() { printf '[delta-dev] ОШИБКА: %s\n' "$*" >&2; exit 1; }

nested_display() {
    [ -f "${STATE}" ] || fail "вложенная сессия не запущена: tools/delta-dev.sh nested"
    cat "${STATE}"
}

cmd_check() {
    local rc=0 f out tmp
    for f in "${DELTA}"/bin/*; do
        bash -n "${f}" || { log "синтаксис: ${f}"; rc=1; }
    done
    jq -e 'type == "object"' "${DELTA}/defaults/settings.json" >/dev/null || { log "JSON: defaults/settings.json"; rc=1; }

    # конфиг Hyprland вместе с generated.lua из значений по умолчанию
    tmp=$(mktemp -d)
    HOME=${tmp} delta-apply --no-reload >/dev/null 2>&1 || { log "delta-apply не сгенерировал конфиг"; rc=1; }
    out=$(HOME=${tmp} Hyprland --verify-config -c "${DELTA}/hypr/hyprland.lua" 2>&1 | sed -n '/Config parsing result/,$p')
    rm -rf "${tmp}"
    if grep -q 'config ok' <<<"${out}"; then
        log "Hyprland: config ok"
    else
        log "Hyprland отклонил конфиг:"; grep -v 'parsing result' <<<"${out}" | sed '/^$/d'; rc=1
    fi

    # /usr/bin/qmllint бывает обёрткой без вывода — берём настоящий из Qt 6
    local qmllint=/usr/lib/qt6/bin/qmllint
    if [ -x "${qmllint}" ]; then
        # модули qs.* qmllint не видит, поэтому показываем только ошибки синтаксиса
        while IFS= read -r -d '' f; do
            out=$("${qmllint}" "${f}" 2>&1 | grep -E '\[syntax\]' || true)
            [ -z "${out}" ] || { log "QML: ${f#"${DELTA}"/}"; printf '%s\n' "${out}"; rc=1; }
        done < <(find "${DELTA}/shell" -name '*.qml' -print0)
    fi
    # собранные шейдеры (.qsb) не старее исходников
    "$(dirname "$0")/delta-shaders.sh" --check || rc=1
    [ "${rc}" -eq 0 ] && log "все проверки пройдены"
    return "${rc}"
}

cmd_nested() {
    local secs=${1:-600} sock="" pid hpid
    [ -n "${WAYLAND_DISPLAY:-}" ] || fail "нужна текущая Wayland-сессия"
    cmd_stop >/dev/null 2>&1 || true
    mkdir -p "${DEV_HOME}/.config/delta/hypr"
    # во вложенной сессии нет сторожа start-hyprland — убираем его плашку со снимков
    # Окно вложенной сессии маленькое, и масштаб «auto» дал бы 2: держим 1
    # правилом для всех выходов в user.lua — так он не зависит от settings.json
    # (сброс настроек, раздел «Экран»). Своё правило для WL-1 из «Экран» главнее.
    printf '%s\n' 'hl.config({ misc = { disable_watchdog_warning = true } })' \
        'hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })' \
        > "${DEV_HOME}/.config/delta/hypr/user.lua"
    if [ "${DELTA_DEV_HIDDEN:-0}" = 1 ]; then
        # Для фоновых проверок (агенты): окно вложенной сессии не мешает работе —
        # плавающее 1280×800 на скрытом спецстоле и продолжает рисоваться.
        # Правило живёт только до перезагрузки конфига основной сессии.
        hyprctl eval 'hl.window_rule({ name = "delta-dev-nested", match = { class = "^aquamarine$" }, float = true, size = "'"${DELTA_DEV_SIZE:-1280 800}"'", workspace = "special:deltadev silent", render_unfocused = true, no_initial_focus = true })' >/dev/null 2>&1 || true
    fi
    rm -f "${DEV_HOME}/.nested-bus"
    if [ "${DELTA_DEV_PRIVATE_BUS:-0}" = 1 ]; then
        # Своя сессионная шина D-Bus: сервер уведомлений, MPRIS-плееры и
        # трей вложенной сессии не конфликтуют с основной. Адрес — для `exec`.
        HOME=${DEV_HOME} DELTA_NESTED=1 setsid timeout "${secs}" dbus-run-session -- \
            sh -c 'printf "%s\n" "$DBUS_SESSION_BUS_ADDRESS" > "$HOME/.nested-bus"; exec delta-session' \
            > "${DEV_HOME}/nested.log" 2>&1 &
    else
        HOME=${DEV_HOME} DELTA_NESTED=1 setsid timeout "${secs}" delta-session > "${DEV_HOME}/nested.log" 2>&1 &
    fi
    pid=$!
    # Сокет берём у того экземпляра Hyprland, который принадлежит нашей
    # группе процессов, — так параллельные сессии не путаются.
    for _ in $(seq 1 75); do
        sleep 0.2
        for hpid in $(hyprctl instances -j 2>/dev/null | jq -r '.[].pid'); do
            if [ "$(ps -o pgid= -p "${hpid}" 2>/dev/null | tr -d ' ')" = "${pid}" ]; then
                sock=$(hyprctl instances -j | jq -r --argjson p "${hpid}" '.[] | select(.pid == $p) | .wl_socket')
                sig=$(hyprctl instances -j | jq -r --argjson p "${hpid}" '.[] | select(.pid == $p) | .instance')
                break 2
            fi
        done
    done
    [ -n "${sock}" ] || { kill -TERM -- "-${pid}" 2>/dev/null; fail "Hyprland не запустился, см. ${DEV_HOME}/nested.log"; }
    # оболочке нужно ещё мгновение, чтобы подняться
    sleep 1
    printf '%s\n' "${sock}" > "${STATE}"
    printf '%s\n' "${sig}" > "${DEV_HOME}/.nested-sig"
    printf '%s\n' "${pid}" > "${PIDFILE}"
    log "сессия «${DEV_NAME}» на ${sock}, закроется через ${secs} с (или: tools/delta-dev.sh stop)"
}

cmd_stop() {
    [ -f "${PIDFILE}" ] || return 0
    local sock="" pgid
    pgid=$(cat "${PIDFILE}")
    [ -f "${STATE}" ] && sock=$(cat "${STATE}")
    # Оболочка запущена с -d и живёт вне группы: гасим её на дисплее этой
    # сессии сами, иначе следующий запуск (qs -n) увидит её и не стартует
    [ -n "${sock}" ] && WAYLAND_DISPLAY=${sock} qs -p "${DELTA_SHELL_ENTRY:-${DELTA}/shell}" kill >/dev/null 2>&1 || true
    # setsid выше сделал timeout лидером группы: гасим всю группу
    kill -TERM -- "-${pgid}" 2>/dev/null || true
    # ждём, пока Hyprland освободит сокет, иначе следующий запуск займёт то же имя
    for _ in $(seq 1 50); do
        kill -0 -- "-${pgid}" 2>/dev/null || { [ -z "${sock}" ] || [ ! -e "${XDG_RUNTIME_DIR}/${sock}" ]; } && break
        sleep 0.2
    done
    kill -KILL -- "-${pgid}" 2>/dev/null || true
    rm -f "${PIDFILE}" "${STATE}" "${DEV_HOME}/.nested-sig"
    log "сессия «${DEV_NAME}» закрыта"
}

# экземпляр Hyprland вложенной сессии: без него hyprctl внутри exec/ipc
# достучится до основного Hyprland пользователя
nested_sig() {
    local sig
    sig=$(cat "${DEV_HOME}/.nested-sig" 2>/dev/null)
    [ -n "${sig}" ] || fail "нет сигнатуры вложенного Hyprland — перезапустите nested"
    printf '%s\n' "${sig}"
}
cmd_ipc()  { local sig; sig=$(nested_sig) || exit 1; HYPRLAND_INSTANCE_SIGNATURE=${sig} WAYLAND_DISPLAY=$(nested_display) delta-shell ipc "$@"; }
# запустить программу внутри вложенной сессии (её дисплей и, если есть, её шина D-Bus)
cmd_exec() {
    local disp sig
    disp=$(nested_display)
    sig=$(nested_sig) || exit 1
    if [ -s "${DEV_HOME}/.nested-bus" ]; then
        DBUS_SESSION_BUS_ADDRESS=$(cat "${DEV_HOME}/.nested-bus") HYPRLAND_INSTANCE_SIGNATURE=${sig} WAYLAND_DISPLAY=${disp} HOME=${DEV_HOME} "$@"
    else
        HYPRLAND_INSTANCE_SIGNATURE=${sig} WAYLAND_DISPLAY=${disp} HOME=${DEV_HOME} "$@"
    fi
}
cmd_shot() { local f=${1:-${DEV_HOME}/shot.png}; WAYLAND_DISPLAY=$(nested_display) grim "${f}"; log "${f}"; }
cmd_log()  {
    # журнал именно этой сессии: ищем экземпляр Quickshell на её дисплее
    local disp pid l=""
    disp=$(nested_display)
    for pid in $(pgrep -x qs; pgrep -x quickshell); do
        if tr '\0' '\n' < "/proc/${pid}/environ" 2>/dev/null | grep -qx "WAYLAND_DISPLAY=${disp}"; then
            l=${XDG_RUNTIME_DIR}/quickshell/by-pid/${pid}/log.log
            break
        fi
    done
    [ -n "${l}" ] && [ -f "${l}" ] || fail "оболочка в сессии «${DEV_NAME}» не запущена (упала?), см. ${DEV_HOME}/nested.log"
    grep -vE ' DEBUG' "${l}"
}

# Первый запуск: HOME сессии стирается (только build/delta-home-<имя>),
# настроек нет — экран блокировки как после загрузки, затем первая настройка.
cmd_fresh() {
    case "${DEV_HOME}" in "${PROJECT_DIR}"/build/delta-home-*) ;; *) fail "fresh стирает только build/delta-home-*: ${DEV_HOME}" ;; esac
    cmd_stop >/dev/null 2>&1 || true
    rm -rf -- "${DEV_HOME}"
    log "чистый HOME: ${DEV_HOME}"
    DELTA_OOBE=1 DELTA_LOCK_ON_START=1 cmd_nested "$@"
    log "экран блокировки — пароль вашей учётной записи; затем первая настройка"
}

case "${1:-}" in
    check)  shift; cmd_check "$@" ;;
    nested) shift; cmd_nested "$@" ;;
    fresh)  shift; cmd_fresh "$@" ;;
    ipc)    shift; cmd_ipc "$@" ;;
    shot)   shift; cmd_shot "$@" ;;
    log)    shift; cmd_log "$@" ;;
    stop)   shift; cmd_stop "$@" ;;
    exec)   shift; cmd_exec "$@" ;;
    *) sed -n "2,23p" "$0"; exit 2 ;;
esac
