"""Версии Vanks OS из релизов GitHub.

В релизе бывают:
  • пакет оболочки delta-<версия>-<сборка>-any.pkg.tar.zst (+ .sha256) —
    выбранная оболочка ставится поверх образа (в 0.1 пакета нет — только
    образ, оболочка в нём своя);
  • образ системы кусками <имя>.iso.part0, .part1, … (GitHub не берёт
    файлы больше 2 ГБ, куски по 1900 МиБ режет tools/iso-release.sh)
    и <имя>.iso.sha256 — сумма всего образа.

Образа может не быть (релиз только с новой оболочкой) — тогда берётся образ
из самого нового релиза, где он есть, а выбранная оболочка ставится поверх
(writer кладёт её в раздел VANKOS, установщик системы ставит её).

Список — из API GitHub. Без входа API даёт 60 запросов в час на адрес (на
весь дом или общий IP), поэтому, если он отказал, версии собираются со
страниц сайта, у которых такого лимита нет: лента releases.atom, файлы
релиза (expanded_assets) и размеры из заголовков ответов. И только если не
ответил и сайт — последний сохранённый список (fetch.source == "cache").

В списке — только большие версии (major): тег из двух чисел — v0.6, v0.7,
v1.0 (или v0.5.0) — и исключения из EXTRA. Промежуточные (0.5.1, 0.6.2)
приходят в систему обновлением Delta (delta-update), а в Vanks Setup их нет.
Показываются версии без «.0» и без номера сборки пакета: 0.5, а не 0.5.0-1.

Для проверок без сети: VANKS_SETUP_API — другой адрес API (свой сервер
с /repos/<репозиторий>/releases), VANKS_SETUP_WEB — другой адрес сайта,
VANKS_SETUP_REPO — другой репозиторий.
"""

import html
import json
import os
import re
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field

from . import VERSION

API = os.environ.get("VANKS_SETUP_API", "https://api.github.com").rstrip("/")
WEB = os.environ.get("VANKS_SETUP_WEB", "https://github.com").rstrip("/")
REPO = os.environ.get("VANKS_SETUP_REPO", "ArtyomVank/Vanks0s")
USER_AGENT = "vanks-setup/" + VERSION

SHELL_RE = re.compile(r"^delta-(\d[\w.]*)-(\d+)-any\.pkg\.tar\.zst$")
PART_RE = re.compile(r"^(.+\.iso)\.part(\d+)$")

# Большие версии сверх правила «два числа»: 0.5.6 — первая с играми Steam и
# Epic в лаунчере. 0.4 из списка убрана — её заменила 0.5.
EXTRA = {"0.5.6"}
HIDDEN = {"0.4"}


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
        """0.4 из тега v0.4.0, 0.5.6 из v0.5.6 (или из имени пакета)."""
        m = SHELL_RE.match(self.shell.name) if self.shell else None
        return short(self.tag) or (m.group(1) if m else "?")

    @property
    def major(self):
        v = self.version
        return v not in HIDDEN and (v in EXTRA or len(v.split(".")) <= 2)


def short(text):
    """Версия для людей: v0.5.0 → 0.5, 0.6 → 0.6, 0.5.6 → 0.5.6."""
    v = text.strip().lstrip("vV")
    while v.count(".") > 1 and v.endswith(".0"):
        v = v[:-2]
    return v


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


def _limit_message(e):
    reset = e.headers.get("X-RateLimit-Reset") if e.headers else None
    when = ""
    if reset and reset.isdigit():
        when = f" Попробуйте через {max(1, int((int(reset) - time.time()) // 60) + 1)} мин."
    return "GitHub временно ограничил запросы (60 в час без входа)." + when


