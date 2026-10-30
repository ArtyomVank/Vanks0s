"""Окно Vanks Setup: PySide6 + QML (Main.qml) поверх того же ядра, что
и терминал. Backend — мост: свойства для QML, а загрузка и запись идут в
отдельном потоке и присылают ход сигналами (в поток окна — очередью).

QML читается через importlib.resources: программа работает и из .pyz
(zip), и из PyInstaller.
"""

import os
import sys
import threading
from importlib import resources

from PySide6.QtCore import QObject, Property, QUrl, Signal, Slot, QSettings
from PySide6.QtGui import QGuiApplication, QIcon
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtWidgets import QApplication, QFileDialog

from .. import VERSION, releases, download, devices, writer
from ..releases import human


class Backend(QObject):
    changed = Signal()
    progressChanged = Signal()
    _post = Signal(object)          # функция из рабочего потока → выполнить в потоке окна

    def __init__(self):
        super().__init__()
        self._post.connect(lambda fn: fn())
        self.store = QSettings("Vanks", "Setup")
        self._rels = []
        self._versions = []
        self._index = 0
        self._disks = []
        self._state = "loading"       # loading · ready · error · busy · done · failed
        self._error = ""
        self._stage = ""
        self._done = 0.0
        self._total = 0.0
        self._speed = 0.0
        self._result = ""
        self._cancel = threading.Event()
        self._t0 = (0.0, 0.0, "")

    # ---------- свойства ----------
    def _get(name):
        return lambda self: getattr(self, "_" + name)

    state = Property(str, _get("state"), notify=changed)
    error = Property(str, _get("error"), notify=changed)
    result = Property(str, _get("result"), notify=changed)
    stage = Property(str, _get("stage"), notify=progressChanged)
    done = Property(float, _get("done"), notify=progressChanged)
    total = Property(float, _get("total"), notify=progressChanged)
    speed = Property(float, _get("speed"), notify=progressChanged)
    index = Property(int, _get("index"), notify=changed)

    @Property(str, constant=True)
    def appVersion(self):
        return VERSION

    @Property("QVariantList", notify=changed)
    def versions(self):
        out = []
        for i, r in enumerate(self._versions):
            img = releases.image_for(self._rels, r)
            out.append({"version": r.version, "title": r.title, "date": r.date, "latest": i == 0,
                        "pre": r.prerelease, "notes": (r.notes or "").strip()[:400],
                        "image": img.name if img else "", "imageTag": img.tag if img else "",
                        "imageSize": human(img.size) if img else "", "own": bool(r.image)})
        return out

    @Property("QVariantList", notify=changed)
    def disks(self):
        return [{"path": d.path, "name": d.name or ("Флешка" if d.removable else "Диск"), "size": human(d.size),
                 "removable": d.removable, "fits": self._image() is not None and d.size >= self._image().size}
                for d in self._disks]

    def _flag(key):
        def get(self):
            return self.store.value(key, False, type=bool)

        def put(self, v):
            self.store.setValue(key, bool(v))
            self.changed.emit()
            if key == "prerelease":
                self._apply()
        return get, put

    allowDisks = Property(bool, *_flag("allowDisks"), notify=changed)
    prerelease = Property(bool, *_flag("prerelease"), notify=changed)

    @Property(str, notify=changed)
    def downloads(self):
        for name in ("Загрузки", "Downloads"):
            p = os.path.join(os.path.expanduser("~"), name)
            if os.path.isdir(p):
                return p
        return os.path.expanduser("~")

    @Property(str, notify=changed)
    def cachePath(self):
        return download.cache_dir()

    # ---------- версии ----------
    def _image(self):
        return releases.image_for(self._rels, self._versions[self._index]) if self._versions else None

    def _apply(self):
        self._versions = releases.shell_versions(self._rels, self.prerelease)
        self._index = 0
        self._state = "ready" if self._versions else "error"
        if not self._versions:
            self._error = "В релизах нет ни одной версии"
        self.changed.emit()

    @Slot()
    def load(self):
        self._state, self._error = "loading", ""
        self.changed.emit()

        def work():
            try:
                rels = releases.fetch()

                def ok():
                    self._rels = rels
                    self._apply()
                self._post.emit(ok)
            except Exception as e:
                msg = str(e)

                def bad():
                    self._state, self._error = "error", "Не удалось получить версии с GitHub: " + msg
                    self.changed.emit()
                self._post.emit(bad)
        threading.Thread(target=work, daemon=True).start()

    @Slot(int)
    def choose(self, i):
        if 0 <= i < len(self._versions):
            self._index = i
            self.changed.emit()

    @Slot(bool)
    def refreshDisks(self, internal):
        try:
            self._disks = devices.list_disks(allow_internal=internal and self.allowDisks)
            if not internal:
                self._disks = [d for d in self._disks if d.removable]
        except Exception as e:
            self._disks = []
            self._error = "Не удалось получить список дисков: " + str(e)
        self.changed.emit()

    @Slot(str, result=str)
    def pickFolder(self, start):
        return QFileDialog.getExistingDirectory(None, "Куда сохранить образ", start or self.downloads) or ""

    # ---------- работа ----------
    def _progress(self, stage, done, total):
        now = __import__("time").monotonic()

        def apply():
            t, d, s = self._t0
            if s != stage:
                self._t0 = (now, done, stage)
            elif now - t > 0.5:
                self._speed = (done - d) / (now - t)
                self._t0 = (now, done, stage)
            self._stage, self._done, self._total = stage, float(done), float(total)
            self.progressChanged.emit()
        self._post.emit(apply)

    @Slot(str, str)
    def start(self, kind, target):
        """kind: folder · usb · disk; target — папка или путь устройства."""
        if self._state == "busy" or not self._versions:
            return
        chosen = self._versions[self._index]
        image = self._image()
        disk = next((d for d in self._disks if d.path == target), None)
        if kind != "folder" and not disk:
            return
        self._cancel.clear()
        self._state, self._error, self._result, self._speed = "busy", "", "", 0.0
        self._stage, self._done, self._total = "download", 0.0, float(image.size)
        self.changed.emit()
        self.progressChanged.emit()

        def work():
            try:
                parts = download.get_image(image, self._progress, self._cancel)
                shell = download.get_shell(chosen, self._cancel) if chosen.shell else None
                choice = writer.choice_json(chosen, image)
                if kind == "folder":
                    iso = writer.to_folder(parts, image, target, shell, choice, self._progress, self._cancel)
                    msg = f"Образ сохранён: {iso}"
                else:
                    job = {"parts": parts, "total": image.size, "sha": download.expected_sha(image.sha256),
                           "disk": {"path": disk.path, "size": disk.size, "number": disk.number},
                           "shell": shell, "choice": choice}
                    if writer.need_elevation():
                        ok = writer.run_elevated(job, self._progress, self._cancel, via="pkexec")
                    else:
                        ok = writer.job_device(job, self._progress, self._cancel)
                    msg = f"Vanks OS записана на «{disk.name or disk.path}»."
                    if shell and not ok:
                        msg += " Для выбранной версии оболочки не хватило места — поставится версия из образа."

                def fin():
                    self._state, self._result = "done", msg
                    self.changed.emit()
                self._post.emit(fin)
            except download.Cancelled:
                def stop():
                    self._state = "ready"
                    self.changed.emit()
                self._post.emit(stop)
            except Exception as e:
                text = str(e)

                def bad():
                    self._state, self._error = "failed", text
                    self.changed.emit()
                self._post.emit(bad)
        threading.Thread(target=work, daemon=True).start()

    @Slot()
    def reset(self):
        """После «Готово» или ошибки — снова к выбору."""
        self._state, self._error, self._result = "ready", "", ""
        self.changed.emit()

    @Slot()
    def cancel(self):
        self._cancel.set()

    @Slot(str)
    def openPath(self, path):
        from PySide6.QtGui import QDesktopServices
        QDesktopServices.openUrl(QUrl.fromLocalFile(path))


