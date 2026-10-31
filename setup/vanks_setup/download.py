"""Загрузка с докачкой и проверкой.

Куски образа и пакет оболочки ложатся в папку кэша (cache_dir()). Оборвалась
связь или закрыли программу — при следующем запуске недокачанный файл
продолжается с того же места (HTTP Range). Готовый образ проверяется по
sha256 из релиза; проверенный помечается файлом <имя>.ok — второй раз не
пересчитываем.

progress(stage, done, total) — «download» и «verify», байты.
cancel — threading.Event: выставили — загрузка прерывается (Cancelled).
"""

import hashlib
import os
import re
import sys
import time
import urllib.error
import urllib.request

from .releases import request

CHUNK = 1 << 20


class Cancelled(Exception):
    pass


class DownloadError(Exception):
    pass


def cache_dir():
    """~/.cache/vanks-setup или %LOCALAPPDATA%\\VanksSetup."""
    if sys.platform == "win32":
        base = os.environ.get("LOCALAPPDATA") or os.path.expanduser("~")
        path = os.path.join(base, "VanksSetup")
    else:
        base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
        path = os.path.join(base, "vanks-setup")
    os.makedirs(path, exist_ok=True)
    return path


def fetch_text(asset, timeout=30):
    with urllib.request.urlopen(request(asset.url, "application/octet-stream"), timeout=timeout) as resp:
        return resp.read().decode("utf-8", "replace")


def expected_sha(asset):
    """Первое слово файла .sha256 («<сумма>  <имя>»)."""
    if not asset:
        return None
    words = fetch_text(asset).split()
    return words[0].lower() if words and len(words[0]) == 64 else None


def fetch(asset, dest, progress=None, cancel=None, base=0, total=None, retries=5):
    """Скачать asset в dest с докачкой. base/total — для общего прогресса
    нескольких файлов (сколько уже скачано до этого и сколько всего)."""
    total = total or asset.size
    if os.path.exists(dest) and os.path.getsize(dest) == asset.size:
        if progress:
            progress("download", base + asset.size, total)
        return dest
    tmp = dest + ".dl"
    attempt = 0
    while True:
        have = os.path.getsize(tmp) if os.path.exists(tmp) else 0
        if have > asset.size:
            os.remove(tmp)
            have = 0
        if have == asset.size:
            break
        req = request(asset.url, "application/octet-stream")
        if have:
            req.add_header("Range", f"bytes={have}-")
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                # сервер не умеет докачку — начинаем файл заново
                if have and resp.status != 206:
                    have = 0
                with open(tmp, "ab" if have else "wb") as f:
                    while True:
                        if cancel is not None and cancel.is_set():
                            raise Cancelled()
                        buf = resp.read(CHUNK)
                        if not buf:
                            break
                        f.write(buf)
                        have += len(buf)
                        if progress:
                            progress("download", base + have, total)
            attempt = 0
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError) as e:
            if isinstance(e, urllib.error.HTTPError) and e.code == 416:
                os.remove(tmp)
                continue
            # файла нет или нет доступа — повторять бесполезно
            if isinstance(e, urllib.error.HTTPError) and 400 <= e.code < 500 and e.code != 429:
                raise DownloadError(f"не удалось скачать {asset.name}: {e}") from e
            attempt += 1
            if attempt > retries:
                raise DownloadError(f"не удалось скачать {asset.name}: {e}") from e
            time.sleep(min(30, 2 ** attempt))
            continue
        if have >= asset.size:
            break
    if os.path.getsize(tmp) != asset.size:
        raise DownloadError(f"{asset.name}: размер не совпал")
    os.replace(tmp, dest)
    return dest


def sha256_files(paths, progress=None, cancel=None, total=None):
    h = hashlib.sha256()
    done = 0
    total = total or sum(os.path.getsize(p) for p in paths)
    for p in paths:
        with open(p, "rb") as f:
            while True:
                if cancel is not None and cancel.is_set():
                    raise Cancelled()
                buf = f.read(4 * CHUNK)
                if not buf:
                    break
                h.update(buf)
                done += len(buf)
                if progress:
                    progress("verify", done, total)
    return h.hexdigest()


def get_image(image, progress=None, cancel=None, folder=None):
    """Скачать и проверить образ; вернуть пути кусков по порядку. В кэше —
    своя папка на релиз: у 0.1 и 0.3 образы с одним именем, но разные."""
    if not folder:
        folder = os.path.join(cache_dir(), re.sub(r"[^\w.-]", "_", image.tag or "image"))
        os.makedirs(folder, exist_ok=True)
    paths = [os.path.join(folder, p.name) for p in image.parts]
    ok = os.path.join(folder, image.name + ".ok")
    want = expected_sha(image.sha256)
    done = 0
    for asset, path in zip(image.parts, paths):
        fetch(asset, path, progress, cancel, base=done, total=image.size)
        done += asset.size
    if want and os.path.exists(ok):
        with open(ok) as f:
            if f.read().strip() == want:
                return paths
    if want:
        got = sha256_files(paths, progress, cancel, image.size)
        if got != want:
            # испорченный кусок не угадать — удаляем все, в следующий раз скачаются заново
            for p in paths:
                os.remove(p)
            raise DownloadError("образ скачался с ошибкой (не совпала sha256) — попробуйте ещё раз")
        with open(ok, "w") as f:
            f.write(want)
    return paths


def get_shell(release, cancel=None, folder=None):
    """Скачать и проверить пакет оболочки выбранной версии."""
    folder = folder or cache_dir()
    path = os.path.join(folder, release.shell.name)
    fetch(release.shell, path, cancel=cancel)
    want = expected_sha(release.shell_sha)
    if want and sha256_files([path]) != want:
        os.remove(path)
        raise DownloadError(f"{release.shell.name} скачался с ошибкой — попробуйте ещё раз")
    return path
