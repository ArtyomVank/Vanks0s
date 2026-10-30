"""python -m vanks_setup и vanks-setup.pyz.

Без параметров — окно, если есть PySide6 и экран (и из терминала тоже, как
в Windows); терминал (cli.py) — с --cli, с любыми параметрами (--list,
--usb …) или когда окна быть не может (нет экрана, нет PySide6).
--write-helper — запись от root (writer.run_elevated).
"""

import os
import sys


def main():
    if "--write-helper" in sys.argv:
        from .cli import helper
        return helper()
    screen = sys.platform == "win32" or bool(os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY"))
    if "--gui" in sys.argv or (len(sys.argv) == 1 and screen):
        try:
            from .gui import run
        except ImportError:
            run = None
        if run:
            return run()
    from .cli import main as cli
    return cli([a for a in sys.argv[1:] if a not in ("--gui", "--cli")])


if __name__ == "__main__":
    sys.exit(main())
