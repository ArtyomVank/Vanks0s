# Delta — договорённости между модулями

Этот файл читают все, кто пишет модули оболочки (в том числе параллельно).
Цель: модули делаются одновременно и не ломают друг друга.

## 1. Кто чем владеет

Писать можно **только в свои файлы**. Чужие — только читать.

| Модуль | Владеет |
|---|---|
| A · Доки, уведомления, OSD | `docks/`, `notify/`, `osd/`, `menus/NotificationsMenu.qml`, `settings/sections/Docks.qml`, `settings/sections/Notifications.qml`, `dev-docks.qml` |
| B · Блокировка, вход, питание | `lock/`, `greeter/`, `greeter.qml`, `menus/PowerMenu.qml`, `settings/sections/Lock.qml`, `settings/sections/Power.qml`, `../session/greetd/`, `dev-lock.qml` |
| C · Лаунчер, обои, быстрые меню | `launcher/`, `walls/`, `wallpaper/`, `menus/{Wifi,Bluetooth,Sound,Media,Battery,Lang,Calendar,Workspaces}Menu.qml`, `settings/sections/{Wallpapers,Sound,Network,Bluetooth}.qml`, `dev-launcher.qml` |
| D · Виджеты | `widgets/`, `services/`, `menus/{Weather,Pc}Menu.qml`, `settings/sections/Widgets.qml`, `dev-widgets.qml` |
| E · Экран | `display/`, `../bin/delta-monitors`, `settings/sections/Display.qml`, `dev-display.qml` |
| F · Приложение «Настройки» | `settings/` (кроме чужих `sections/*.qml`), `settings-app.qml`, `../bin/delta-settings`, `settings/sections/{Appearance,Windows,Keyboard,Mouse,Profile,Users,About,DateTime,Language,DefaultApps,Autostart,Updates,GitHub}.qml`, `dev-settings.qml` |
| Фаза 2 · интегратор | `minimize/` (сворачивание, «джинн»), `window/` (кнопки окна), `appearance/` (оформление GTK/Qt), `polkit/`, `../bin/delta-autologin`, `../session/polkit/` |

Общие файлы — **не трогать** (меняет только интегратор):
`shell.qml`, `common/**`, `hypr/hyprland.lua`, `defaults/settings.json`,
`packaging/`, `tools/`. Если там чего-то не хватает — напишите в отчёте.

Иконки: можно **добавлять** новые `icons/<имя>.svg` (24×24, белая линия 1.8,
как остальные). Существующие не менять.

## 2. Общие кирпичи

```qml
import qs.common      // Settings, Theme, ShellState, Shortcuts, Icons
import qs.common.ui   // Glass, Label, Sym, Btn, Toggle, Slider, Chips, SettingRow, Card
```

- Цвета, радиусы, шрифты, длительности — только из `Theme` (никаких своих `#hex`,
  кроме содержимого вроде обложек и графиков погоды).
- Иконки — `Sym { name: "wifi" }` (файлы в `icons/`).
- Тексты интерфейса — по-русски.
- Не хватает компонента — сделайте его у себя (`<модуль>/parts/…`) и упомяните
  в отчёте: интегратор может перенести его в `common/ui`.

## 3. Настройки

- Читать: `Settings.get("раздел.ключ", значениеПоУмолчанию)` — **всегда с
  умолчанием**, потому что в `defaults/settings.json` вашего ключа ещё нет.
- Писать: `Settings.set("раздел.ключ", значение)`.
- В отчёте перечислите все новые ключи с умолчаниями — интегратор добавит их в
  `defaults/settings.json`. Существующие ключи смотрите там же.
- Разделы `monitors`, `display`, `windows`, `input`, `appearance` после записи автоматически
  применяются к Hyprland через `delta-apply`. Новые поля для Hyprland — в отчёт.

## 4. Как модуль подключается к оболочке

Каждый модуль даёт один-два корневых компонента; интегратор вставит их в `shell.qml`:

| Компонент | Сколько экземпляров |
|---|---|
| `docks/Docks.qml` — `Scope { required property ShellScreen screen }` | на каждый монитор |
| `notify/Notifications.qml`, `osd/Osd.qml` | один (сервер уведомлений должен быть один) |
| `lock/Lock.qml` | один |
| `launcher/Launcher.qml`, `walls/Wallpapers.qml` | один |
| `wallpaper/Wallpaper.qml` — `PanelWindow { screen }` | на каждый монитор |
| `widgets/Widgets.qml` — `Scope { required property ShellScreen screen }` | на каждый монитор |
| `window/WindowControls.qml` — `Scope`, сам создаёт слой на каждый монитор | один |
| `window/SettingsGhost.qml`, `wallpaper/DesktopMenu.qml`, `widgets/DeskClear.qml` — `Scope` | один |

Связь между модулями — через `ShellState` (открытое окно оболочки, открытое
меню, блокировка, уведомления, геометрия доков) и через глобальные сочетания
`Shortcuts` (их список — в `common/Shortcuts.qml`, привязки — в `hyprland.lua`).
Нужен новый сигнал, сочетание или поле `ShellState` — в отчёт.

- «Настройки» открывать только через `ShellState.openSettings(раздел, откуда)`:
  окно выходит каплей из верхнего дока (`window/SettingsGhost.qml`).
- Окно или меню, которое закрывается нажатием мимо (`HyprlandFocusGrab`),
  отмечает это `ShellState.noteDismiss(имя)` — тогда тот же клик по кнопке
  дока не откроет его снова (`toggleOverlay`, `openMenu` это проверяют).
- Меню рабочего стола: `ShellState.openDesktopMenu(screen, x, y)` / `closeDesktopMenu()`.

