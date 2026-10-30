"""Vanks Setup — скачивает Vanks OS из релизов GitHub и записывает её
в папку или на флешку (а с разрешения в настройках — на диск).

Ядро — только стандартная библиотека Python: его же запускает команда для
терминала (cli.py) и окно (gui/). Модули:
    releases  — версии из релизов GitHub: образ кусками и пакет оболочки
    download  — загрузка с докачкой и проверкой sha256
    devices   — флешки и диски (Linux: lsblk, Windows: Get-Disk)
    writer    — запись образа и раздел VANKOS с выбранной версией оболочки
"""

VERSION = "1.0.0"


def _certs():
    """Сертификаты для https. Python из сборки PyInstaller принёс свой
    OpenSSL, а тот ищет их там, где они лежали на машине сборки (Ubuntu:
    /usr/lib/ssl) — на Arch, Fedora и других их там нет. Тогда берём набор
    системы, а если и его нет — встроенный certifi."""
    import os
    import ssl
    if os.environ.get("SSL_CERT_FILE") or os.environ.get("SSL_CERT_DIR"):
        return
    paths = ssl.get_default_verify_paths()
    if (paths.cafile and os.path.isfile(paths.cafile)) or (paths.capath and os.path.isdir(paths.capath)
                                                           and os.listdir(paths.capath)):
        return
    for f in ("/etc/ssl/certs/ca-certificates.crt",      # Arch, Debian, Ubuntu
              "/etc/pki/tls/certs/ca-bundle.crt",         # Fedora
              "/etc/ssl/ca-bundle.pem",                   # openSUSE
              "/etc/ssl/cert.pem"):                       # Alpine, macOS
        if os.path.isfile(f):
            os.environ["SSL_CERT_FILE"] = f
            return
    try:
        import certifi
        os.environ["SSL_CERT_FILE"] = certifi.where()
    except ImportError:
        pass


_certs()
