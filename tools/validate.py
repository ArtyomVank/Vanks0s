#!/usr/bin/env python3
"""Статическая проверка проекта Vanks OS.

Не требует сторонних библиотек: проверяет структуру, перекрёстные ссылки
(модули Calamares ↔ sequence ↔ файлы), ассеты брендинга, JSON Waybar,
парность скобок в QML и синтаксис shell-скриптов (если есть bash).

Запуск:  python3 tools/validate.py [--root DIR]
Код возврата 0 — проблем нет, 1 — есть ошибки.
"""

from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ERRORS: list[str] = []
WARNINGS: list[str] = []

BUILTIN_MODULES = {
    "welcome", "locale", "keyboard", "partition", "users", "summary",
    "finished", "machineid", "fstab", "localecfg", "networkcfg", "hwclock",
    "bootloader", "initcpiocfg", "initcpio", "umount", "mount", "unpackfs",
    "services-systemd", "displaymanager", "packages", "notes", "license",
}


def err(msg: str) -> None:
    ERRORS.append(msg)


def warn(msg: str) -> None:
    WARNINGS.append(msg)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def check_tree(root: Path) -> None:
    required = [
        "build.sh",
        "iso/profiledef.sh",
        "iso/packages.x86_64",
        "iso/pacman.conf",
        "iso/syslinux/syslinux.cfg",
        "iso/efiboot/loader/loader.conf",
        "iso/lists/target-base.txt",
        "iso/lists/gnome.txt",
        "iso/lists/delta.txt",
        "iso/airootfs/usr/local/lib/vankos/bootstrap.sh",
        "iso/airootfs/usr/local/lib/vankos/desktop.sh",
        "iso/airootfs/usr/local/lib/vankos/cleanup.sh",
        "iso/airootfs/usr/local/bin/vankos-installer",
        "iso/airootfs/usr/local/bin/vankos-live-setup",
        "iso/airootfs/usr/local/bin/vankos-live-session",
        "iso/airootfs/usr/share/vankos/greetd-live.toml",
        "iso/efiboot/loader/entries/vankos-safe.conf",
        "tools/build-delta.sh",
        "packaging/delta/PKGBUILD",
        "iso/airootfs/etc/mkinitcpio.conf.d/archiso.conf",
        "iso/efiboot/loader/entries/vankos.conf",
        "calamares/settings.conf",
        "calamares/branding/vankos/branding.desc",
        "calamares/branding/vankos/show.qml",
        "calamares/modules/shellchooser.conf",
    ]
    for rel in required:
        if not (root / rel).exists():
            err(f"нет обязательного файла: {rel}")


def check_boot_root(root: Path) -> None:
    """Загрузка ISO: обязательные archiso-хуки и ASCII в меню загрузчика."""
    conf = root / "iso/airootfs/etc/mkinitcpio.conf.d/archiso.conf"
    if not conf.exists():
        err("нет iso/airootfs/etc/mkinitcpio.conf.d/archiso.conf — initramfs не найдёт ISO")
        return
    text = read(conf)
    hooks = re.search(r"^HOOKS=\((.*)\)", text, re.MULTILINE)
    if not hooks:
        err("archiso.conf: не найдена строка HOOKS=(...)")
    else:
        names = hooks.group(1).split()
        for required_hook in ("archiso", "archiso_loop_mnt", "memdisk"):
            if required_hook not in names:
                err(f"archiso.conf: в HOOKS нет '{required_hook}' — загрузка уйдёт в emergency mode")

    # systemd-boot и syslinux не умеют рисовать кириллицу: в меню будут пустые места.
    boot_files = list((root / "iso/efiboot").rglob("*.conf")) + [root / "iso/syslinux/syslinux.cfg"]
    for path in boot_files:
        if not path.exists():
            continue
        for lineno, line in enumerate(read(path).splitlines(), 1):
            if line.lstrip().startswith("#"):
                continue  # комментарии загрузчик не отображает
            if any("а" <= ch.lower() <= "я" or ch.lower() == "ё" for ch in line):
                warn(
                    f"{path.relative_to(root)}:{lineno}: кириллица в меню загрузчика "
                    "(systemd-boot/syslinux её не отобразят)"
                )


