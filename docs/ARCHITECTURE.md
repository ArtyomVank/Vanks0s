# Архитектура Vanks OS

## 1. Загрузка

```
UEFI ──► systemd-boot (efiboot/) ──┐
                                   ├──► vmlinuz-linux-zen + initramfs-linux-zen.img
BIOS ──► syslinux (syslinux/) ─────┘        │
                                            ▼
                             mkinitcpio-archiso hook
                                            │
             copytoram=y: airootfs.sfs копируется в RAM (tmpfs)
                                            │
                                            ▼
                             switch_root в squashfs-образ
```

Ключевые параметры ядра (см. `iso/efiboot/loader/entries/vankos.conf`):

```
archisobasedir=vankos archisosearchuuid=%ARCHISO_UUID% copytoram=y quiet loglevel=3
```

`copytoram=y` — требование «система запускается в оперативке»: после загрузки
флешку можно вынуть. Плата — RAM: squashfs ≈ 2.5–3 ГБ, поэтому нужно **≥ 6 ГБ**
(в QEMU по умолчанию 8 ГБ). Для слабых машин есть пункт `copytoram=n`.

## 2. Live-сессия

| Компонент | Файл | Роль |
|---|---|---|
| systemd unit | `etc/systemd/system/vankos-live-setup.service` | oneshot **до** `greetd.service` |
| скрипт | `usr/local/bin/vankos-live-setup` | создаёт `vanks`, кладёт конфиг greetd, настройки Delta (установщик в доке, без блокировки и сна), ярлык, `dconf update` |
| greetd | `usr/share/vankos/greetd-live.toml` → `/etc/greetd/config.toml` | автовход `vanks` (`[initial_session]`) |
| сессия | `usr/local/bin/vankos-live-session` | Delta; при `vankos.safe=1` или если Delta упала за 30 с — Calamares в `cage` (pixman) |
| автозапуск | `etc/xdg/autostart/vankos-installer.desktop` | Delta запускает его через `dex` после входа |
| polkit | `etc/polkit-1/rules.d/49-vankos-installer.rules` | разрешает `vanks` запускать `/usr/bin/calamares` через `pkexec` без пароля |
| оформление | `etc/dconf/db/local.d/00-vankos` | тёмная тема, акцент, док, обои |

Порядок: `graphical.target` → `vankos-live-setup` (создаёт пользователя) →
`greetd.service` → автовход → `vankos-live-session` → Delta → автозапуск →
`vankos-installer` → `sudo -n calamares` (Wayland-окно поверх Delta).

Безопасный режим — пункт меню загрузки «Safe mode» (`nomodeset vankos.safe=1`):
вместо Delta сразу `cage` с Calamares на весь экран, программная отрисовка.

`QT_QPA_PLATFORM=xcb` в лаунчере — Calamares это Qt Widgets приложение, под
Wayland-сессией GNOME оно работает через XWayland.

## 3. Установщик

Последовательность из `calamares/settings.conf`:

| Фаза | Шаг | Что делает |
|---|---|---|
| show | `welcome` | приветствие, требования (12 ГБ, 4 ГБ RAM) |
| show | `locale`, `keyboard`, `partition`, `users` | стандартные страницы |
| show | `packagechooser@shell` | **выбор GNOME / Hyprland** |
| show | `summary` | итог |
| exec | `partition`, `mount` | разметка и монтирование цели |
| exec | `shellprocess@bootstrap` | `bootstrap.sh`: pacstrap базовой системы |
| exec | `shellprocess@desktop` | `desktop.sh`: пакеты стола + службы + `/etc/skel` |
| exec | `machineid`…`hwclock` | системные файлы цели |
| exec | `initcpiocfg`, `initcpio` | `mkinitcpio -P` |
| exec | `bootloader` | GRUB (UEFI/BIOS), `installEFIFallback` |
| exec | `shellprocess@cleanup` | `cleanup.sh`: umount репозитория, удаление следов |
| exec | `umount` | размонтирование |

### Передача выбора

`packagechooser` с `method: legacy` пишет в GlobalStorage ключ
`packagechooser_shell` (`gnome` или `hyprland`). `shellprocess` подставляет
любой ключ GS через `${gs[...]}`:

```yaml
script:
  - command: "/usr/local/lib/vankos/desktop.sh ${ROOT} \"${gs[packagechooser_shell]}\""
```

Поэтому выбор читается shell-скриптом — без Python-модулей Calamares и без
своего C++ кода. Если ключ не пришёл, `desktop.sh` считает выбор `gnome`.

### Почему pacstrap, а не unpackfs

`unpackfs` (копирование live-squashfs в цель) проще, но тащит в установленную
систему весь live-хлам: `calamares`, `archiso`-хуки, live-пользователя,
live-настройки GDM. Чистка такого образа — набор эвристик, которые ломаются
на следующей версии archiso.

`pacstrap` даёт ровно те пакеты, что выбрал пользователь, и стандартный Arch.
Плата — установщику нужен репозиторий: локальный на ISO (офлайн) или сеть.

## 4. Офлайн-репозиторий

```
build/pacman-cache/*.pkg.tar.zst
        │ repo-add
        ▼
build/repo/vankos.db.tar.gz  ──►  build/profile/airootfs/var/cache/vankos/repo
                                            │
                                    (squashfs на ISO)
                                            │
live: /var/cache/vankos/repo  ──bind──►  target: /var/cache/vankos/repo
                                            │
                          pacman.conf цели: Server = file:///var/cache/vankos/repo
```

Путь намеренно одинаковый в live-системе и в `chroot` цели: bind-монтирование
делает `file://`-URL валидным в обоих контекстах.

Порядок шагов в `bootstrap.sh`: ключи pacman → bind-репозитория → `pacstrap` →
`pacman.conf` цели → `os-release`. `cleanup.sh` отмонтирует репозиторий и
уберёт `[vankos-local]` из `pacman.conf`, чтобы после установки pacman не
ругался на недоступный сервер.

## 5. Рабочие столы

| | Delta (по умолчанию) | GNOME |
|---|---|---|
| пакеты | `iso/lists/delta.txt` (пакет `delta` из `packaging/delta`) | `iso/lists/gnome.txt` |
| дисплей-менеджер | `greetd` (экран входа Delta) | `gdm` |
| конфиги | `/etc/greetd/config.toml`, `/etc/pam.d/greetd` из пакета delta; `~/.config/delta` создаёт оболочка | системные + `dconf` |
| тема | «Настройки» Delta → Оформление | тёмная, акцент violet |

Оба набора лежат в локальном репозитории, поэтому переключиться на другой стол
после установки можно без интернета: `sudo pacman -S gnome gdm`.

## 6. Брендинг

| Файл | Назначение |
|---|---|
| `branding.desc` | имя продукта, версия, цвета сайдбара, ссылки на картинки |
| `stylesheet.qss` | тёмная тема Qt Widgets (кнопки, поля, списки, прогресс) |
| `show.qml` | заставка на время установки (`slideshowAPI: 2`) |
| `logo.png`, `welcome.png`, `wallpaper.png` | логотип, баннер, обои |
| `delta.png`, `gnome.png` | карточки-скриншоты на экране выбора (`delta.png` — снимок настоящей оболочки) |

Палитра: фон `#0E0C15`, акцент `#7C5CFF`, второй акцент `#22D3EE`,
текст `#E7E4F5`. Все PNG генерируются `tools/gen_branding.py` (Pillow), поэтому
их можно перерисовать одной командой без графического редактора.