## 5. Меню модулей верхнего дока

Док (A) рисует кнопку модуля, подложку меню и анимацию «капля → меню». Содержимое
меню — отдельный файл `menus/<Id>Menu.qml` у владельца (таблица выше). Док
загружает его через `Loader { source: Quickshell.shellDir + "/menus/<Id>Menu.qml" }`;
если файла ещё нет, показывает заглушку.

Корень файла меню:

```qml
Item {
    implicitWidth: 360          // ширина меню
    implicitHeight: column.implicitHeight
    signal close()              // попросить док закрыть меню
    // фон не рисовать — его рисует док (Glass)
}
```

id модулей: `launcher`, `workspaces`, `media`, `lang`, `wifi`, `bluetooth`,
`sound`, `battery`, `power`, `weather`, `pc`, `notifications`, `calendar`.

## 6. Разделы «Настроек»

Файл `settings/sections/<Имя>.qml`. Приложение «Настроек» (F) показывает
список слева, а раздел справа в прокручиваемой области заданной ширины.

```qml
import QtQuick
import QtQuick.Layouts
import qs.common
import qs.common.ui

ColumnLayout {
    property string title: "Доки"
    property string icon: "dock"
    property string keywords: "панель автоскрытие край"   // для поиска
    spacing: 18
    Card { title: "Нижний док"; SettingRow { … } }
}
```

Только `Card` / `SettingRow` / элементы из `common/ui` — чтобы разделы выглядели одинаково.

## 7. Проверка

```bash
DELTA_DEV_NAME=<модуль> DELTA_DEV_HIDDEN=1 DELTA_SHELL_ENTRY=delta/shell/dev-<модуль>.qml tools/delta-dev.sh nested 300
```

```bash
DELTA_DEV_NAME=<модуль> tools/delta-dev.sh shot /путь/снимок.png
```

```bash
DELTA_DEV_NAME=<модуль> tools/delta-dev.sh log
```

```bash
DELTA_DEV_NAME=<модуль> tools/delta-dev.sh ipc call <target> <функция> [аргументы]
```

```bash
DELTA_DEV_NAME=<модуль> tools/delta-dev.sh stop
```

```bash
tools/delta-dev.sh check
```

- `DELTA_DEV_HIDDEN=1` обязателен для фоновой работы: окно вложенной сессии
  уходит на скрытый рабочий стол и не мешает пользователю. Размер экрана там 1280×800.
- `DELTA_DEV_PRIVATE_BUS=1` — своя сессионная шина D-Bus. Нужна, чтобы занять
  имя сервера уведомлений, видеть только свои MPRIS-плееры, трей и т. п.
  Программы внутрь сессии: `tools/delta-dev.sh exec notify-send "Заголовок" "Текст"`,
  `tools/delta-dev.sh exec mpv --no-video файл.mp3` (MPRIS через mpv-mpris, если есть).
  Системная шина (NetworkManager, BlueZ, UPower, logind) общая — **ничего не меняйте
  в системе** при проверке: не подключайте сети, не сопрягайте устройства,
  не выключайте и не усыпляйте компьютер. Проверяйте чтение и интерфейс.
- `dev-<модуль>.qml` — своя точка входа: `ShellRoot` с обоями (`Wallpaper`) и
  только вашим модулем. Для проверки удобно добавить в неё `IpcHandler`.
- Ввод мыши и клавиатуры во вложенную сессию не подать: состояния проверяйте
  через IPC (открыть меню, включить режим редактирования, подставить данные).
- **Всегда** закрывайте сессию (`stop`) и держите не больше одной своей.
- После правки QML: `ipc call shell reload` не нужен — перезапустите `nested`.
- `tools/delta-dev.sh check` должен проходить.

## 8. Подводные камни (собраны в фазе 1)

- **Модули `qs.*` у файлов, которые грузятся по пути** (`Loader { source: … }`):
  меню доков и разделы «Настроек». Quickshell находит модуль, только если его
  где-то импортируют статически. Новый `import qs.<модуль>` в таком файле —
  повод добавить этот импорт в `shell.qml` (оболочка) или `settings-app.qml`
  («Настройки»). Иначе будет ошибка «module is not installed» или «X is not a type».
- **Имена `state` и `layer` в корне компонента не занимать:** они уже есть у
  Item, а `layer` ещё и FINAL.
- **Диспетчеры Hyprland в Lua передаются выражением:**
  `Hyprland.dispatch("hl.dsp.focus({ workspace = 2 })")`.
  Старая форма `workspace 2` не работает.
- **«Настройки» — отдельный процесс** (`delta-settings <раздел>`). Оболочку они
  зовут через IPC: `delta-shell ipc call <цель> <функция>`.
- **`tools/delta-dev.sh exec` и `ipc` нацелены на вложенный Hyprland**
  (`HYPRLAND_INSTANCE_SIGNATURE`). Простой `hyprctl` вне них попадает в основной
  Hyprland пользователя.
- **Новая вложенная сессия получает масштаб 1** и пустой `settings.json` (только
  `monitors`): значения по умолчанию подмешиваются. Чтобы начать с чистого листа,
  удалите `build/delta-home-<имя>`.
- **Шейдеры** (`*.vert`, `*.frag`) собираются в `.qsb` командой
  `tools/delta-shaders.sh`. Собранные файлы лежат в репозитории, а `check`
  проверяет, что они не старше исходников.
- **Свёрнутое окно лежит на `special:minimized`.** Чтобы показать окно,
  вызывайте `Minimizer.restore(окно)`, а не `activate()`: свёрнутое окно
  `activate()` не покажет.

