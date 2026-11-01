# Как проверять Vanks Shell

## 1. Окно отладки — безопасно, в любой момент

Внутри Hyprland/Delta оболочка открывается обычным окном, ничего не захватывая:

```bash
tools/run-nested.sh
```

Так проверяются окна, фокус, сочетания, раскладки, буфер обмена, фигуры курсора.

То же с Delta из исходников рядом (`../vankos`), со своей папкой HOME
(`build/delta-home`) и своей шиной D-Bus — настоящие настройки не трогаются:

```bash
tools/run-delta.sh
```

Внутри работает обычный `hyprctl`, если взять подпись из окружения программы
внутри сессии (`HYPRLAND_INSTANCE_SIGNATURE`):

```bash
hyprctl -j clients
hyprctl dispatch 'hl.dsp.focus({workspace=2})'
```

Команды самой Delta — по pid её копии `qs` (без ввода пароля):

```bash
qs ipc --pid <pid> call lock lock
qs ipc --pid <pid> call lock unlock
```

## 2. Что увидит настоящая сессия — тоже безопасно

```bash
target/debug/vanks-shell --probe
```

Покажет видеокарты (основную — стрелкой), подключённые мониторы с именами
из EDID, доступ к месту (logind/seatd) и раскладки из настроек Delta.
Ничего не захватывает, можно запускать из Hyprland.

## 3. Настоящая сессия — с текстовой консоли

Здесь Vanks Shell сама ведёт видеокарту и ввод — как Hyprland. Delta на
своей консоли при этом продолжает работать.

1. Соберите: `cargo build --release`.
2. **Ctrl+Alt+F3** — текстовая консоль, войдите под своим именем.
3. Запустите:
   ```bash
   cd "/run/media/artyom/Новый том/vankos-0.1-src/vanks-shell"
   target/release/vanks-shell --backend tty 2> /tmp/vanks-shell.log
   ```
4. Должен появиться тёмно-фиолетовый экран, курсор и терминал (kitty).

С Delta из исходников (своя папка HOME и шина D-Bus, как в окне отладки):

```bash
tools/run-delta.sh --tty 2> /tmp/vanks-shell.log
```

Delta, установленная в систему, запускается и без этого: оболочка находит
`delta-shell` в PATH.

Как выйти:

| Что | Как |
|---|---|
| выйти из Vanks Shell | **Super+Shift+E** |
| если сочетание не сработало | **Ctrl+Alt+Backspace** |
| вернуться в Delta, не закрывая | **Ctrl+Alt+F1** / **F2** (где идёт Delta) |
| совсем зависла | с другой консоли: `pkill -x vanks-shell` |

Журнал — в `/tmp/vanks-shell.log` (подробнее: `RUST_LOG=debug`).

## 4. С экрана входа

```bash
tools/install-session.sh           # просит sudo; ставит в /usr/local и wayland-sessions
tools/install-session.sh --remove  # убрать
```

На экране входа Delta появится «Vanks Shell (разработка)». Журнал:
`journalctl -t vanks-shell -b`.

## Что смотреть на железе в Delta

- Super — меню приложений, щелчок мимо него — закрывается;
- Super+L — экран блокировки, пароль снимает его; Ctrl+Alt+F1 — другая консоль,
  остальные сочетания при блокировке не работают;
- окна: кнопки Delta в углу, развернуть, свернуть, столы Super+1…9;
- полный экран у видео и игр; простой гасит экран и блокирует его по настройкам;
- `journalctl -t vanks-shell -b` не пишет «программа отключена за ошибку протокола».

## Что смотреть на железе

- монитор включился в родном разрешении (1920×1080 у MKG MJF24F200);
- курсор двигается плавно, не мерцает; над текстом в kitty — «I»-курсор;
- в kitty печатается; Alt+Shift переключает на русский; Caps Lock горит;
- тачпад: касание — щелчок, прокрутка двумя пальцами;
- Ctrl+Alt+F1 → Delta, обратно Ctrl+Alt+F3 → Vanks Shell снова рисует;
- выдернуть/вставить кабель монитора — экран возвращается.

**NVIDIA:** нужен `nvidia_drm.modeset=1` (он уже нужен Hyprland). Накладные
плоскости отключены — как раз из-за NVIDIA; курсор идёт на свою плоскость.
