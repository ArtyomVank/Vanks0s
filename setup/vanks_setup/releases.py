"""Версии Vanks OS из релизов GitHub.

В релизе бывают:
  • пакет оболочки delta-<версия>-<сборка>-any.pkg.tar.zst (+ .sha256) —
    он есть в каждом релизе, это и есть «версия» в списке;
  • образ системы кусками <имя>.iso.part0, .part1, … (GitHub не берёт
    файлы больше 2 ГБ, куски по 1900 МиБ режет tools/iso-release.sh)
    и <имя>.iso.sha256 — сумма всего образа.

Образа может не быть (релиз только с новой оболочкой) — тогда берётся образ
из самого нового релиза, где он есть, а выбранная оболочка ставится поверх
(writer кладёт её в раздел VANKOS, установщик системы ставит её).

Для проверок без сети: VANKS_SETUP_API — другой адрес API (свой сервер
с /repos/<репозиторий>/releases), VANKS_SETUP_REPO — другой репозиторий.
"""

import json
import os
import re
import urllib.error
import urllib.request
from dataclasses import dataclass, field

from . import VERSION

API = os.environ.get("VANKS_SETUP_API", "https://api.github.com").rstrip("/")
REPO = os.environ.get("VANKS_SETUP_REPO", "ArtyomVank/Vanks0s")
USER_AGENT = "vanks-setup/" + VERSION

SHELL_RE = re.compile(r"^delta-(\d[\w.]*)-(\d+)-any\.pkg\.tar\.zst$")
PART_RE = re.compile(r"^(.+\.iso)\.part(\d+)$")


@dataclass
class Asset:
    name: str
    size: int
    url: str


@dataclass
class Image:
    """Образ системы: куски по порядку и файл с суммой всего образа."""
    name: str
    parts: list
    sha256: Asset | None
    tag: str

    @property
    def size(self):
        return sum(p.size for p in self.parts)


@dataclass
class Release:
    tag: str
    title: str
    date: str
    prerelease: bool
    shell: Asset | None = None
    shell_sha: Asset | None = None
    image: Image | None = None
    notes: str = ""
    key: tuple = field(default_factory=tuple)

    @property
    def version(self):
        """0.4.0 из тега v0.4.0 (или из имени пакета)."""
        m = SHELL_RE.match(self.shell.name) if self.shell else None
        return self.tag.lstrip("vV") or (m.group(1) if m else "?")


def version_key(text):
    """Ключ сортировки версий: 0.10.0 новее 0.9.2."""
    return tuple(int(x) if x.isdigit() else 0 for x in re.split(r"[.\-]", text.lstrip("vV")))


def request(url, accept="application/vnd.github+json"):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": accept})
    token = os.environ.get("GITHUB_TOKEN")
    if token and url.startswith(API):
        req.add_header("Authorization", "Bearer " + token)
    return req


def parse(data):
    """Релизы из ответа API → [Release], черновики пропускаем."""
    out = []
    for r in data:
        if r.get("draft"):
            continue
        rel = Release(tag=r.get("tag_name", ""), title=r.get("name") or r.get("tag_name", ""),
                      date=(r.get("published_at") or "")[:10], prerelease=bool(r.get("prerelease")),
                      notes=r.get("body") or "")
        assets = {a["name"]: Asset(a["name"], int(a.get("size", 0)), a["browser_download_url"]) for a in r.get("assets", [])}
        parts = {}
        for name, a in assets.items():
            if SHELL_RE.match(name):
                rel.shell = a
                rel.shell_sha = assets.get(name + ".sha256")
            m = PART_RE.match(name)
            if m:
                parts.setdefault(m.group(1), []).append((int(m.group(2)), a))
            elif name.endswith(".iso") and assets.get(name + ".sha256"):
                parts.setdefault(name, []).append((0, a))
        # несколько образов в релизе — берём тот, у которого есть сумма, иначе первый
        for iso in sorted(parts, key=lambda n: (n + ".sha256") not in assets):
            seq = [a for _, a in sorted(parts[iso])]
            rel.image = Image(name=iso, parts=seq, sha256=assets.get(iso + ".sha256"), tag=rel.tag)
            break
        rel.key = version_key(rel.tag)
        out.append(rel)
    out.sort(key=lambda r: r.key, reverse=True)
    return out


class LimitError(Exception):
    pass


def fetch(timeout=20):
    """Все релизы репозитория (новые первыми). Ответ сохраняется в кэш: если
    GitHub недоступен или исчерпан лимит (60 запросов в час без входа), берём
    последний сохранённый список."""
    from .download import cache_dir
    url = f"{API}/repos/{REPO}/releases?per_page=100"
    saved = os.path.join(cache_dir(), "releases-" + REPO.replace("/", "_") + ".json")
    try:
        with urllib.request.urlopen(request(url), timeout=timeout) as resp:
            data = json.load(resp)
        with open(saved, "w", encoding="utf-8") as f:
            json.dump(data, f)
        return parse(data)
    except Exception as e:
        if os.path.exists(saved):
            with open(saved, encoding="utf-8") as f:
                return parse(json.load(f))
        if isinstance(e, urllib.error.HTTPError) and e.code in (403, 429):
            reset = e.headers.get("X-RateLimit-Reset") if e.headers else None
            when = ""
            if reset and reset.isdigit():
                import time
                when = f" Попробуйте через {max(1, int((int(reset) - time.time()) // 60) + 1)} мин."
            raise LimitError("GitHub временно ограничил запросы (60 в час без входа)." + when) from e
        raise


def shell_versions(releases, prereleases=False):
    """Версии для выбора — релизы с пакетом оболочки; первая — самая новая."""
    return [r for r in releases if r.shell and (prereleases or not r.prerelease)]


def image_for(releases, chosen):
    """Образ для выбранной версии: свой, иначе самый новый из релизов с образом."""
    if chosen.image:
        return chosen.image
    for r in releases:
        if r.image and not r.prerelease:
            return r.image
    for r in releases:
        if r.image:
            return r.image
    return None


def human(size):
    """1,9 ГБ — размер для людей."""
    for unit, k in (("ГБ", 1 << 30), ("МБ", 1 << 20), ("КБ", 1 << 10)):
        if size >= k:
            return f"{size / k:.1f}".replace(".", ",") + " " + unit
    return f"{size} Б"
