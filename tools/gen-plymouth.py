#!/usr/bin/env python3
"""Картинки заставки загрузки Delta (Plymouth): знак V и точка загрузки.

Рисует pycairo (системный python), кладёт в delta/session/plymouth/delta/.
Запуск из корня проекта:
    python3 tools/gen-plymouth.py
"""

import math
from pathlib import Path

import cairo

OUT = Path(__file__).resolve().parent.parent / "delta" / "session" / "plymouth" / "delta"
CYAN = (34 / 255, 211 / 255, 238 / 255)


def logo(size: int) -> None:
    """Белая буква V из двух скруглённых штрихов и бирюзовая точка справа сверху."""
    s = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    c = cairo.Context(s)
    k = size / 100
    c.set_line_cap(cairo.LINE_CAP_ROUND)
    c.set_line_join(cairo.LINE_JOIN_ROUND)
    c.set_line_width(13 * k)
    c.set_source_rgb(1, 1, 1)
    c.move_to(22 * k, 26 * k)
    c.line_to(47 * k, 80 * k)
    c.line_to(72 * k, 26 * k)
    c.stroke()
    c.set_source_rgb(*CYAN)
    c.arc(86 * k, 17 * k, 7 * k, 0, 2 * math.pi)
    c.fill()
    s.write_to_png(str(OUT / "logo.png"))


def dot(size: int) -> None:
    s = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    c = cairo.Context(s)
    c.set_source_rgb(1, 1, 1)
    c.arc(size / 2, size / 2, size / 2 - 0.5, 0, 2 * math.pi)
    c.fill()
    s.write_to_png(str(OUT / "dot.png"))


def field(w: int, h: int) -> None:
    """Поле пароля (диск зашифрован): тёмная скруглённая плашка с рамкой."""
    s = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
    c = cairo.Context(s)
    r = h / 2
    c.new_sub_path()
    c.arc(w - r, r, r - 1, -math.pi / 2, math.pi / 2)
    c.arc(r, r, r - 1, math.pi / 2, 3 * math.pi / 2)
    c.close_path()
    c.set_source_rgba(1, 1, 1, 0.08)
    c.fill_preserve()
    c.set_source_rgba(1, 1, 1, 0.28)
    c.set_line_width(1.5)
    c.stroke()
    s.write_to_png(str(OUT / "field.png"))


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    logo(132)
    dot(9)
    field(300, 44)
    print("готово:", OUT)