def check_yaml_hygiene(root: Path) -> None:
    for path in root.rglob("*"):
        if path.suffix not in {".conf", ".desc", ".yaml", ".yml"} or "build" in path.parts:
            continue
        text = read(path)
        rel = path.relative_to(root)
        if "\t" in text:
            err(f"{rel}: символ табуляции в YAML (недопустим для отступов)")
        if text and not text.endswith("\n"):
            warn(f"{rel}: файл не заканчивается переводом строки")
        for lineno, line in enumerate(text.splitlines(), 1):
            if re.search(r":[ \t]+$", line):
                warn(f"{rel}:{lineno}: пробелы после ':' — YAML может прочитать как null")


def branding_images(root: Path) -> None:
    branding = root / "calamares/branding/vankos"
    desc = read(branding / "branding.desc")
    for match in re.finditer(
        r'^\s*(product(?:Icon|Logo|Wallpaper|Welcome|Banner)):\s*"([^"]+)"', desc, re.MULTILINE
    ):
        name = match.group(2)
        if not (branding / name).exists():
            err(f"branding.desc ссылается на отсутствующий образ: {name}")
    show = read(branding / "show.qml")
    for match in re.finditer(r'source:\s*"([^"]+)"', show):
        name = match.group(1)
        if not (branding / name).exists():
            err(f"show.qml ссылается на отсутствующий образ: {name}")
    for match in re.finditer(r'url\("?([^")]+)"?\)', read(root / "calamares/branding/vankos/stylesheet.qss")):
        url = match.group(1)
        if url.startswith(("http", "data:")):
            continue
        if not (branding / url).exists():
            warn(f"stylesheet.qss: не найден ресурс {url}")


def check_qml(root: Path) -> None:
    qml = root / "calamares/branding/vankos/show.qml"
    text = read(qml)
    if text.count("{") != text.count("}"):
        err("show.qml: несбалансированные фигурные скобки")
    if "import QtQuick" not in text:
        err("show.qml: нет импорта QtQuick")
    if "function onActivate" not in text:
        warn("show.qml: нет onActivate() — slideshowAPI 2 будет ругаться")


def check_package_lists(root: Path) -> None:
    lists = {
        "gnome": root / "iso/lists/gnome.txt",
        "delta": root / "iso/lists/delta.txt",
    }
    chooser = read(root / "calamares/modules/shellchooser.conf")
    ids = re.findall(r"^\s*-\s*id:\s*(\S+)\s*$", chooser, re.MULTILINE)
    if not ids:
        err("shellchooser.conf: не найдено ни одного id")
    for item_id in ids:
        if item_id not in lists:
            err(f"shellchooser.conf: id '{item_id}' не имеет списка пакетов iso/lists/{item_id}.txt")
        shot = re.search(
            rf"id:\s*{re.escape(item_id)}\b.*?screenshot:\s*\"([^\"]+)\"",
            chooser,
            re.DOTALL,
        )
        if not shot:
            warn(f"shellchooser.conf: у '{item_id}' нет screenshot")
        elif not (root / "calamares/branding/vankos" / shot.group(1)).exists():
            err(f"shellchooser.conf: нет картинки {shot.group(1)} в branding/vankos")
    for name, path in lists.items():
        entries = [ln for ln in read(path).splitlines() if ln.strip() and not ln.strip().startswith("#")]
        if not entries:
            err(f"{path.name}: пустой список пакетов")
        if name not in ids:
            warn(f"список {path.name} не используется ни одним пунктом установщика")
    live = {
        ln.strip()
        for ln in read(root / "iso/packages.x86_64").splitlines()
        if ln.strip() and not ln.strip().startswith("#")
    }
    # live-сессия — Delta через greetd, безопасный режим — Calamares в cage
    for pkg in ("delta", "greetd", "greetd-agreety", "cage", "qt6-wayland"):
        if pkg not in live:
            err(f"iso/packages.x86_64: нет {pkg} — live-сессия Delta или безопасный режим не запустятся")
    for pkg in ("gnome", "gdm"):
        if pkg in live:
            warn(f"{pkg} есть в live-образе: GNOME должен ставиться только установщиком")
    default = re.search(r"^default:\s*(\S+)", chooser, re.MULTILINE)
    if not default or default.group(1) != "delta":
        warn("shellchooser.conf: по умолчанию должен быть выбран delta")


