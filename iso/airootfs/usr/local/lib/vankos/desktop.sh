#!/usr/bin/env bash
# Vanks OS — шаг 2 установки: выбранный рабочий стол + службы.
# Аргументы: ${ROOT} и выбор пользователя (delta|gnome).
set -euo pipefail
export LC_ALL=C

ROOT="${1:-}"
CHOICE="${2:-delta}"
export ROOT CHOICE

log()  { printf '[vankos/desktop] %s\n' "$*"; }
fail() { printf '[vankos/desktop] ОШИБКА: %s\n' "$*" >&2; exit 1; }

[ -n "${ROOT}" ] || fail "не передана точка монтирования цели"
[ -d "${ROOT}" ] || fail "нет каталога ${ROOT}"

# Calamares передаёт id из packagechooser; поддерживаем и человекочитаемый вид.
CHOICE=$(printf '%s' "${CHOICE}" | tr '[:upper:]' '[:lower:]')
case "${CHOICE}" in
    delta|"" )  CHOICE=delta; LIST=/usr/share/vankos/delta.txt; DM=greetd ;;
    gnome )     CHOICE=gnome; LIST=/usr/share/vankos/gnome.txt; DM=gdm ;;
    * ) fail "неизвестный вариант рабочего стола: ${CHOICE}" ;;
esac

[ -f "${LIST}" ] || fail "нет списка пакетов ${LIST}"
mapfile -t pkgs < <(grep -vE '^[[:space:]]*(#|$)' "${LIST}")
[ "${#pkgs[@]}" -gt 0 ] || fail "пустой список пакетов в ${LIST}"

log "рабочий стол: ${CHOICE}, пакетов: ${#pkgs[@]}, дисплей-менеджер: ${DM}"

# delta есть в офлайн-репозитории ISO, но не в репозиториях Arch. При установке
# из сети (slim-ISO) ставим его файлом из образа — зависимости pacman возьмёт
# из сети, — и убираем из общего списка.
if [ "${CHOICE}" = "delta" ] && ! arch-chroot "${ROOT}" pacman -Si delta >/dev/null 2>&1; then
    pkgfile=$(find /usr/share/vankos/pkgs -maxdepth 1 -name 'delta-*.pkg.tar.zst' 2>/dev/null | sort | tail -n1)
    [ -n "${pkgfile}" ] || fail "пакета delta нет ни в репозитории, ни в образе (/usr/share/vankos/pkgs)"
    log "ставлю delta из образа: ${pkgfile##*/}"
    install -d "${ROOT}/var/cache/vankos/pkgs"
    install -m 0644 "${pkgfile}" "${ROOT}/var/cache/vankos/pkgs/"
    arch-chroot "${ROOT}" pacman -U --needed --noconfirm "/var/cache/vankos/pkgs/${pkgfile##*/}"
    mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | grep -vx delta)
fi
# Обои (~180 МБ) есть только в офлайн-репозитории полного ISO: в образ файлом
# их не кладём, чтобы не возить дважды. Без них Delta работает — пропускаем.
if [ "${CHOICE}" = "delta" ] && ! arch-chroot "${ROOT}" pacman -Si vankos-wallpapers >/dev/null 2>&1; then
    log "обоев Vanks OS нет в репозитории — ставлю без них"
    mapfile -t pkgs < <(printf '%s\n' "${pkgs[@]}" | grep -vx vankos-wallpapers)
fi

arch-chroot "${ROOT}" pacman -S --needed --noconfirm "${pkgs[@]}"

install -d "${ROOT}/etc/skel/.config" "${ROOT}/etc/skel/Desktop"

if [ "${CHOICE}" = "delta" ]; then
    # Экран входа Delta: конфиг greetd и PAM из пакета delta. Пакет greetd
    # ставит свои версии этих файлов — заменяем их целиком.
    greetd_src="${ROOT}/usr/share/delta/session/greetd"
    [ -f "${greetd_src}/config.toml" ] || fail "нет ${greetd_src}/config.toml — пакет delta установлен не полностью"
    log "настраиваю экран входа Delta (greetd)"
    install -Dm644 "${greetd_src}/config.toml"  "${ROOT}/etc/greetd/config.toml"
    install -Dm644 "${greetd_src}/pam.d-greetd" "${ROOT}/etc/pam.d/greetd"
    # Каталоги вида пользователя для экрана входа (владелец — greeter, его
    # создаёт пакет greetd). При загрузке tmpfiles создаст их и сам, но так
    # первый вход уже найдёт их на месте.
    arch-chroot "${ROOT}" systemd-tmpfiles --create /usr/lib/tmpfiles.d/delta-greeter.conf || \
        log "предупреждение: systemd-tmpfiles не создал каталоги экрана входа (создаст при загрузке)"
    # Оболочка сама создаёт ~/.config/delta при первом входе; в skel ничего не нужно.
else
    log "готовлю GNOME"
fi

# --- службы ---
log "включаю службы"
for unit in NetworkManager.service bluetooth.service; do
    systemctl --root="${ROOT}" enable "${unit}" 2>/dev/null || \
        log "предупреждение: не удалось включить ${unit} (пакет не установлен?)"
done
systemctl --root="${ROOT}" enable "${DM}.service" 2>/dev/null || \
    fail "не удалось включить ${DM}.service"
systemctl --root="${ROOT}" set-default graphical.target 2>/dev/null || true
systemctl --root="${ROOT}" enable fstrim.timer 2>/dev/null || true

# --- тихая загрузка ---
# Обычному человеку не нужны сообщения ядра, systemd и мигающий курсор между
# логотипом прошивки и экраном входа. Модуль bootloader Calamares для GRUB
# параметры не пишет — задаём их в /etc/default/grub до grub-mkconfig.
GRUB_DEFAULTS="${ROOT}/etc/default/grub"
if [ -f "${GRUB_DEFAULTS}" ]; then
    log "тихая загрузка: параметры ядра для GRUB"
    sed -i 's|^#\?GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 rd.udev.log_level=3 systemd.show_status=auto vt.global_cursor_default=0"|' \
        "${GRUB_DEFAULTS}"
    grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "${GRUB_DEFAULTS}" || \
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 rd.udev.log_level=3 systemd.show_status=auto vt.global_cursor_default=0"' >> "${GRUB_DEFAULTS}"
else
    log "предупреждение: нет /etc/default/grub — параметры тихой загрузки не заданы"
fi

# --- отметка о выбранном окружении ---
install -d "${ROOT}/etc/vankos"
printf '%s\n' "${CHOICE}" > "${ROOT}/etc/vankos/shell"
cat > "${ROOT}/etc/vankos/release" <<EOF
VANKS_SHELL=${CHOICE}
VANKS_DISPLAY_MANAGER=${DM}
VANKS_VERSION=0.4
EOF

log "рабочий стол ${CHOICE} установлен"
exit 0
