# Как устроена Vanks Shell

Один процесс, один цикл событий ([calloop](https://github.com/Smithay/calloop)).
Источники событий — сокет Wayland (новые программы), сам Display (сообщения
программ) и бэкенд (кадры экрана и ввод). Каждый обработчик получает
`CalloopData { state: Shell, display_handle }`.

```
            ┌──────────── цикл событий calloop ────────────┐
программы → │ ListeningSocket → Display → обработчики       │
            │                    протоколов (handlers/)     │
бэкенд    → │ winit/udev: ввод → input.rs → Seat → фокус    │
            │             кадр → space.render_output → GPU  │
            └───────────────────────────────────────────────┘
                              Shell (state.rs)
```

## Модули

| Файл | Что делает |
|---|---|
| `main.rs` | ключи запуска, выбор бэкенда, сигналы, цикл событий, первая программа |
| `state.rs` | `Shell` — всё состояние: Space с окнами, состояния протоколов, место ввода (Seat); фокус, размещение окон, запуск программ |
| `config.rs` | постоянные (фон, каскад) и переменные окружения |
| `settings.rs` | настройки Delta: `~/.config/delta/settings.json` поверх умолчаний Delta |
| `input.rs` | клавиатура и мышь: сочетания оболочки, щелчок поднимает окно, Super+перетаскивание |
| `handlers/` | протоколы Wayland: `compositor.rs` (кадры поверхностей), `xdg_shell.rs` (окна, меню, просьбы тащить и менять размер, xdg-decoration), `layer_shell.rs` (панели Delta), `mod.rs` (seat, буфер обмена, выходы, dmabuf, запрет простоя) |
| `grabs/` | захваты мыши: перемещение и изменение размера окна |
| `backend/mod.rs` | какой бэкенд: внутри графической сессии — winit, с консоли — udev |
| `backend/winit.rs` | окно отладки: выход размером с окно, ввод из него, отрисовка через GLES; курсор — у сессии вокруг |
| `backend/udev.rs` | настоящая сессия: libseat, видеокарта (DRM/GBM/EGL), мониторы и их кадры, libinput, консоли |
| `render.rs` | элементы кадра выхода: курсор поверх окон, при блокировке — только замок |
| `workspaces.rs` | рабочие столы и свёрнутые, адреса окон, развернуть и полный экран, выбор окна по `address:`/`class:`/`title:` |
| `ipc.rs` | сокеты Hyprland: ответы `j/…` и события для Delta |
| `dispatch.rs` | команды `dispatch`: Lua (`hl.dsp.…`) и старые |
| `lock.rs` | ext-session-lock: блокировка экрана, восстановление после падения замка |
| `protocols/` | протоколы, которых нет в Smithay: `global_shortcuts`, `focus_grab`, `foreign_toplevel` (и toplevel-mapping), `idle_notify` |
| `cursor.rs` | тема курсора xcursor, фигуры по имени, анимация |
| `edid.rs` | производитель и модель монитора из EDID |
| `probe.rs` | `--probe`: что увидит настоящая сессия, без захвата |

## Главные понятия Smithay

- **Space** — плоскость с окнами и выходами. Порядок окон — порядок
  наложения: `raise_element` поднимает окно наверх.
- **Window** — окно программы (xdg_toplevel). Свои данные окна (например, «уже
  поставлено на место») — в `window.user_data()`.
- **Seat** — клавиатура, мышь и касания одного пользователя. Фокус клавиатуры
  — поверхность, которой идут нажатия.
- **Grab** — мышь временно у оболочки (тащим окно): события идут в захват,
  а не программе.
- **delegate_*!** — подключает протокол к `Shell`; для каждого нужен свой
  `*Handler`.

## Как добавить протокол

1. Состояние протокола — поле в `Shell`, создаётся в `Shell::new`.
2. `impl <Протокол>Handler for Shell` — в `handlers/<протокол>.rs`.
3. `delegate_<протокол>!(Shell);` рядом.
4. Если нужна отрисовка — элементы в `render_output` бэкенда.

## Кадры в настоящей сессии

```
таймер → render_screen → output_elements (курсор, окна)
       → DrmOutput::render_frame — сравнение с прошлым кадром
           изменилось → queue_frame → … VBlank → frame_shown → таймер(0)
           нет        → таймер(1 кадр монитора)
       → frame callbacks программам на этом мониторе
```

Ответы программам уходят после каждого прохода цикла событий (main.rs),
а не только с кадром: монитор может спать, а программы ждать.

Консоль ушла (Ctrl+Alt+Fn) — libseat присылает PauseSession: libinput и
DRM на паузе, кадров нет. Вернулась — ActivateSession: всё обратно и кадр.

## Связь с Delta

С 0.3 Delta работает на Vanks Shell без правок в самой Delta: оболочка
отвечает ей как Hyprland 0.57 с конфигом на Lua.

```
Delta (Quickshell) ── Quickshell.Hyprland ──→ сокеты hypr/<подпись>/  ipc.rs, dispatch.rs
                   ── wlr-layer-shell ─────→ handlers/layer_shell.rs
                   ── GlobalShortcut ──────→ protocols/global_shortcuts.rs ← input.rs
                   ── WlSessionLock ───────→ lock.rs
                   ── ToplevelManager ─────→ protocols/foreign_toplevel.rs
                   ── HyprlandFocusGrab ───→ protocols/focus_grab.rs
                   ── IdleMonitor ─────────→ protocols/idle_notify.rs
```

`j/status` сообщает `configProvider: "lua"`: так Quickshell шлёт команды в виде
`hl.dsp.focus({workspace=2})`, а их разбирает `dispatch.rs`. Подпись
`vanks_<время>_<pid>` передаётся программам в `HYPRLAND_INSTANCE_SIGNATURE`,
поэтому и обычный `hyprctl` работает с Vanks Shell.

Дальше — перенос эффектов (стекло, «желе», анимации) в сам композитор. Подробно
— в ROADMAP.

### Обходы ошибок Smithay 0.7

Оба случая одинаковы: программа снимает роль (destroy) и присылает пустой
commit. Протокол это разрешает, а Quickshell так и делает, но проверки Smithay
отключают её за ошибку протокола. Перед ними срабатывают наши проверки, заведённые
в `CompositorHandler::new_surface`: `guard_removed_layer` (`layer_shell.rs`) и
`guard_removed_lock` (`lock.rs`). Если в журнале есть «программа отключена за
ошибку протокола» — смотреть сюда в первую очередь.

`IdleNotifierState` из Smithay требует, чтобы цикл событий работал с тем же типом,
что и Wayland; у нас там `CalloopData`, поэтому `idle_notify.rs` свой.