def from_web(timeout=20):
    """Релизы со страниц сайта — в том же виде, что ответ API. Черновиков в
    ленте нет; пометки «предварительный» тоже (её рисует скрипт страницы),
    так что здесь все релизы — обычные."""
    ns = {"a": "http://www.w3.org/2005/Atom"}

    def get(url, method="GET"):
        return urllib.request.urlopen(urllib.request.Request(url, method=method, headers={"User-Agent": USER_AGENT}),
                                      timeout=timeout)

    with get(f"{WEB}/{REPO}/releases.atom") as resp:
        feed = ET.fromstring(resp.read())
    entries = []
    for e in feed.findall("a:entry", ns):
        link = e.find("a:link", ns)
        tag = urllib.parse.unquote((link.get("href") if link is not None else "").rsplit("/tag/", 1)[-1])
        if not tag:
            continue
        body = re.sub(r"<[^>]+>", "", html.unescape(e.findtext("a:content", "", ns)))
        entries.append({"tag_name": tag, "name": e.findtext("a:title", tag, ns), "draft": False, "prerelease": False,
                        "published_at": e.findtext("a:updated", "", ns), "body": body.strip(), "assets": []})

    def assets(rel):
        tag = urllib.parse.quote(rel["tag_name"])
        with get(f"{WEB}/{REPO}/releases/expanded_assets/{tag}") as resp:
            page = resp.read().decode("utf-8", "replace")
        names = dict.fromkeys(urllib.parse.unquote(m) for m in
                              re.findall(rf'href="/{re.escape(REPO)}/releases/download/{re.escape(tag)}/([^"?#]+)"', page))
        rel["assets"] = [{"name": n, "size": 0, "browser_download_url": f"{WEB}/{REPO}/releases/download/{tag}/"
                          + urllib.parse.quote(n)} for n in names]

    def size(a):
        # размер нужен куску образа (хватит ли флешки, ход загрузки) и пакету
        if SHELL_RE.match(a["name"]) or PART_RE.match(a["name"]) or a["name"].endswith(".iso"):
            with get(a["browser_download_url"], "HEAD") as resp:
                a["size"] = int(resp.headers.get("Content-Length") or 0)

    with ThreadPoolExecutor(8) as pool:
        list(pool.map(assets, entries))
        list(pool.map(size, [a for r in entries for a in r["assets"]]))
    return entries


def fetch(timeout=20):
    """Все релизы репозитория (новые первыми): API, иначе страницы сайта,
    иначе последний сохранённый список. Откуда он — в fetch.source
    ("api", "web", "cache"), когда сохранён — в fetch.saved_at."""
    from .download import cache_dir
    url = f"{API}/repos/{REPO}/releases?per_page=100"
    saved = os.path.join(cache_dir(), "releases-" + REPO.replace("/", "_") + ".json")
    errors = []
    for source in ("api", "web"):
        try:
            if source == "api":
                with urllib.request.urlopen(request(url), timeout=timeout) as resp:
                    data = json.load(resp)
            else:
                data = from_web(timeout)
                if not data:
                    raise ValueError("в ленте релизов пусто")
        except Exception as e:
            errors.append(e)
            continue
        with open(saved, "w", encoding="utf-8") as f:
            json.dump(data, f)
        fetch.source, fetch.saved_at = source, time.time()
        return parse(data)
    if os.path.exists(saved):
        with open(saved, encoding="utf-8") as f:
            data = json.load(f)
        fetch.source, fetch.saved_at = "cache", os.path.getmtime(saved)
        return parse(data)
    e = errors[0]
    if isinstance(e, urllib.error.HTTPError) and e.code in (403, 429):
        raise LimitError(_limit_message(e)) from e
    raise e


fetch.source, fetch.saved_at = "", 0.0


def stale_note():
    """Пояснение, если показан сохранённый список (иначе пусто)."""
    if fetch.source != "cache":
        return ""
    return time.strftime("Список версий сохранён %d.%m в %H:%M — GitHub сейчас не отвечает, новых версий может не быть.",
                         time.localtime(fetch.saved_at))


def shell_versions(releases, prereleases=False):
    """Версии для выбора — большие релизы с оболочкой или своим образом;
    первая — самая новая. Тег встречается дважды (черновик пропущен, но
    бывает повтор) — берём первый."""
    out, seen = [], set()
    for r in releases:
        if (r.shell or r.image) and r.major and (prereleases or not r.prerelease) and r.version not in seen:
            seen.add(r.version)
            out.append(r)
    return out


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
