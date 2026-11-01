# Композитор Delta

Композитор графического окружения Delta с версии 1.0: на Rust и
[Smithay](https://github.com/Smithay/smithay), без Hyprland. Оболочка Delta
(`../delta`, Quickshell) работает на нём без отдельной сборки: композитор отвечает
ей как Hyprland 0.57, поэтому и `hyprctl` работает как обычно.

## Что умеет

- **Настоящая сессия:** сам ведёт видеокарту (DRM/KMS) и ввод (libinput) через
  libseat, горячее подключение мониторов, XWayland, снимки и запись экрана.
- **Окна:** скругление, рамка и тень; размытие и линза жидкого стекла с настоящим
  фоном, а не с обоями; правила размеров (`src/rules.rs`).
- **Анимации:** появление окна сборкой из осколков (`assemble`) и изнутри, из капли
  (`inside`), а также `popin`, `slide`, `fade`; пружины размера и места, смена столов.
- **Перетаскивание:** «желе» считает сам композитор на каждом кадре экрана.

Настройки читает из `~/.config/delta/settings.json` (разделы `windows`,
`appearance`, `input`, `monitors`).

## Чего пока нет

Tearing, VRR, HDR, зеркалирование, ночной свет (гамма), вторая видеокарта. Кадры
пока считаются по опросу, а не только по изменениям. Эти функции есть в сессии
«Delta на Hyprland».

## Запуск

Как часть Delta: `delta-session` (пункт «Delta» на экране входа). Не поднялся за
15 секунд — `delta-session` откроет Hyprland.

Для разработки, в окне и из исходников:

```bash
tools/run-delta.sh
```

Сборка: `cargo build --release`. Тесты: `cargo test`. Пакетом занимается
`packaging/delta/PKGBUILD`. Подробнее: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md),
[docs/TESTING.md](docs/TESTING.md), [docs/ROADMAP.md](docs/ROADMAP.md).
