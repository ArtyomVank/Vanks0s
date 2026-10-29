#!/usr/bin/env python3
"""Генератор брендинга Vanks OS.

Рисует все растровые ассеты проекта (логотип, обои, приветственный баннер,
карточки рабочих столов для установщика) в единой палитре. Никаких внешних
файлов не требуется — только Pillow.

Запуск:
    python tools/gen_branding.py            # из корня проекта
    python tools/gen_branding.py --root /path/to/vankos
"""

from __future__ import annotations

import argparse
import math
import os
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

# --- палитра ---------------------------------------------------------------
BG_DEEP = (11, 10, 18)
BG = (14, 12, 21)
BG_SOFT = (23, 20, 31)
VIOLET = (124, 92, 255)
CYAN = (34, 211, 238)
TEXT = (231, 228, 245)
MUTED = (167, 159, 196)

FONT_CANDIDATES = [
    r"C:\Windows\Fonts\segoeuib.ttf",
    r"C:\Windows\Fonts\segoeui.ttf",
    r"C:\Windows\Fonts\arialbd.ttf",
    r"C:\Windows\Fonts\arial.ttf",
    "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/noto/NotoSans-Bold.ttf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = FONT_CANDIDATES if bold else FONT_CANDIDATES[1::2] + FONT_CANDIDATES
    for path in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size)
            except OSError:
                continue
    return ImageFont.load_default()


def lerp(a: tuple[int, int, int], b: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))  # type: ignore[return-value]


def linear_gradient(size: tuple[int, int], start, end, angle: float = 90.0) -> Image.Image:
    """Плавный линейный градиент (angle в градусах, 90 = сверху вниз)."""
    w, h = size
    base = Image.new("RGB", (w, h))
    px = base.load()
    rad = math.radians(angle)
    dx, dy = math.cos(rad), math.sin(rad)
    denom = max(abs(dx) * w + abs(dy) * h, 1)
    for y in range(h):
        for x in range(w):
            t = (x * dx + y * dy) / denom + 0.5
            px[x, y] = lerp(start, end, min(max(t, 0.0), 1.0))
    return base


