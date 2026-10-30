# Vanks Setup

Скачивает Vanks OS из релизов GitHub и записывает её:

- **в папку** — образ `.iso` и рядом папка `vankos` с выбранной оболочкой;
- **на флешку** — загрузочная сразу, с неё ставится система;
- **на диск** — другой диск компьютера целиком (включается в настройках
  программы; системный диск не показывается никогда).

Версии — все релизы с пакетом оболочки Delta, по умолчанию самая новая.
Если в релизе нет своего образа, берётся образ из самого нового релиза, где
он есть, а выбранная оболочка ставится поверх: на флешке после образа
появляется раздел `VANKOS` с пакетом, установщик системы берёт его оттуда
(`iso/airootfs/usr/local/lib/vankos/desktop.sh`).

## Запуск

Arch Linux, в терминале:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/ArtyomVank/Vanks0s/main/setup/get.sh)
```

Сразу на флешку или в папку: `… get.sh) --usb /dev/sdb`, `--folder ~/Загрузки`,
версии: `--list`, своя версия: `--version 0.4.0`.

Windows — `VanksSetup.exe` из релиза (попросит права администратора).
Linux с окном — `vanks-setup-linux-x86_64` из релиза.

## Устройство

| Файл | Что делает |
|---|---|
| `vanks_setup/releases.py` | версии из API GitHub, куски образа `.iso.partN` |
| `vanks_setup/download.py` | загрузка с докачкой, проверка sha256 |
| `vanks_setup/devices.py` | флешки и диски (lsblk / Get-Disk) |
| `vanks_setup/writer.py` | запись, сверка, раздел `VANKOS` |
| `vanks_setup/cli.py` | терминал |
| `vanks_setup/gui/` | окно: PySide6 + QML |
| `get.sh` | команда для терминала |
| `build.sh` | один исполняемый файл (PyInstaller) |

Образ для релиза режет `tools/iso-release.sh` (GitHub не берёт файлы больше
2 ГБ — куски по 1900 МиБ). `.exe` и файл для Linux собирает GitHub Actions
(`.github/workflows/setup.yml`) при публикации релиза.

## Проверка без сети и без флешки

```bash
VANKS_SETUP_API=http://127.0.0.1:8765 VANKS_SETUP_REPO=test/r \
VANKS_SETUP_TEST_DEVICE=1 VANKS_SETUP_TEST_DISK=/tmp/usb.img \
python3 -m vanks_setup --usb /tmp/usb.img --yes
```

`VANKS_SETUP_TEST_DEVICE=1` — «флешка» обычный файл: без прав root и без
размонтирования. Окно: `--gui`, `VANKS_SETUP_STEP=1` открывает сразу шаг,
`VANKS_SETUP_AUTO="usb|/tmp/usb.img"` сразу начинает запись.