def check_live_session(root: Path) -> None:
    """greetd в live: автовход vanks, безопасный режим из меню загрузки."""
    conf = read(root / "iso/airootfs/usr/share/vankos/greetd-live.toml")
    if "[initial_session]" not in conf or 'user = "vanks"' not in conf:
        err("greetd-live.toml: нет автовхода vanks ([initial_session])")
    if "vankos-live-session" not in conf:
        err("greetd-live.toml: сессии должен запускать vankos-live-session")
    setup = read(root / "iso/airootfs/usr/local/bin/vankos-live-setup")
    if "/etc/greetd/config.toml" not in setup:
        err("vankos-live-setup: не кладёт /etc/greetd/config.toml — greetd покажет свой конфиг")
    session = read(root / "iso/airootfs/usr/local/bin/vankos-live-session")
    if "vankos.safe=1" not in session:
        err("vankos-live-session: не проверяет vankos.safe=1")
    safe_boot = [
        p for p in [root / "iso/syslinux/syslinux.cfg", *(root / "iso/efiboot").rglob("*.conf")]
        if "vankos.safe=1" in read(p)
    ]
    if len(safe_boot) < 2:
        err("меню загрузки: пункт безопасного режима (vankos.safe=1) нужен и в syslinux, и в systemd-boot")
    if "greetd.service" not in read(root / "build.sh"):
        err("build.sh: greetd не включается в live-образе")
    prof = read(root / "iso/profiledef.sh")
    if "/usr/local/bin/vankos-live-session" not in prof:
        err("profiledef.sh: нет прав 0755 для vankos-live-session (mkarchiso сбросит их на 0644)")


def check_calamares_sequence(root: Path) -> None:
    settings = read(root / "calamares/settings.conf")
    modules_dir = root / "calamares/modules"

    instances = {}
    for block in re.finditer(
        r"-\s*id:\s*(\S+)\s*\n\s*module:\s*(\S+)\s*\n\s*config:\s*(\S+)", settings
    ):
        inst_id, module, config = block.groups()
        instances[inst_id] = module
        cfg = modules_dir / config
        if not cfg.exists():
            err(f"settings.conf: instance '{inst_id}' ссылается на отсутствующий {config}")

    used_in_sequence = set()
    for match in re.finditer(r"^\s*-\s*([A-Za-z0-9_@-]+)\s*$", settings, re.MULTILINE):
        token = match.group(1)
        if token in {"show", "exec"} or set(token) <= {"-"}:
            continue
        used_in_sequence.add(token)

    for token in sorted(used_in_sequence):
        if "@" in token:
            module, inst_id = token.split("@", 1)
            if inst_id not in instances:
                err(f"settings.conf: sequence использует '@{inst_id}', но instance не объявлен")
            elif instances[inst_id] != module:
                err(f"settings.conf: '@{inst_id}' объявлен как '{instances[inst_id]}', а не '{module}'")
        elif token not in instances and token not in BUILTIN_MODULES:
            warn(f"settings.conf: модуль '{token}' не объявлен в instances и не входит в известные")

    for inst_id, module in instances.items():
        if module == "shellprocess":
            stop = re.search(
                rf"id:\s*{re.escape(inst_id)}\b.*?config:\s*(\S+)", settings, re.DOTALL
            )
            if stop:
                conf = read(modules_dir / stop.group(1))
                for script in re.findall(r"/usr/local/(?:lib|bin)/vankos/[A-Za-z0-9_.-]+", conf):
                    target = root / "iso/airootfs" / script.lstrip("/")
                    if not target.exists():
                        err(f"модуль {stop.group(1)}: нет скрипта {script}")


