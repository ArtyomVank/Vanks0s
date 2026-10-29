#!/usr/bin/env bash
# ============================================================================
#  Vanks OS — подготовка сборочной машины (Arch Linux).
#
#  Ставит зависимости, проверяет место и права, выставляет биты выполнения
#  и запускает статические проверки проекта. Ничего не собирает.
#
#      ./tools/setup-host.sh
#      sudo ./tools/setup-host.sh     # сразу и пакеты поставить
# ============================================================================
set -uo pipefail

PROJECT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PKGS=(
    archiso
    arch-install-scripts
    squashfs-tools
    libisoburn
    mtools
    dosfstools
    e2fsprogs
    erofs-utils
    grub
    syslinux
    edk2-shell
    base-devel
    sudo
    python
    python-pillow
)
MIN_FREE_GB=25
problems=0

c_bold=$'\033[1m'; c_dim=$'\033[2m'; c_ok=$'\033[32m'; c_warn=$'\033[33m'; c_err=$'\033[31m'; c_off=$'\033[0m'
step() { printf '\n%s==>%s %s\n' "${c_bold}" "${c_off}" "$*"; }
ok()   { printf '  %s✓%s %s\n' "${c_ok}" "${c_off}" "$*"; }
warn() { printf '  %s!%s %s\n' "${c_warn}" "${c_off}" "$*"; }
bad()  { printf '  %s×%s %s\n' "${c_err}" "${c_off}" "$*"; problems=$((problems + 1)); }

step "Дистрибутив"
if ! command -v pacman >/dev/null 2>&1; then
    bad "это не Arch Linux (нет pacman). Сборка возможна только на Arch/Arch-based."
    echo "    Варианты: Arch в VirtualBox/VMware, Arch на железе или WSL2 с импортом Arch."
    exit 1
fi
ok "$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2- | tr -d '\"')"
[[ "$(uname -m)" == "x86_64" ]] && ok "архитектура x86_64" || bad "нужна x86_64, сейчас $(uname -m)"

step "Права и место"
if [[ ${EUID} -eq 0 ]]; then ok "запущено от root"; else warn "не root — пакеты и сборку придётся запускать через sudo"; fi
free_gb=$(df -Pk "${PROJECT_DIR}" | awk 'NR==2 {printf "%d", $4/1024/1024}')
if ((free_gb >= MIN_FREE_GB)); then
    ok "свободно ${free_gb} ГБ (нужно ${MIN_FREE_GB})"
else
    bad "свободно ${free_gb} ГБ, нужно минимум ${MIN_FREE_GB} ГБ"
fi
mem_gb=$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo)
((mem_gb >= 4)) && ok "RAM ${mem_gb} ГБ" || warn "RAM ${mem_gb} ГБ — сборка пойдёт, тест в QEMU может не хватить"

step "Пакеты"
if [[ ${EUID} -eq 0 ]]; then
    echo "  ставлю: ${PKGS[*]}"
    if pacman -S --needed --noconfirm "${PKGS[@]}"; then
        ok "зависимости установлены"
    else
        bad "pacman не смог установить зависимости"
    fi
else
    missing=()
    for pkg in "${PKGS[@]}"; do pacman -Qq "${pkg}" >/dev/null 2>&1 || missing+=("${pkg}"); done
    if ((${#missing[@]} == 0)); then
        ok "все зависимости уже стоят"
    else
        warn "не хватает: ${missing[*]}"
        echo "    sudo pacman -S --needed ${missing[*]}"
    fi
fi

step "Команды"
for cmd in mkarchiso pacstrap repo-add mksquashfs xorriso; do
    if command -v "${cmd}" >/dev/null 2>&1; then ok "${cmd}"; else bad "нет ${cmd}"; fi
done

step "Файлы проекта"
chmod +x "${PROJECT_DIR}/build.sh" "${PROJECT_DIR}/tools/"*.sh 2>/dev/null || true
chmod +x "${PROJECT_DIR}/iso/airootfs/usr/local/bin/"* 2>/dev/null || true
chmod +x "${PROJECT_DIR}/iso/airootfs/usr/local/lib/vankos/"*.sh 2>/dev/null || true
ok "биты выполнения выставлены"

if command -v python3 >/dev/null 2>&1; then
    if python3 "${PROJECT_DIR}/tools/validate.py" --root "${PROJECT_DIR}" >/tmp/vankos-validate.log 2>&1; then
        ok "статические проверки пройдены ($(grep -c . /tmp/vankos-validate.log) строк отчёта)"
    else
        bad "проверки нашли ошибки:"
        sed 's/^/    /' /tmp/vankos-validate.log
    fi
else
    warn "нет python3 — статические проверки пропущены"
fi

step "Итог"
if ((problems)); then
    printf '  %sЕсть проблемы: %d.%s Исправьте и запустите скрипт снова.\n' "${c_err}" "${problems}" "${c_off}"
    exit 1
fi
cat <<EOF
  ${c_ok}Всё готово.${c_off} Дальше:

    ${c_bold}sudo ${PROJECT_DIR}/build.sh${c_off}                 # полная сборка с офлайн-репозиторием
    ${c_dim}sudo VANKOS_OFFLINE=0 ${PROJECT_DIR}/build.sh${c_off}   # slim, установка из сети

  ISO появится в ${PROJECT_DIR}/build/out/
  Проверить в виртуалке: ${PROJECT_DIR}/tools/run-qemu.sh
EOF
