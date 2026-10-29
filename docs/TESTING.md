# Тестирование

## 1. Виртуалка (обязательно до флешки)

```bash
./tools/run-qemu.sh                      # UEFI
VANKOS_QEMU_BIOS=1 ./tools/run-qemu.sh   # BIOS
VANKOS_QEMU_MEM=10G ./tools/run-qemu.sh  # если мало памяти
```

Нужны `qemu-full` (или `qemu-desktop` + `qemu-system-x86`) и `edk2-ovmf`.

Что должно произойти:

1. Меню загрузчика (5 секунд) → строка `Vanks OS 0.1 (GNOME, в оперативной памяти)`.
2. Через 20–60 секунд — GDM и автовход пользователя `vanks`.
3. Через ~10 секунд после входа открывается окно установщика (Calamares).

Проверка «всё в RAM»: в live-сессии

```bash
df -h /run/archiso/copytoram    # squashfs смонтирован из tmpfs
free -h                         # занято примерно на размер образа
```

Чтобы проверить установку в виртуалке, добавьте второй диск:

```bash
qemu-img create -f qcow2 /tmp/vankos-target.qcow2 30G
# и в run-qemu.sh добавьте: -drive file=/tmp/vankos-target.qcow2,if=virtio,format=qcow2
```

## 2. Чек-лист приёмки

### Загрузка

- [ ] UEFI: меню systemd-boot, загрузка без ошибок `archiso`
- [ ] BIOS: syslinux грузится (проверить `VANKOS_QEMU_BIOS=1`)
- [ ] `copytoram=y`: после загрузки `umount /dev/sr0` не ломает систему
- [ ] `copytoram=n` (второй пункт меню) тоже загружается

### Live-сессия

- [ ] автовход в GNOME без пароля
- [ ] обои Vanks OS, тёмная тема, док с ярлыком установщика
- [ ] установщик открылся сам и открывается повторно из меню
- [ ] `pkexec /usr/bin/calamares` не спрашивает пароль
- [ ] работает сеть (NetworkManager), звук, тачпад

### Установщик

- [ ] русский язык интерфейса, брендинг Vanks OS на всех экранах
- [ ] экран «Рабочий стол»: две карточки (GNOME, Hyprland) с описаниями
- [ ] разметка: «Стереть диск» + шифрование не выбрано
- [ ] сводка показывает выбранный стол
- [ ] прогресс идёт, заставка анимируется, логи без `Traceback`

### Установленная система — GNOME

- [ ] GRUB в меню UEFI/BIOS, `Vanks OS` в `os-release`
- [ ] GDM, вход созданным пользователем, пароль работает
- [ ] `sudo` работает, `systemctl status` без failed
- [ ] `pacman -Syu` не ругается на `[vankos-local]`
- [ ] в `/etc/pacman.conf` нет `file:///var/cache/vankos`

### Установленная система — Hyprland

- [ ] SDDM, сессия Hyprland в списке
- [ ] Super+Return (kitty), Super+D (wofi), Super+Q работают
- [ ] Waybar и Mako стартуют, обои на месте
- [ ] `hyprctl monitors` показывает монитор

## 3. Где смотреть логи

| Что | Где |
|---|---|
| сборка ISO | `build/build.log`, stdout `mkarchiso` |
| Calamares (live) | `sudo journalctl -b -u calamares`; `~/.cache/calamares/session.log` |
| установка | `/var/log/calamares.log` в live; `/var/log/pacman.log` в цели |
| загрузка live | `journalctl -b`, `systemctl status vankos-live-setup` |
| сам скрипт установки | вывод `[vankos/bootstrap]`, `[vankos/desktop]` в логе Calamares |

Быстрая диагностика в live-сессии:

```bash
ls /usr/lib/calamares/modules | grep -E 'packagechooser|shellprocess|pacstrap'
calamares -d 2>&1 | head -50     # запуск с отладкой из терминала
```

## 4. Известные риски первой сборки

| Риск | Признак | Что делать |
|---|---|---|
| В сборке Arch нет модуля `packagechooser` | Calamares пишет «module not found» и пропускает экран | проверить `ls /usr/lib/calamares/modules`; при отсутствии — заменить экран на `netinstall`/`notes` или собрать Calamares с нужными модулями |
| Calamares не стартует под Wayland | окно не появляется | в лаунчере уже стоит `QT_QPA_PLATFORM=xcb`; проверить наличие `xorg-xwayland` |
| `pacstrap` падает на hook'ах | ошибка `chroot` в логе | установщик запускается от root в live; проверить, что цель смонтирована (`mount | grep calamares-root`) |
| Подписи pacman в онлайн-режиме | `invalid or corrupted package` | обновить `archlinux-keyring` в live-образе; временно `SigLevel = Optional TrustAll` |
| Нет `/etc/pacman.d/mirrorlist` в live | pacstrap не находит репозитории | пакет `pacman-mirrorlist` есть в `packages.x86_64`, проверить файл |
| Мало RAM | copytoram не копирует, ошибка `not enough space` | грузить второй пункт меню (`copytoram=n`) или дать ≥ 6 ГБ |
| GRUB не ставится на UEFI | `grub-install failed` | в VM включить UEFI (по умолчанию в `run-qemu.sh`), ESP ≥ 300 МБ |
| Загрузка падает в emergency mode, `gpt-auto-root` | ядро не нашло ISO | нет archiso-хуков в initramfs: проверить `iso/airootfs/etc/mkinitcpio.conf.d/archiso.conf` и пересобрать ISO |
| В меню загрузчика пустые места вместо слов | кириллица в `title`/`SAY` | `systemd-boot` и `syslinux` не рисуют не-ASCII: меню только на английском |

## 5. Тест на реальном железе

1. Записать ISO на флешку ≥ 8 ГБ (`dd`, Ventoy, balenaEtcher).
2. Загрузиться в UEFI (Secure Boot **выключить** — подписи нет).
3. Пройти установку на свободный диск, **не** трогая рабочий.
4. Проверить чек-листы выше, отдельно: Wi-Fi, спящий режим, яркость,
   внешний монитор, звук через наушники.
5. Сохранить `journalctl -b > /tmp/boot.log` и `sudo cat /var/log/calamares.log`.
