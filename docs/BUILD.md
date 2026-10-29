# Сборка Vanks OS

## Требования

* Arch Linux x86_64 (или Arch-контейнер/VM с доступом к `loop`-устройствам
  и монтированию — в Docker без `--privileged` mkarchiso не работает).
* root (mkarchiso монтирует squashfs и создаёт петлевые устройства).
* Свободно **≥ 25 ГБ** диска: кэш пакетов, work-каталог, репозиторий и ISO.
* Интернет на время сборки (пакеты скачиваются с зеркал Arch).

Пакеты сборочной машины:

```bash
sudo pacman -S --needed archiso arch-install-scripts squashfs-tools libisoburn \
    mtools dosfstools e2fsprogs erofs-utils grub syslinux edk2-shell python-pillow
```

`build.sh` сам проверяет наличие команд и пакетов и падает с подсказкой, если
чего-то не хватает.

## Команды

```bash
chmod +x build.sh tools/*.sh

./tools/validate.sh              # статические проверки (быстро, без root)
sudo ./build.sh                  # полная сборка с офлайн-репозиторием
sudo VANKOS_OFFLINE=0 ./build.sh # slim-ISO без репозитория
```

Переменные окружения:

| Переменная | По умолчанию | Смысл |
|---|---|---|
| `VANKOS_OFFLINE` | `1` | `1` — включить локальный репозиторий в ISO |
| `VANKOS_JOBS` | `nproc` | зарезервировано под параллельную сборку |

Результат: `build/out/vankos-<дата>-x86_64.iso` и рядом `.sha256`.
Полный лог — `build/build.log`.

## Что делает build.sh

1. Проверяет root, команды и пакеты.
2. При отсутствии PNG запускает `tools/gen_branding.py` (нужен `python-pillow`).
3. Копирует `iso/` в `build/profile` и добавляет туда:
   * `calamares/` → `airootfs/etc/calamares/`;
   * списки пакетов → `airootfs/usr/share/vankos/`;
   * симлинки systemd: `vankos-live-setup.service`, `gdm.service`,
     `default.target → graphical.target`.
4. Подставляет `CacheDir = build/pacman-cache` в `pacman.conf`.
5. **Проверяет/собирает Calamares** (`tools/build-calamares.sh` →
   `build/pkgs/`), добавляет `build/pkgs` как репозиторий `[vankos-pkgs]` и
   проверяет, что каждый пакет из `iso/packages.x86_64` вообще существует.
6. Если `VANKOS_OFFLINE=1`: скачивает **все** пакеты из
   `target-base + gnome + hyprland` в `build/pacman-cache`, собирает
   `vankos.db.tar.gz` через `repo-add` (только `*.pkg.tar.zst`, без `*.sig`)
   и кладёт репозиторий в `airootfs/var/cache/vankos/repo`.
7. Запускает `mkarchiso`.
8. Проверяет, что в initramfs попали archiso-хуки, что у `calamares` в
   собранном rootfs нет недостающих библиотек, и считает SHA-256.

### Почему Calamares собирается отдельно

В репозиториях Arch (`core`, `extra`) пакета `calamares` **нет** — он живёт
только в AUR. Причём AUR-рецепт собирает Calamares без модуля
`packagechooser`, а именно на нём держится экран выбора рабочего стола.

Поэтому в проекте лежит свой рецепт `packaging/calamares/PKGBUILD`:
та же версия 3.4.2, но `SKIP_MODULES` не трогает `packagechooser`.
`tools/build-calamares.sh` собирает пакет через `makepkg` от отдельного
пользователя `vankosbuild` (от root `makepkg` работать отказывается) и
складывает результат в `build/pkgs/`.

```bash
sudo ./tools/build-calamares.sh     # только сборка установщика, 5–15 минут
```

Повторно пакет не пересобирается, только если в `build/pkgs/` лежит файл
ровно для текущих `pkgver`/`pkgrel` из PKGBUILD. После правки рецепта
(например, добавления зависимости `kcrash`) старый пакет удаляется и
собирается заново — иначе в ISO попал бы бинарник, который не запускается.

### Как получается полный офлайн-репозиторий

Ключевой приём — **изолированная база pacman**:

```bash
pacman -Syw --dbpath build/pacdb --cachedir build/pacman-cache \
    --config build/profile/pacman.conf $(cat lists/...)
```

Пустая `--dbpath` означает «ничего не установлено», поэтому pacman скачивает
и целевые пакеты, и все зависимости — независимо от того, что стоит на
сборочной машине. Дальше `repo-add` собирает из кэша локальную базу.

На ISO репозиторий лежит в `/<install_dir>/airootfs.sfs` по пути
`/var/cache/vankos/repo`. Установщик:

* монтирует его bind-ом в `/var/cache/vankos/repo` целевой системы;
* прописывает в `pacman.conf` цели `Server = file:///var/cache/vankos/repo`
  (путь одинаковый до и после `chroot`);
* перед `umount` отмонтирует и удалит запись (`cleanup.sh`).

## Сколько это занимает

| Этап | Время | Размер |
|---|---|---|
| сборка Calamares (первый раз) | 5–15 мин | ~30 МБ в `build/pkgs` |
| скачивание пакетов | 5–15 мин | ~2 ГБ в `build/pacman-cache` |
| `mkarchiso` | 15–40 мин | ~2–3 ГБ в `build/work` |
| ISO (полная) | — | ≈ 3.5–4.5 ГБ |
| ISO (slim) | — | ≈ 1.5–2 ГБ |

ssd и 8+ ядер ускоряют сборку примерно вдвое.

## Если сборка упала

| Симптом | Причина и что делать |
|---|---|
| `mkarchiso: command not found` | не установлен `archiso` |
| `Не удалось создать каталог $BUILDDIR` / в live-системе не стартует установщик | проект лежит на NTFS/FAT: там нет владельцев и setuid, `sudo`/`pkexec` в образе ломаются. `build.sh` сам собирает в ext4-образе `build/vankos-build.ext4` (монтируется в `/mnt/vankos-build`), либо задайте `VANKOS_BUILD_DIR` на ext4/btrfs |
| `Loop device ... is not available` | сборка в контейнере без прав; запускайте на хосте или в `--privileged` |
| `failed retrieving file ... core.db` | нет сети/плохое зеркало: `reflector --country ... > /etc/pacman.d/mirrorlist` |
| `not enough free space` | нужно ≥ 25 ГБ; почистите `build/work`, `build/pacman-cache` |
| `package X not found` | опечатка в `iso/packages.x86_64` или `iso/lists/*.txt`; `build.sh` теперь проверяет это до сборки и печатает список отсутствующих |
| `target not found: calamares` | calamares нет в репозиториях Arch — он должен собираться через `tools/build-calamares.sh` в `build/pkgs` (build.sh делает это сам) |
| `bsdtar: Unrecognized archive format` в `repo-add` | в список попали файлы `*.sig`; фильтр в `build.sh` уже исключает их, проверьте свои правки |
| `install: пропущен операнд, задающий целевой файл` | в `build.sh` был `install -m 0755 <файл>` без цели; права ставятся через `chmod` |
| `Validating 'bios.syslinux': The 'syslinux' package is missing` | `syslinux` (и `memtest86+`) должны быть в `iso/packages.x86_64`, а не только на хосте |
| в Calamares нет экрана выбора стола | в пакет не попал `packagechooser` — собирайте по `packaging/calamares/PKGBUILD` из проекта, а не по AUR-рецепту |
| `pacman -Syw` ругается на подписи | обновите `archlinux-keyring` на сборочной машине |

Логи mkarchiso пишет в stdout и в `build/build.log`; после падения
`build/work` сохраняется — по нему видно, на каком пакете остановилось.

### ISO собрался, но загружается в emergency mode

Симптом: `Timed out waiting for device /dev/gpt-auto-root`,
`Dependency failed for Initrd Root File System`, `Cannot open access to console`.

Причина: в initramfs нет archiso-хуков — ядро не ищет ISO и не выставляет
`root=`. Проверяется одной командой на сборочной машине:

```bash
grep -ao 'archisosearchuuid' build/work/*/airootfs/boot/initramfs-linux.img | head -1
```

Если вывода нет — отсутствует или испорчен
`iso/airootfs/etc/mkinitcpio.conf.d/archiso.conf` (в нём должен быть
`HOOKS=(... memdisk archiso archiso_loop_mnt ...)`). `build.sh` проверяет это
до сборки и после неё, поэтому при правильном профиле такой ошибки быть не
должно.

Второй вариант — мало RAM для `copytoram=y` (нужно ≥ 6 ГБ): выберите в меню
второй пункт `no RAM copy`.

### Кириллица в меню загрузчика не видна

`systemd-boot` и `syslinux` умеют рисовать только ASCII: русские буквы в
`title`/`SAY` превращаются в пустые места. Поэтому меню загрузчика — на
английском, а русский начинается с Calamares. `tools/validate.sh`
предупреждает, если кириллица снова попадёт в `iso/efiboot/*` или
`iso/syslinux/syslinux.cfg`.

## Проверка перед записью на флешку

```bash
./tools/run-qemu.sh                     # UEFI, 8 ГБ RAM
VANKOS_QEMU_BIOS=1 ./tools/run-qemu.sh  # BIOS
```

Смотрите [TESTING.md](TESTING.md) — там чек-лист приёмки.
