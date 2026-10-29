# Экран входа Delta (greetd)

greetd запускает отдельный Hyprland (`hyprland.lua` отсюда) от пользователя
`greeter`, в нём — `qs -p /usr/share/delta/shell/greeter.qml`. Greeter выглядит
как экран блокировки: обои, тема и часы последнего пользователя, его аватар.
После пароля доигрывается анимация разблокировки, greeter просит greetd
запустить сессию и выходит; вместе с ним выходит и его Hyprland.

## Файлы

| Здесь | Куда ставить | Что |
|---|---|---|
| `config.toml` | `/etc/greetd/config.toml` | greetd: VT 1, greeter через `start-hyprland` |
| `hyprland.lua` | `/usr/share/delta/session/greetd/hyprland.lua` | композитор экрана входа, без привязок |
| `pam.d-greetd` | `/etc/pam.d/greetd` | PAM greetd + `pam_gnome_keyring` (связка ключей открывается паролем входа) |
| `tmpfiles.conf` | `/usr/lib/tmpfiles.d/delta-greeter.conf` | каталоги `/var/lib/delta-greeter`, `/var/cache/delta-greeter` |
| `../../bin/delta-greeter-sync` | `/usr/bin/delta-greeter-sync` | копирует вид пользователя для экрана входа |

## Как вид пользователя попадает на экран входа

Greeter работает от `greeter` и не может читать домашние каталоги. Поэтому:

1. Оболочка пользователя (lock/Lock.qml) через 5 с после смены оформления,
   обоев, часов или аватара запускает `delta-greeter-sync` **от имени
   пользователя**. Тот пишет в `/var/lib/delta-greeter/users/<логин>/`:
   `settings.json` (только оформление, часы, экран блокировки и его виджеты,
   без музыки и уведомлений), `wallpaper.jpg` (уменьшенная копия; видеообои
   не копируются — берётся `wallpaper.poster`, если задан), `avatar`.
2. Права: `users/` — `root:root 1733` (как `/tmp`, но без чтения списка).
   Каждый может создать свой каталог, но не может читать список или менять
   чужие. Greeter берёт каталог, только если его владелец (uid) — пользователь
   с этим именем, поэтому подложить вид «за другого» нельзя. Худшее, что может
   сделать другой пользователь, — заранее занять каталог с чужим именем; тогда
   у того пользователя экран входа будет в виде по умолчанию, а
   `delta-greeter-sync` сообщит об этом.
3. Аватар greeter ищет сначала в AccountsService (`/var/lib/AccountsService/icons/<логин>`,
   его меняют «Настройки» → Профиль), затем в каталоге пользователя.
4. Greeter копирует `settings.json` выбранного пользователя в
   `/var/cache/delta-greeter/config/delta/settings.json` (это его
   `XDG_CONFIG_HOME`, задан в `hyprland.lua`) — общий `Settings` применяет тему,
   как в оболочке. Там же `state.json` — последний пользователь и сессия.
5. Выключить: «Настройки» → Экран блокировки → «Показывать мои обои на экране
   входа» (ключ `greeter.sync`) — оболочка вызовет `delta-greeter-sync --remove`.

Root, polkit и системные службы для этого не нужны.

## Установка (для сборщика ISO)

```bash
pacman -S greetd                         # создаёт пользователя greeter и greetd.service
install -Dm644 config.toml   /etc/greetd/config.toml
install -Dm644 pam.d-greetd  /etc/pam.d/greetd
install -Dm644 hyprland.lua  /usr/share/delta/session/greetd/hyprland.lua
install -Dm644 tmpfiles.conf /usr/lib/tmpfiles.d/delta-greeter.conf
install -Dm755 ../../bin/delta-greeter-sync /usr/bin/delta-greeter-sync
systemd-tmpfiles --create /usr/lib/tmpfiles.d/delta-greeter.conf
systemctl disable gdm.service sddm.service 2>/dev/null; systemctl enable greetd.service
```

В PKGBUILD: `depends+=(greetd)` (или оставить в optdepends и ставить эти
файлы отдельным пакетом `delta-greeter`), `backup=(etc/greetd/config.toml)`.
`/etc/pam.d/greetd` принадлежит пакету greetd — либо `install` в
`.install`-скрипте, либо `NoExtract`/замена через свой пакет.

## «Входить без пароля»

В `config.toml` раскомментировать `[initial_session]` с нужным пользователем
(это делает установщик или «Настройки» через polkit — меняется `/etc`).
Сессия стартует сразу; если в настройках включено `lock.onStart`, оболочка
первым делом показывает экран блокировки (как в Windows). Минус: связка
ключей GNOME не откроется сама — `pam_gnome_keyring` не получит пароль.

## Проверка без greetd

```bash
DELTA_GREETER_MOCK=1 DELTA_GREETER_DIR=$PWD/build/greeter-data \
DELTA_DEV_NAME=lock DELTA_DEV_HIDDEN=1 DELTA_SHELL_ENTRY=delta/shell/greeter.qml \
    tools/delta-dev.sh nested 300
DELTA_DEV_NAME=lock DELTA_SHELL_ENTRY=delta/shell/greeter.qml tools/delta-dev.sh ipc call greeter submit delta
```

В режиме проверки пароль `delta` подходит, остальные — нет; запуск сессии,
перезагрузка и выключение только пишутся в журнал. Каталог вида для проверки:
`mkdir -p build/greeter-data/users && chmod 1733 build/greeter-data/users &&
HOME=build/delta-home-lock DELTA_GREETER_DIR=$PWD/build/greeter-data delta/bin/delta-greeter-sync`.

Проверить конфиг композитора: `Hyprland --verify-config -c hyprland.lua`.