def radial_glow(size: tuple[int, int], center, radius, color, strength: float = 1.0) -> Image.Image:
    """Мягкое радиальное свечение как RGB-слой для screen-наложения."""
    w, h = size
    factor = 8
    small = (max(w // factor, 1), max(h // factor, 1))
    layer = Image.new("L", small, 0)
    draw = ImageDraw.Draw(layer)
    cx, cy = center[0] / factor, center[1] / factor
    r = max(radius / factor, 1)
    steps = 32
    for i in range(steps, 0, -1):
        t = i / steps
        rr = r * t
        # квадратичный профиль затухания к краю
        value = int(255 * min(strength, 1.0) * (1.0 - t) ** 2.2)
        draw.ellipse([cx - rr, cy - rr, cx + rr, cy + rr], fill=value)
    layer = layer.filter(ImageFilter.GaussianBlur(max(r / 2.5, 1)))
    layer = layer.resize(size, Image.LANCZOS)
    return Image.composite(Image.new("RGB", size, color), Image.new("RGB", size, (0, 0, 0)), layer)


def add_glow(base: Image.Image, glow: Image.Image, amount: float = 0.85) -> Image.Image:
    """Screen-наложение: свечение действительно светится, а не гасит фон."""
    screened = ImageChops.screen(base, glow)
    return Image.blend(base, screened, amount)


def add_vignette(img: Image.Image, strength: float = 0.55) -> Image.Image:
    w, h = img.size
    mask = Image.new("L", (w // 4, h // 4), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse([-w // 12, -h // 12, w // 4 + w // 12, h // 4 + h // 12], fill=255)
    mask = mask.filter(ImageFilter.GaussianBlur(w / 24)).resize((w, h), Image.LANCZOS)
    dark = Image.new("RGB", (w, h), (4, 3, 8))
    return Image.composite(img, Image.blend(img, dark, strength), mask)


def grid_overlay(size: tuple[int, int], step: int = 80, alpha: int = 12) -> Image.Image:
    w, h = size
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(layer)
    for x in range(0, w, step):
        draw.line([(x, 0), (x, h)], fill=(255, 255, 255, alpha), width=1)
    for y in range(0, h, step):
        draw.line([(0, y), (w, y)], fill=(255, 255, 255, alpha), width=1)
    return layer


def rounded_mask(size: tuple[int, int], radius: int) -> Image.Image:
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius=radius, fill=255)
    return mask


def draw_letter_mark(size: int) -> Image.Image:
    """Логотип: скруглённый квадрат с градиентом и монограммой V."""
    scale = 4
    s = size * scale
    card = linear_gradient((s, s), VIOLET, CYAN, angle=35).convert("RGBA")
    card.putalpha(rounded_mask((s, s), radius=int(s * 0.22)))

    # внутренняя тёмная подложка под букву
    inner = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    d = ImageDraw.Draw(inner)
    pad = int(s * 0.10)
    d.rounded_rectangle(
        [pad, pad, s - pad, s - pad],
        radius=int(s * 0.16),
        fill=(14, 12, 21, 210),
    )
    card.alpha_composite(inner)

    # буква V
    glyph = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glyph)
    f = font(int(s * 0.52), bold=True)
    text = "V"
    bbox = gd.textbbox((0, 0), text, font=f)
    tw, th = bbox[2] - bbox[0], bbox[3] - bbox[1]
    gd.text(((s - tw) / 2 - bbox[0], (s - th) / 2 - bbox[1] - int(s * 0.01)), text, font=f, fill=(255, 255, 255, 255))
    card.alpha_composite(glyph)

    # акцентная точка
    dot = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    dd = ImageDraw.Draw(dot)
    r = int(s * 0.045)
    cx, cy = int(s * 0.74), int(s * 0.27)
    dd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=CYAN + (255,))
    card.alpha_composite(dot)

    return card.resize((size, size), Image.LANCZOS)


def make_wallpaper(size=(1920, 1080)) -> Image.Image:
    base = linear_gradient(size, (13, 11, 20), (19, 15, 28), angle=105)

    base = add_glow(base, radial_glow(size, (size[0] * 0.10, size[1] * 0.04), size[0] * 0.55, VIOLET, 0.75), 0.55)
    base = add_glow(base, radial_glow(size, (size[0] * 0.92, size[1] * 0.96), size[0] * 0.50, CYAN, 0.45), 0.45)
    base = add_glow(base, radial_glow(size, (size[0] * 0.76, size[1] * 0.10), size[0] * 0.36, (226, 92, 255), 0.28), 0.40)
    base = add_glow(base, radial_glow(size, (size[0] * 0.38, size[1] * 0.62), size[0] * 0.32, (58, 78, 255), 0.18), 0.35)

    img = base.convert("RGBA")
    img.alpha_composite(grid_overlay(size, step=96, alpha=8))

    # тонкая диагональная «трасса»
    trace = Image.new("RGBA", size, (0, 0, 0, 0))
    td = ImageDraw.Draw(trace)
    for i, width in enumerate((3, 2, 1)):
        td.line(
            [(0, size[1] * 0.78 + i * 14), (size[0], size[1] * 0.42 + i * 14)],
            fill=(124, 92, 255, 60 - i * 16),
            width=width,
        )
    trace = trace.filter(ImageFilter.GaussianBlur(2))
    img.alpha_composite(trace)
    img = add_vignette(img.convert("RGB"), 0.62).convert("RGBA")

    d = ImageDraw.Draw(img)
    d.text((110, size[1] - 190), "Vanks OS", font=font(66, bold=True), fill=(255, 255, 255, 238))
    d.text((114, size[1] - 108), "Arch Linux · GNOME и Hyprland · 0.2 «Nebula»", font=font(24), fill=MUTED + (220,))

    logo = draw_letter_mark(120)
    img.alpha_composite(logo, (110, size[1] - 340))
    return img.convert("RGB")


def make_welcome(size=(720, 300)) -> Image.Image:
    img = Image.new("RGBA", size, (0, 0, 0, 0))
    logo = draw_letter_mark(150)
    img.alpha_composite(logo, (40, (size[1] - 150) // 2))
    d = ImageDraw.Draw(img)
    x = 220
    d.text((x, 88), "Vanks OS", font=font(56, bold=True), fill=(255, 255, 255, 255))
    d.text((x + 4, 156), "Arch Linux без лишних движений", font=font(21), fill=MUTED + (255,))
    d.text((x + 4, 190), "GNOME · Hyprland · офлайн-установка", font=font(17), fill=(124, 92, 255, 255))
    return img


def _screen_frame(size, title: str, accent, kind: str) -> Image.Image:
    """Общая рамка «скриншота» рабочего стола для карточки в установщике."""
    w, h = size
    img = linear_gradient(size, (16, 13, 24), (26, 21, 38), angle=100).convert("RGBA")

    # обои-градиент внутри «экрана»
    glow = radial_glow(size, (w * 0.25, h * 0.2), w * 0.7, accent, 0.55)
    img = add_glow(img.convert("RGB"), glow).convert("RGBA")

    d = ImageDraw.Draw(img)
    # верхняя панель
    d.rounded_rectangle([0, 0, w, 46], radius=0, fill=(10, 9, 16))
    d.text((22, 13), title, font=font(19, bold=True), fill=(255, 255, 255, 230))
    d.ellipse([w - 120, 18, w - 108, 30], fill=accent)
    d.text((w - 96, 14), "12:30", font=font(18), fill=MUTED)

    if kind == "gnome":
        # док слева
        d.rounded_rectangle([16, 86, 78, h - 26], radius=18, fill=(13, 11, 20))
        for i in range(5):
            yy = 104 + i * 62
            d.rounded_rectangle([28, yy, 66, yy + 38], radius=10, fill=(46, 40, 62))
        # окно
        d.rounded_rectangle([110, 96, w - 60, h - 70], radius=16, fill=(24, 20, 34),
                            outline=(60, 52, 82), width=1)
        d.rounded_rectangle([110, 96, w - 60, 136], radius=16, fill=(32, 27, 45))
        for i, col in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
            d.ellipse([130 + i * 22, 108, 144 + i * 22, 122], fill=col)
        d.text((150, 156), "Добро пожаловать в Vanks OS", font=font(30, bold=True), fill=(255, 255, 255, 235))
        d.text((150, 202), "Обзор · Док · Тёмная тема · жесты", font=font(19), fill=MUTED)
        for i in range(3):
            d.rounded_rectangle([150, 250 + i * 54, 150 + 420 - i * 70, 288 + i * 54], radius=10,
                                fill=(40, 34, 54))
    else:
        # Delta: верхний док-«остров», часы на столе, стеклянное окно, док приложений
        d.rounded_rectangle([w // 2 - 210, 58, w // 2 + 210, 90], radius=16, fill=(18, 15, 28),
                            outline=(60, 52, 82), width=1)
        d.text((w // 2 - 190, 64), "1  2  3", font=font(16), fill=MUTED)
        d.text((w // 2 - 26, 63), "12:30", font=font(18, bold=True), fill=(255, 255, 255, 235))
        d.ellipse([w // 2 + 150, 68, w // 2 + 162, 80], fill=accent)
        d.ellipse([w // 2 + 172, 68, w // 2 + 184, 80], fill=MUTED)

        d.text((60, 120), "12:30", font=font(96, bold=True), fill=(255, 255, 255, 225))
        d.text((66, 230), "среда, 28 октября", font=font(22), fill=MUTED)

        d.rounded_rectangle([w // 2 - 20, 120, w - 50, h - 110], radius=18, fill=(24, 20, 36),
                            outline=(70, 62, 96), width=1)
        d.rounded_rectangle([w // 2 - 20, 120, w - 50, 160], radius=18, fill=(32, 27, 46))
        d.text((w // 2 + 4, 130), "Настройки", font=font(17, bold=True), fill=TEXT)
        for i in range(4):
            yy = 180 + i * 46
            d.rounded_rectangle([w // 2, yy, w - 70, yy + 34], radius=10, fill=(40, 34, 56))
            d.ellipse([w - 120, yy + 9, w - 104, yy + 25], fill=accent if i % 2 == 0 else MUTED)

        dock_w = 6 * 52 + 20
        x0 = (w - dock_w) // 2
        d.rounded_rectangle([x0, h - 84, x0 + dock_w, h - 20], radius=22, fill=(18, 15, 28),
                            outline=(60, 52, 82), width=1)
        for i in range(6):
            xx = x0 + 14 + i * 52
            d.rounded_rectangle([xx, h - 74, xx + 42, h - 32], radius=12,
                                fill=accent if i == 0 else (52, 46, 72))
    return img


def make_card(name: str, title: str, subtitle: str, accent, kind: str, size=(960, 620)) -> Image.Image:
    w, h = size
    canvas = Image.new("RGBA", size, (12, 10, 19, 255))
    shot = _screen_frame((w - 40, h - 150), title, accent, kind)

    mask = rounded_mask(shot.size, 14)
    canvas.paste(shot, (20, 20), mask)
    d = ImageDraw.Draw(canvas)
    d.rounded_rectangle([20, 20, w - 20, h - 130], radius=14, outline=accent, width=1)
    d.text((24, h - 108), name, font=font(38, bold=True), fill=(255, 255, 255, 245))
    d.text((26, h - 58), subtitle, font=font(20), fill=MUTED)
    return canvas


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    root = Path(args.root)

    branding = root / "calamares" / "branding" / "vankos"
    backgrounds = root / "iso" / "airootfs" / "usr" / "share" / "backgrounds" / "vankos"
    for directory in (branding, backgrounds):
        directory.mkdir(parents=True, exist_ok=True)

    wallpaper = make_wallpaper()
    wallpaper.save(branding / "wallpaper.png", optimize=True)
    wallpaper.save(backgrounds / "wallpaper.png", optimize=True)

    draw_letter_mark(512).save(branding / "logo.png", optimize=True)
    make_welcome().save(branding / "welcome.png", optimize=True)

    make_card(
        "GNOME",
        "GNOME",
        "Обзор, док, тёмная тема, GDM",
        VIOLET,
        "gnome",
    ).save(branding / "gnome.png", optimize=True)

    make_card(
        "Delta",
        "Delta",
        "Рабочий стол Vanks OS: Hyprland, доки, виджеты",
        CYAN,
        "delta",
    ).save(branding / "delta.png", optimize=True)

    print(f"Ассеты брендинга записаны в {branding}")
    print(f"Обои для live-системы: {backgrounds / 'wallpaper.png'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
