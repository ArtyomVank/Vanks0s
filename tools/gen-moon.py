#!/usr/bin/env python3
"""Карта Луны для супер обоев: delta/shell/wallpaper/super/moon-map.jpg.

Вся карта придумана здесь, чужих снимков нет: моря — размытый шум, поверх
кратеры с чашей, валом и лучами. Равнопромежуточная проекция; красный канал —
высота, зелёный — светлота грунта. Нужны Python и ImageMagick, считается минуту.

    tools/gen-moon.py
"""
import array
import math
import os
import random
import subprocess
import tempfile

W, H = 3072, 1536
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "delta/shell/wallpaper/super/moon-map.jpg")

random.seed(1969)
height = array.array("f", bytes(4 * W * H))
albedo = array.array("f", bytes(4 * W * H))


def crater(lat, lon, radius, depth, rays=0.0):
    """радиус в пикселях по экватору; ближе к полюсу карта растянута по долготе"""
    cy = int((0.5 - lat / math.pi) * H)
    cx = int((lon / (2 * math.pi)) * W)
    stretch = 1 / max(0.15, math.cos(lat))
    reach = 3.2 if rays else 1.7
    ry = int(radius * reach) + 1
    rx = min(W // 2 - 1, int(radius * reach * stretch) + 1)
    spokes = [(random.uniform(0, 2 * math.pi), random.uniform(0.3, 1.0)) for _ in range(14)] if rays else []
    for y in range(max(0, cy - ry), min(H, cy + ry + 1)):
        dy = y - cy
        row = y * W
        for x in range(cx - rx, cx + rx + 1):
            dx = (x - cx) / stretch
            d = math.sqrt(dx * dx + dy * dy) / radius
            if d >= reach:
                continue
            i = row + (x % W)
            if d < 1.0:
                # чаша с плоским дном и валом по краю
                height[i] += depth * (-(1 - d ** 4) + 0.28 * d ** 12)
                albedo[i] += 0.05 * rays - 0.02
            elif d < 1.7:
                height[i] += depth * 0.28 * (1.7 - d) ** 2 / 0.49
            if spokes and d >= 1.0:
                a = math.atan2(dy, dx)
                s = 0.0
                for angle, power in spokes:
                    gap = abs((a - angle + math.pi) % (2 * math.pi) - math.pi)
                    if gap < 0.09:
                        s = max(s, power * (1 - gap / 0.09))
                albedo[i] += rays * s * (1 - (d - 1) / (reach - 1)) ** 1.6


def random_point():
    return math.asin(random.uniform(-1, 1)), random.uniform(0, 2 * math.pi)


# крупные — мало, мелкие — много, как на настоящей Луне
for _ in range(30):
    crater(*random_point(), random.uniform(48, 120), random.uniform(0.30, 0.45))
for _ in range(240):
    crater(*random_point(), random.uniform(14, 44), random.uniform(0.25, 0.42))
for _ in range(2200):
    crater(*random_point(), random.uniform(4, 13), random.uniform(0.18, 0.35))
for _ in range(9000):
    crater(*random_point(), random.uniform(1.5, 4), random.uniform(0.10, 0.22))
# молодые кратеры с лучами — на обращённой к нам стороне
for lat, lon, r in [(-0.75, 0.15, 26), (0.18, -0.35, 20), (0.05, 0.5, 15), (0.55, -0.15, 13)]:
    crater(lat, lon % (2 * math.pi), r, 0.42, rays=0.34)


def grid_noise(cells_x, cells_y):
    """гладкий шум: случайная сетка, по долготе замкнута"""
    grid = [[random.random() for _ in range(cells_x)] for _ in range(cells_y + 1)]

    def row(y):
        fy = y / H * cells_y
        iy = min(cells_y - 1, int(fy))
        t = fy - iy
        t = t * t * (3 - 2 * t)
        a, b = grid[iy], grid[iy + 1]
        line = [a[j] * (1 - t) + b[j] * t for j in range(cells_x)]
        out = [0.0] * W
        k = cells_x / W
        for x in range(W):
            fx = x * k
            ix = int(fx)
            u = fx - ix
            u = u * u * (3 - 2 * u)
            out[x] = line[ix] * (1 - u) + line[(ix + 1) % cells_x] * u
        return out
    return row


def smooth(a, b, v):
    t = max(0.0, min(1.0, (v - a) / (b - a)))
    return t * t * (3 - 2 * t)


# моря — самые низкие частоты, материки изрезаны средними и мелкими
low = [grid_noise(9, 5), grid_noise(19, 10), grid_noise(41, 21)]
mid = [grid_noise(90, 45), grid_noise(200, 100), grid_noise(460, 230)]

pixels = bytearray(W * H * 3)
for y in range(H):
    r0, r1, r2 = low[0](y), low[1](y), low[2](y)
    m0, m1, m2 = mid[0](y), mid[1](y), mid[2](y)
    row = y * W
    for x in range(W):
        sea = smooth(0.50, 0.58, r0[x] * 0.58 + r1[x] * 0.28 + r2[x] * 0.14)
        rough = m0[x] * 0.5 + m1[x] * 0.3 + m2[x] * 0.2 - 0.5
        i = row + x
        h = 0.5 + rough * (0.34 - 0.27 * sea) + height[i] * 0.36 - sea * 0.05
        a = 0.66 - 0.31 * sea + (m1[x] - 0.5) * 0.10 + (r2[x] - 0.5) * 0.08 + (random.random() - 0.5) * 0.035 + albedo[i]
        j = i * 3
        pixels[j] = max(0, min(255, int(h * 255)))
        pixels[j + 1] = max(0, min(255, int(a * 255)))
        pixels[j + 2] = 128

with tempfile.TemporaryDirectory() as tmp:
    raw = os.path.join(tmp, "moon.ppm")
    with open(raw, "wb") as f:
        f.write(b"P6\n%d %d\n255\n" % (W, H) + bytes(pixels))
    subprocess.check_call(["magick", raw, "-sampling-factor", "4:4:4", "-quality", "88", OUT])
print(OUT, os.path.getsize(OUT))