def run():
    os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
    app = QApplication(sys.argv)
    app.setApplicationName("Vanks Setup")
    app.setOrganizationName("Vanks")
    pkg = resources.files(__package__)
    logo = pkg / "logo.png"
    if logo.is_file():
        from PySide6.QtGui import QPixmap
        pix = QPixmap()
        pix.loadFromData(logo.read_bytes())
        app.setWindowIcon(QIcon(pix))
    backend = Backend()
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", backend)
    import base64

    def data_uri(f, mime):
        return f"data:{mime};base64," + base64.b64encode(f.read_bytes()).decode()
    engine.rootContext().setContextProperty("logoData", data_uri(logo, "image/png") if logo.is_file() else "")
    # значки Delta (белые линии) — data: URI, чтобы работали и из .pyz
    icons = {f.name[:-4]: data_uri(f, "image/svg+xml") for f in (pkg / "icons").iterdir() if f.name.endswith(".svg")}
    engine.rootContext().setContextProperty("icons", icons)
    # для снимков экрана при разработке: сразу открыть шаг (VANKS_SETUP_STEP=1 VANKS_SETUP_KIND=folder)
    engine.rootContext().setContextProperty("startStep", int(os.environ.get("VANKS_SETUP_STEP", "0") or 0))
    engine.rootContext().setContextProperty("startKind", os.environ.get("VANKS_SETUP_KIND", ""))
    engine.loadData((pkg / "Main.qml").read_bytes(), QUrl("qrc:/Main.qml"))
    if not engine.rootObjects():
        return 1
    # проверки: VANKS_SETUP_AUTO="usb|/путь" — начать запись, как только придут версии
    auto = os.environ.get("VANKS_SETUP_AUTO", "")
    if auto and "|" in auto:
        kind, target = auto.split("|", 1)

        def go():
            if backend.state == "ready":
                backend.changed.disconnect(go)
                backend.refreshDisks(kind == "disk")
                backend.start(kind, target)
        backend.changed.connect(go)
    backend.load()
    return app.exec()
