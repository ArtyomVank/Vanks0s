# Delta — исходники

Спецификация и план: [docs/DELTA.md](../docs/DELTA.md).

```
bin/delta-session     запуск сессии: окружение, settings.json, delta-apply, Hyprland
bin/delta-apply       settings.json → ~/.config/delta/hypr/generated.lua (с проверкой)
bin/delta-shell       запуск оболочки Quickshell под присмотром (упала — снова), `delta-shell ipc …`
hypr/hyprland.lua     базовый конфиг Hyprland (Lua), подключает generated.lua и user.lua
defaults/settings.json  значения по умолчанию для всех настроек
shell/                оболочка (QML, Quickshell 0.3)
  shell.qml           точка входа
  common/             Settings, Theme, Shortcuts — общие для всех модулей
  wallpaper/          обои
  docks/              доки
session/              delta.desktop, delta-portals.conf
```

Пакет: `packaging/delta/PKGBUILD` (ставит всё в `/usr/bin` и `/usr/share/delta`).

## Как устроены настройки

- Один файл `~/.config/delta/settings.json`. При первом входе копируется из
  `defaults/settings.json`; новые ключи из обновлений подмешиваются сами.
- В QML: читать `Settings.get("docks.apps.edge", "bottom")` или `Settings.s.<раздел>`,
  писать `Settings.set("docks.apps.edge", "left")`. Запись на диск — через 250 мс,
  чтобы ползунки не дёргали диск.
- Если меняется раздел `monitors`, `windows`, `input` или `appearance`, оболочка
  сама запускает `delta-apply`. Тот проверяет новый конфиг через
  `Hyprland --verify-config` и только потом заменяет файл и делает `hyprctl reload`.
  Повреждённый JSON или отклонённый конфиг оставляют прежний `generated.lua`.
- Глобальные сочетания: Hyprland шлёт `delta:<имя>` (`hl.dsp.global`), оболочка
  ловит их через `common/Shortcuts.qml`.
- Все поверхности оболочки называются `delta-*`: на них в `hyprland.lua` включено
  размытие и выключены анимации Hyprland, потому что анимирует сама оболочка.

## Разработка

```bash
tools/delta-dev.sh check
```

Проверка без запуска: синтаксис скриптов, JSON, конфиг Hyprland, синтаксис QML.

```bash
tools/delta-dev.sh nested 600
```

Delta в окне внутри текущей сессии Hyprland, с отдельным HOME в
`build/delta-home`, поэтому ваш `~/.config/delta` не затрагивается.

```bash
tools/delta-dev.sh ipc call shell set docks.apps.autohide false
```

```bash
tools/delta-dev.sh shot
```

```bash
tools/delta-dev.sh log
```

`ipc call shell reload` перезагружает оболочку после правки QML без перезапуска
Hyprland.
