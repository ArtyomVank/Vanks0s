"""Запись образа: в папку, на флешку или диск.

На флешку/диск образ пишется как есть (как dd или Rufus в режиме «DD»).
Первый мегабайт — таблица разделов — пишется последним: пока её нет, система
не находит на флешке разделов и не монтирует их посреди записи. Потом всё
записанное читается обратно и сверяется по sha256.

Если на флешке осталось место, после образа создаётся маленький раздел
VANKOS (FAT, 64 МиБ) с выбранной версией оболочки:
    /vankos/delta-<версия>-1-any.pkg.tar.zst
    /vankos/choice.json   { "shell": "0.4.0", "package": …, "image": … }
Установщик системы (iso/…/desktop.sh) ставит оболочку оттуда.

Запись на устройство требует прав администратора. На Linux её делает
отдельный процесс (sudo в терминале, pkexec из окна) — run_elevated();
на Windows программа сама запускается от администратора (манифест .exe).

progress(stage, done, total): «write», «check», «extra».
"""

import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

from . import VERSION
from .download import Cancelled

BLOCK = 4 << 20
HEAD = 1 << 20
SECTOR = 512
DATA_SIZE = 64 << 20
DATA_LABEL = "VANKOS"
# только для проверок: «устройство» — обычный файл, без прав и размонтирования
TEST = os.environ.get("VANKS_SETUP_TEST_DEVICE") == "1"


class WriteError(Exception):
    pass


def _check(cancel):
    if cancel is not None and cancel.is_set():
        raise Cancelled()


def blocks(paths, size=BLOCK):
    """Куски образа подряд — блоками ровно по size байт (последний короче)."""
    buf = bytearray()
    for p in paths:
        with open(p, "rb") as f:
            while True:
                data = f.read(size - len(buf))
                if not data:
                    break
                buf += data
                if len(buf) == size:
                    yield bytes(buf)
                    buf.clear()
    if buf:
        yield bytes(buf)


def choice_json(release, image):
    return json.dumps({"shell": release.version, "package": release.shell.name if release.shell else None,
                       "image": image.name, "tag": release.tag, "setup": VERSION}, ensure_ascii=False, indent=2)


# ---------- в папку ----------

def to_folder(paths, image, folder, shell_path=None, choice=None, progress=None, cancel=None):
    """Собрать образ из кусков в папку; рядом — пакет оболочки и choice.json."""
    os.makedirs(folder, exist_ok=True)
    iso = os.path.join(folder, image.name)
    total = image.size
    if shutil.disk_usage(folder).free < total - (os.path.getsize(iso) if os.path.exists(iso) else 0):
        raise WriteError("в папке не хватает места: нужно " + str(total >> 20) + " МБ")
    tmp = iso + ".part"
    done = 0
    with open(tmp, "wb") as out:
        for b in blocks(paths):
            _check(cancel)
            out.write(b)
            done += len(b)
            if progress:
                progress("write", done, total)
    os.replace(tmp, iso)
    if shell_path:
        extra = os.path.join(folder, "vankos")
        os.makedirs(extra, exist_ok=True)
        shutil.copy2(shell_path, extra)
        if choice:
            with open(os.path.join(extra, "choice.json"), "w", encoding="utf-8") as f:
                f.write(choice)
    return iso


# ---------- на устройство ----------

def _run(cmd, inp=None, check=True, env=None):
    flags = 0x08000000 if sys.platform == "win32" else 0
    r = subprocess.run(cmd, input=inp, capture_output=True, text=True, env=env, creationflags=flags)
    if check and r.returncode != 0:
        raise WriteError(f"{cmd[0]}: {(r.stderr or r.stdout).strip()}")
    return r


def _unmount_linux(dev):
    """Размонтировать все разделы флешки (udisksctl, если umount не дал)."""
    r = _run(["lsblk", "-J", "-o", "PATH,MOUNTPOINTS", dev], check=False)
    if r.returncode != 0:
        return
    nodes = []

    def walk(n):
        nodes.append(n)
        for c in n.get("children") or []:
            walk(c)
    for n in json.loads(r.stdout).get("blockdevices", []):
        walk(n)
    for n in nodes:
        for m in n.get("mountpoints") or []:
            if not m:
                continue
            if m == "[SWAP]":
                _run(["swapoff", n["path"]], check=False)
            elif _run(["umount", n["path"]], check=False).returncode != 0:
                _run(["udisksctl", "unmount", "-b", n["path"]], check=False)


def _diskpart(script):
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
        f.write(script)
        name = f.name
    try:
        return _run(["diskpart", "/s", name])
    finally:
        os.remove(name)


def _free_letter():
    for c in "ZYXWVUTSRQPONMLKJIHGFED":
        if not os.path.exists(c + ":\\"):
            return c
    raise WriteError("нет свободной буквы диска для раздела VANKOS")


