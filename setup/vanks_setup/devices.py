"""Куда можно записать образ: флешки и (если разрешено) другие диски.

Диск с работающей системой не показывается никогда: на Linux — тот, где
смонтированы /, /boot, /home или подкачка; на Windows — системный и
загрузочный (IsSystem, IsBoot). Внутренние диски — только с allow_internal
(«Настройки → Разрешить запись на диски»).
"""

import json
import os
import subprocess
import sys
from dataclasses import dataclass, field

from .releases import human

SYSTEM_MOUNTS = {"/", "/boot", "/boot/efi", "/efi", "/usr", "/var", "/home", "[SWAP]"}


@dataclass
class Disk:
    path: str              # /dev/sdb или \\.\PhysicalDrive2
    size: int
    name: str              # «SanDisk Ultra»
    removable: bool
    mounts: list = field(default_factory=list)
    number: int = -1       # номер диска Windows

    @property
    def label(self):
        kind = "флешка" if self.removable else "диск"
        return f"{self.name or kind} — {human(self.size)} ({self.path})"


def _run(cmd, timeout=15):
    flags = 0x08000000 if sys.platform == "win32" else 0   # CREATE_NO_WINDOW
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, creationflags=flags)


def _linux(allow_internal):
    out = _run(["lsblk", "-J", "-b", "-o", "NAME,PATH,SIZE,MODEL,VENDOR,TRAN,RM,HOTPLUG,TYPE,MOUNTPOINTS,RO"])
    if out.returncode != 0:
        raise RuntimeError("lsblk: " + out.stderr.strip())
    disks = []
    for d in json.loads(out.stdout).get("blockdevices", []):
        if d.get("type") != "disk" or d.get("ro") or not int(d.get("size") or 0):
            continue
        mounts = []

        def walk(node):
            mounts.extend(m for m in (node.get("mountpoints") or []) if m)
            for c in node.get("children") or []:
                walk(c)
        walk(d)
        if any(m in SYSTEM_MOUNTS for m in mounts):
            continue
        # zram и loop — не диски
        if d.get("name", "").startswith(("zram", "loop", "sr")):
            continue
        removable = bool(d.get("rm")) or bool(d.get("hotplug")) or d.get("tran") in ("usb", "mmc")
        if not removable and not allow_internal:
            continue
        name = " ".join(x.strip() for x in (d.get("vendor") or "", d.get("model") or "") if x and x.strip())
        disks.append(Disk(d["path"], int(d["size"]), name, removable, mounts))
    return disks


def _windows(allow_internal):
    ps = ("Get-Disk | Select-Object Number,FriendlyName,Size,BusType,IsSystem,IsBoot,IsReadOnly,IsOffline "
          "| ConvertTo-Json -Compress")
    out = _run(["powershell", "-NoProfile", "-NonInteractive", "-Command", ps], timeout=30)
    if out.returncode != 0:
        raise RuntimeError("Get-Disk: " + out.stderr.strip())
    data = json.loads(out.stdout or "[]")
    if isinstance(data, dict):
        data = [data]
    disks = []
    for d in data:
        if d.get("IsSystem") or d.get("IsBoot") or d.get("IsReadOnly") or not d.get("Size"):
            continue
        bus = str(d.get("BusType", ""))
        # BusType бывает числом (7 — USB, 12 — SD, 13 — MMC) или строкой
        removable = bus in ("USB", "SD", "MMC", "7", "12", "13")
        if not removable and not allow_internal:
            continue
        n = int(d["Number"])
        disks.append(Disk(rf"\\.\PhysicalDrive{n}", int(d["Size"]), (d.get("FriendlyName") or "").strip(), removable, [], n))
    return disks


def list_disks(allow_internal=False):
    # проверки: «флешка» — обычный файл (VANKS_SETUP_TEST_DEVICE=1, writer.TEST)
    test = os.environ.get("VANKS_SETUP_TEST_DISK")
    if test and os.environ.get("VANKS_SETUP_TEST_DEVICE") == "1":
        return [Disk(test, int(os.environ.get("VANKS_SETUP_TEST_SIZE", 256 << 20)), "Тестовая флешка", True)]
    return _windows(allow_internal) if sys.platform == "win32" else _linux(allow_internal)
