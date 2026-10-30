"""Vanks Setup в терминале.

    vanks-setup                         по шагам: версия → куда → запись
    vanks-setup --list                  версии из релизов GitHub
    vanks-setup --folder ~/Загрузки     образ в папку (версия — самая новая)
    vanks-setup --usb /dev/sdb          на флешку
    vanks-setup --disk /dev/sdc --allow-disks
                                        на другой диск (не системный)
    --version 0.4.0   версия оболочки (по умолчанию самая новая)
    --yes             не спрашивать подтверждение (вместе с --usb/--disk)
    --prerelease      показывать и предварительные версии

Запись на флешку — через sudo: пароль спросит sudo, остальное идёт от
вашего пользователя (загрузка — в ~/.cache/vanks-setup).
"""

import argparse
import json
import os
import sys
import threading
import time

from . import VERSION, releases, download, devices, writer
from .releases import human

STAGES = {"download": "Загрузка", "verify": "Проверка", "write": "Запись", "check": "Сверка", "extra": "Раздел VANKOS"}
TTY = sys.stdout.isatty()


def color(code, text):
    return f"\033[{code}m{text}\033[0m" if TTY else text


def say(text=""):
    print(text, flush=True)


def fail(text):
    say(color("1;31", "Ошибка: ") + text)
    sys.exit(1)


class Bar:
    """Строка прогресса: стадия, полоса, проценты, сколько из скольких, скорость."""
    def __init__(self):
        self.stage = None
        self.t0 = 0
        self.d0 = 0
        self.last = 0

    def __call__(self, stage, done, total):
        now = time.monotonic()
        if stage != self.stage:
            if self.stage:
                sys.stdout.write("\n")
            self.stage, self.t0, self.d0 = stage, now, done
        if now - self.last < 0.15 and done < total:
            return
        self.last = now
        k = done / total if total else 1
        width = 28
        bar = "█" * int(k * width) + "░" * (width - int(k * width))
        speed = (done - self.d0) / max(0.001, now - self.t0)
        tail = f"{human(done)} из {human(total)}" if total > 1 else ""
        if speed > 0 and total > 1 and stage in ("download", "write"):
            tail += f"  {human(speed)}/с"
        line = f"\r  {STAGES.get(stage, stage):<14} {color('35', bar)} {int(k * 100):3d} %  {tail}"
        sys.stdout.write(line.ljust(96))
        sys.stdout.flush()

    def end(self):
        if self.stage:
            sys.stdout.write("\n")
            self.stage = None


def ask(prompt, default=None):
    try:
        v = input(f"{prompt}{f' [{default}]' if default is not None else ''}: ").strip()
    except EOFError:
        v = ""
    return v or (str(default) if default is not None else "")


def pick(prompt, items, default=1):
    while True:
        v = ask(prompt, default)
        if v.isdigit() and 1 <= int(v) <= len(items):
            return items[int(v) - 1]
        say("  Введите номер из списка.")


def downloads_dir():
    for name in ("Загрузки", "Downloads"):
        p = os.path.expanduser("~/" + name)
        if os.path.isdir(p):
            return p
    return os.path.expanduser("~")