def check_profiledef(root: Path) -> None:
    prof = read(root / "iso/profiledef.sh")
    # Эти пути создаются пакетами внутри образа, их нет в airootfs — проверяем мягко.
    managed_prefixes = ("/usr/local/", "/etc/vankos/", "/opt/")
    for match in re.finditer(r'\["([^"]+)"\]="', prof):
        rel = match.group(1)
        exists = (root / "iso/airootfs" / rel.lstrip("/")).exists()
        if not exists and rel.startswith(managed_prefixes):
            err(f"profiledef.sh: file_permissions ссылается на отсутствующий {rel}")
    for needed in ('iso_name="vankos"', "bootmodes=", 'airootfs_image_type="squashfs"'):
        if needed not in prof:
            warn(f"profiledef.sh: не найдено {needed}")

    # mkarchiso валидирует профиль: для каждого bootmode нужен свой пакет в списке.
    pkgs = {
        ln.strip()
        for ln in read(root / "iso/packages.x86_64").splitlines()
        if ln.strip() and not ln.strip().startswith("#")
    }
    if "bios.syslinux" in prof and "syslinux" not in pkgs:
        err("iso/packages.x86_64: для 'bios.syslinux' нужен пакет syslinux (иначе mkarchiso прервётся)")
    if "uefi.systemd-boot" in prof:
        for optional in ("memtest86+-efi", "edk2-shell", "memtest86+"):
            if optional not in pkgs:
                warn(f"iso/packages.x86_64: нет {optional} — mkarchiso выдаст INFO (не критично)")

    # Calamares нет в репозиториях Arch: он собирается из packaging/calamares.
    if "calamares" in pkgs:
        if not (root / "packaging/calamares/PKGBUILD").exists():
            err("в списке есть calamares, но нет packaging/calamares/PKGBUILD")
        if not (root / "tools/build-calamares.sh").is_file():
            err("нет tools/build-calamares.sh — Calamares не будет собран")
    else:
        warn("в iso/packages.x86_64 нет calamares — установщика в live-системе не будет")


def check_calamares_pkgbuild(root: Path) -> None:
    """Calamares линкуется с KF6Crash, если crash reporting не выключен.

    Такая ошибка не видна на сборочной машине (там kcrash может стоять
    случайно), но в live-образе установщик падает ещё до main():
    "error while loading shared libraries: libKF6Crash.so.6".
    """
    pkgbuild = root / "packaging/calamares/PKGBUILD"
    if not pkgbuild.exists():
        return
    text = read(pkgbuild)
    if "-DBUILD_CRASH_REPORTING=OFF" in text:
        return

    depends = re.search(r"^depends=\((.*?)^\)", text, re.MULTILINE | re.DOTALL)
    if not depends:
        warn("PKGBUILD Calamares: не найден блок depends=()")
        return
    names = set(re.findall(r"['\"]([^'\"]+)['\"]", depends.group(1)))
    if "kcrash" not in names:
        err(
            "PKGBUILD Calamares: BUILD_CRASH_REPORTING=ON, но в depends нет 'kcrash' — "
            "в live-образе calamares не запустится (libKF6Crash.so.6)"
        )


def check_json_and_shell(root: Path) -> None:
    defaults = root / "delta/defaults/settings.json"
    try:
        json.loads(read(defaults))
    except json.JSONDecodeError as exc:
        err(f"delta/defaults/settings.json: невалидный JSON ({exc})")

    bash = shutil.which("bash")
    scripts = list(root.rglob("*.sh")) + [
        root / "iso/airootfs/usr/local/bin/vankos-installer",
        root / "iso/airootfs/usr/local/bin/vankos-live-setup",
        root / "iso/airootfs/usr/local/bin/vankos-live-session",
    ]
    for script in scripts:
        if "build" in script.parts or not script.is_file():
            continue
        if "\r\n" in read(script):
            err(f"{script.relative_to(root)}: CRLF-переводы строк — bash не запустит файл")
        if not bash:
            continue
        result = subprocess.run([bash, "-n", str(script)], capture_output=True, text=True)
        if result.returncode != 0:
            err(f"{script.relative_to(root)}: синтаксическая ошибка bash: {result.stderr.strip()}")


def check_executable_bits(root: Path) -> None:
    # На Windows права не выставляются, но предупредить полезно.
    for rel in ("build.sh", "iso/profiledef.sh"):
        path = root / rel
        if path.exists():
            mode = path.stat().st_mode
            if not mode & 0o111:
                warn(f"{rel}: нет бита выполнения (chmod +x {rel})")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    root = Path(args.root).resolve()

    check_tree(root)
    check_boot_root(root)
    check_yaml_hygiene(root)
    branding_images(root)
    check_qml(root)
    check_package_lists(root)
    check_live_session(root)
    check_calamares_sequence(root)
    check_profiledef(root)
    check_calamares_pkgbuild(root)
    check_json_and_shell(root)
    check_executable_bits(root)

    print(f"Проверен проект: {root}")
    if WARNINGS:
        print(f"\nПредупреждения ({len(WARNINGS)}):")
        for item in WARNINGS:
            print(f"  ! {item}")
    if ERRORS:
        print(f"\nОшибки ({len(ERRORS)}):")
        for item in ERRORS:
            print(f"  x {item}")
        return 1

    print("\nОшибок не найдено.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
