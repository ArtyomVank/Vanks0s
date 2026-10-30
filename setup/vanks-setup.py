# Точка входа для PyInstaller (.exe для Windows, файл для Linux):
# двойной щелчок — окно, из терминала — команды (vanks-setup --help).
import sys

from vanks_setup.__main__ import main

sys.exit(main())
