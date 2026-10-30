"""python -m vanks_setup и vanks-setup.pyz.

Окно — с --gui или когда программу открыли не из терминала (двойной щелчок,
.exe), если есть PySide6 и экран; иначе — терминал (cli.py).
--write-helper — запись от root (writer.run_elevated).
"""

import os
import sys


def main():
    if "--write-helper" in sys.argv:
        from .cli import helper
        return helper()
    screen = sys.platform == "win32" or bool(os.environ.get("WAYLAND_DISPLAY") or os.environ.get("DISPLAY"))
    terminal = sys.stdin is not None and sys.stdin.isatty()
    if "--gui" in sys.argv or (len(sys.argv) == 1 and screen and not terminal):
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