def main(argv=None):
    ap = argparse.ArgumentParser(prog="vanks-setup", description="Скачать Vanks OS и записать в папку или на флешку.")
    ap.add_argument("--list", action="store_true", help="показать версии и выйти")
    ap.add_argument("--version", dest="ver", help="версия оболочки Delta (по умолчанию — самая новая)")
    ap.add_argument("--folder", help="сохранить образ в папку")
    ap.add_argument("--usb", help="записать на флешку (например, /dev/sdb)")
    ap.add_argument("--disk", help="записать на диск (нужен --allow-disks)")
    ap.add_argument("--allow-disks", action="store_true", help="разрешить запись на внутренние диски")
    ap.add_argument("--yes", action="store_true", help="не спрашивать подтверждение")
    ap.add_argument("--prerelease", action="store_true", help="показывать предварительные версии")
    ap.add_argument("-V", action="version", version="vanks-setup " + VERSION)
    a = ap.parse_args(argv)

    say(color("1;35", "Vanks Setup ") + VERSION)
    say("Получаю версии с GitHub…")
    try:
        rels = releases.fetch()
    except Exception as e:
        fail(f"не удалось получить список версий: {e}")
    versions = releases.shell_versions(rels, a.prerelease)
    if not versions:
        fail("в релизах нет ни одной версии оболочки")

    if a.list:
        for i, r in enumerate(versions):
            img = releases.image_for(rels, r)
            note = "своя сборка образа" if r.image else (f"образ из {img.tag}" if img else "образа нет")
            say(f"  {r.version:<10} {r.title} · {r.date} · {note}{'  ← самая новая' if i == 0 else ''}")
        return

    interactive = not (a.folder or a.usb or a.disk)

    # ---- версия ----
    if a.ver:
        chosen = next((r for r in versions if r.version == a.ver.lstrip("vV")), None)
        if not chosen:
            fail(f"версии {a.ver} нет. Есть: " + ", ".join(r.version for r in versions))
    elif interactive:
        say("\nВерсии Delta:")
        for i, r in enumerate(versions, 1):
            say(f"  {i}) {r.version:<9} {r.title} · {r.date}{color('32', '  ← самая новая') if i == 1 else ''}")
        chosen = pick("Версия", versions)
    else:
        chosen = versions[0]
    image = releases.image_for(rels, chosen)
    if not image:
        fail("ни в одном релизе нет образа системы")
    say(f"\nОбраз системы: {image.name} ({human(image.size)}, из {image.tag})")
    say(f"Оболочка Delta {chosen.version} — установится вместе с системой")

    # ---- куда ----
    allow = a.allow_disks or bool(a.disk)
    if interactive:
        targets = [("folder", "В папку на этом компьютере"), ("usb", "На флешку (загрузочную)")]
        if allow:
            targets.append(("disk", "На диск (все данные на нём будут удалены)"))
        say("\nКуда записать:")
        for i, (_, label) in enumerate(targets, 1):
            say(f"  {i}) {label}")
        kind = pick("Куда", targets)[0]
    else:
        kind = "folder" if a.folder else "usb" if a.usb else "disk"

    folder, disk = None, None
    if kind == "folder":
        folder = os.path.abspath(os.path.expanduser(a.folder or ask("Папка", downloads_dir())))
    else:
        try:
            disks = devices.list_disks(allow_internal=(kind == "disk"))
        except Exception as e:
            fail(f"не удалось получить список дисков: {e}")
        if kind == "usb":
            disks = [d for d in disks if d.removable]
        wanted = a.usb or a.disk
        if wanted:
            disk = next((d for d in disks if d.path == wanted), None)
            if not disk:
                fail(f"{wanted} нет среди доступных ({', '.join(d.path for d in disks) or 'ничего не найдено'}). "
                     "Системный диск не показывается никогда")
        else:
            if not disks:
                fail("флешка не найдена — вставьте её и запустите ещё раз")
            say("\nУстройства:")
            for i, d in enumerate(disks, 1):
                say(f"  {i}) {d.label}")
            disk = pick("Устройство", disks)
        if disk.size < image.size:
            fail(f"{disk.label}: мало места, нужно {human(image.size)}")
        if not a.yes:
            say(color("1;33", f"\nВсе данные на «{disk.name or disk.path}» ({disk.path}, {human(disk.size)}) будут удалены."))
            if ask("Напишите «да», чтобы продолжить").lower() not in ("да", "yes", "y", "д"):
                say("Отменено.")
                return

    # ---- загрузка ----
    bar = Bar()
    cancel = threading.Event()
    try:
        say("")
        parts = download.get_image(image, bar, cancel)
        shell = download.get_shell(chosen, cancel) if chosen.shell else None
        bar.end()
        choice = writer.choice_json(chosen, image)
        if kind == "folder":
            iso = writer.to_folder(parts, image, folder, shell, choice, bar, cancel)
            bar.end()
            say(color("1;32", "\nГотово: ") + iso)
            if shell:
                say(f"Оболочка {chosen.version}: {os.path.join(folder, 'vankos')}. Если пишете флешку через Ventoy — скопируйте")
                say("папку vankos в корень флешки рядом с образом. Без неё поставится оболочка, которая есть в образе.")
            return
        job = {"parts": parts, "total": image.size, "sha": download.expected_sha(image.sha256),
               "disk": {"path": disk.path, "size": disk.size, "number": disk.number},
               "shell": shell, "choice": choice}
        if writer.need_elevation():
            say("Для записи нужны права администратора — sudo спросит пароль.")
            ok = writer.run_elevated(job, bar, cancel, via="sudo")
        else:
            ok = writer.job_device(job, bar, cancel)
        bar.end()
    except KeyboardInterrupt:
        cancel.set()
        bar.end()
        say("\nОстановлено. Скачанное сохранено — при следующем запуске загрузка продолжится.")
        sys.exit(130)
    except (download.DownloadError, writer.WriteError, download.Cancelled) as e:
        bar.end()
        fail(str(e) or "отменено")

    say(color("1;32", "\nГотово: ") + f"Vanks OS записана на {disk.label}.")
    if shell and not ok:
        say("На флешке не хватило места для раздела VANKOS — установится оболочка из образа.")
    say("Загрузитесь с неё: при включении компьютера — меню загрузки (обычно F12, F8 или Esc).")


def helper():
    """Запись от root: задание — JSON-файл, ход — строками в stdout."""
    path = sys.argv[-1]
    with open(path, encoding="utf-8") as f:
        job = json.load(f)

    def progress(stage, done, total):
        print(f"P {stage} {done} {total}", flush=True)
    try:
        ok = writer.job_device(job, progress)
        print("D " + ("1" if ok else "0"), flush=True)
    except Exception as e:
        print("E " + str(e).replace("\n", " "), flush=True)
        sys.exit(1)
