#!/usr/bin/env bash
# Vanks OS — archiso profile definition.
# Документация: https://gitlab.archlinux.org/archlinux/archiso/-/blob/master/README.profile.rst
# shellcheck disable=SC2034
iso_name="vankos"
iso_label="VANKOS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="Vanks OS <https://vanksos.local>"
iso_application="Vanks OS Live Installer (Delta in RAM)"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="vankos"
buildmodes=('iso')
# BIOS + UEFI. На современных версиях archiso имена режимов — 'bios.syslinux' и 'uefi.systemd-boot'.
bootmodes=('bios.syslinux' 'uefi.systemd-boot')
arch="x86_64"
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
# zstd вместо xz: сборка в 3-4 раза быстрее, ISO больше примерно на 10%.
airootfs_image_tool_options=('-comp' 'zstd' '-Xcompression-level' '15' '-b' '1M')
bootstrap_tarball_compression=('zstd' '-c' '-T0' '--auto-threads=logical' '--long' '-19')
# тихая загрузка: без сообщений udev/systemd и мигающего курсора консоли
kernel_params="quiet loglevel=3 rd.udev.log_level=3 systemd.show_status=auto vt.global_cursor_default=0"
file_permissions=(
  ["/etc/shadow"]="0:0:400"
  ["/etc/gshadow"]="0:0:400"
  ["/root"]="0:0:750"
  ["/usr/local/bin/vankos-live-setup"]="0:0:755"
  ["/usr/local/bin/vankos-installer"]="0:0:755"
  ["/usr/local/bin/vankos-live-session"]="0:0:755"
  # mkarchiso копирует airootfs с --no-preserve=mode: без этих строк скрипты
  # попадают в образ с 0644, и Calamares падает с кодом 126.
  ["/usr/local/lib/vankos/bootstrap.sh"]="0:0:755"
  ["/usr/local/lib/vankos/desktop.sh"]="0:0:755"
  ["/usr/local/lib/vankos/cleanup.sh"]="0:0:755"
  # sudo игнорирует файлы с режимом шире 0440 — без этого пропадает NOPASSWD
  ["/etc/sudoers.d/10-vankos-live"]="0:0:440"
  ["/etc/polkit-1/rules.d/49-vankos-installer.rules"]="0:0:644"
)