def write_device(paths, total, sha, disk, progress=None, cancel=None):
    """Записать образ на устройство и проверить. sha — ожидаемая сумма образа."""
    path = disk["path"]
    if sys.platform == "win32" and not TEST:
        _diskpart(f"select disk {disk['number']}\nattributes disk clear readonly\nonline disk noerr\nclean\nrescan\n")
    elif not TEST:
        _unmount_linux(path)
    if disk["size"] < total:
        raise WriteError("образ не помещается на устройство")

    mode = "r+b" if (os.path.exists(path) or not TEST) else "w+b"
    head = b""
    with open(path, mode, buffering=0) as dev:
        done = 0
        for b in blocks(paths):
            _check(cancel)
            if done < HEAD:
                # первый мегабайт — в конце
                head += b[:HEAD - done]
                rest = b[HEAD - done:]
                if rest:
                    dev.seek(HEAD)
                    dev.write(_pad(rest))
            else:
                dev.seek(done)
                dev.write(_pad(b))
            done += len(b)
            if progress:
                progress("write", done, total)
        dev.seek(0)
        dev.write(_pad(head))
        if hasattr(os, "fsync"):
            os.fsync(dev.fileno())
        if hasattr(os, "posix_fadvise"):
            os.posix_fadvise(dev.fileno(), 0, 0, os.POSIX_FADV_DONTNEED)

    if sha:
        h = hashlib.sha256()
        done = 0
        with open(path, "rb", buffering=0) as dev:
            while done < total:
                _check(cancel)
                b = dev.read(BLOCK)
                if not b:
                    break
                b = b[:total - done]
                h.update(b)
                done += len(b)
                if progress:
                    progress("check", done, total)
        if h.hexdigest() != sha:
            raise WriteError("записанное не совпало с образом — флешка может быть неисправна")


def _pad(b):
    """Устройства Windows принимают только целые секторы."""
    r = len(b) % SECTOR
    return b + bytes(SECTOR - r) if r else b


def add_data_partition(disk, total, files, progress=None):
    """Раздел VANKOS после образа; files — {имя в /vankos: путь}. False — нет места."""
    start = -(-total // SECTOR)
    start = -(-start // 2048) * 2048
    count = DATA_SIZE // SECTOR
    if disk["size"] < (start + count) * SECTOR:
        return False
    path = disk["path"]
    if progress:
        progress("extra", 0, 1)
    if sys.platform == "win32" and not TEST:
        letter = _free_letter()
        _diskpart(f"rescan\nselect disk {disk['number']}\ncreate partition primary size={DATA_SIZE >> 20}\n"
                  f"format fs=fat quick label={DATA_LABEL}\nassign letter={letter}\n")
        target = letter + ":\\vankos"
        os.makedirs(target, exist_ok=True)
        for name, src in files.items():
            shutil.copyfile(src, os.path.join(target, name))
    else:
        # без sfdisk, mkfs.fat и mtools раздел не сделать — флешка всё равно загрузится
        if any(shutil.which(t) is None for t in ("sfdisk", "mkfs.fat", "mmd", "mcopy")):
            return False
        if TEST and os.path.getsize(path) < (start + count) * SECTOR:
            with open(path, "r+b") as f:
                f.truncate((start + count) * SECTOR)
        _run(["sfdisk", "--append", "--no-reread", "--no-tell-kernel", "--wipe", "never",
              "--wipe-partitions", "never", path], inp=f"start={start}, size={count}, type=e\n")
        _run(["mkfs.fat", "-F", "16", "-n", DATA_LABEL, "-h", str(start), "--offset", str(start),
              path, str(DATA_SIZE // 1024)])
        img = f"{path}@@{start * SECTOR}"
        env = dict(os.environ, MTOOLS_SKIP_CHECK="1")
        _run(["mmd", "-i", img, "::/vankos"], env=env)
        for name, src in files.items():
            _run(["mcopy", "-o", "-i", img, src, "::/vankos/" + name], env=env)
        if not TEST:
            # ядру — новая таблица разделов (не вышло — увидит при следующем подключении)
            _run(["partprobe", path], check=False)
    if progress:
        progress("extra", 1, 1)
    return True


def job_device(job, progress=None, cancel=None):
    """Вся запись на устройство по описанию задания (его же получает helper)."""
    disk = job["disk"]
    write_device(job["parts"], job["total"], job.get("sha"), disk, progress, cancel)
    files = {}
    if job.get("shell"):
        files[os.path.basename(job["shell"])] = job["shell"]
    if job.get("choice"):
        fd, cj = tempfile.mkstemp(suffix=".json")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            f.write(job["choice"])
        files["choice.json"] = cj
    try:
        return add_data_partition(disk, job["total"], files, progress) if files else True
    finally:
        if "choice.json" in files:
            os.remove(files["choice.json"])


# ---------- права администратора (Linux) ----------

def need_elevation():
    return sys.platform != "win32" and not TEST and os.geteuid() != 0


def helper_command():
    """Команда, запускающая эту же программу в режиме helper."""
    if getattr(sys, "frozen", False):
        return [sys.executable, "--write-helper"]
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    return [sys.executable, "-c", f"import sys; sys.path.insert(0, {root!r}); from vanks_setup.cli import helper; helper()"]


def run_elevated(job, progress=None, cancel=None, via="sudo"):
    """Запись от root отдельным процессом; прогресс — по его строкам «P стадия сделано всего»."""
    fd, jpath = tempfile.mkstemp(prefix="vanks-job-", suffix=".json")
    with os.fdopen(fd, "w", encoding="utf-8") as f:
        json.dump(job, f)
    cmd = ([via] if via else []) + helper_command() + [jpath]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, text=True, bufsize=1)
    result, error = None, None
    try:
        for line in proc.stdout:
            if cancel is not None and cancel.is_set():
                proc.terminate()
                raise Cancelled()
            kind, _, rest = line.strip().partition(" ")
            if kind == "P" and progress:
                stage, done, total = rest.split()
                progress(stage, int(done), int(total))
            elif kind == "E":
                error = rest
            elif kind == "D":
                result = rest == "1"
        proc.wait()
    finally:
        os.remove(jpath)
    if error:
        raise WriteError(error)
    if proc.returncode != 0 or result is None:
        raise WriteError("запись прервана (нет прав администратора?)")
    return result
