"""Small UI sprites and the title-screen backdrop -> assets/ui/."""
import math
import os
import random

import palette as P
from pxl import Canvas, mix, shade

E_GLYPH = [
    "11111",
    "10000",
    "10000",
    "11110",
    "10000",
    "10000",
    "11111",
]


def prompt_icon():
    """16x16 key-cap bubble with an 'E' for the interaction indicator."""
    cv = Canvas(16, 16)
    cv.rect(1, 1, 14, 13, (250, 244, 224))
    cv.rect(2, 2, 13, 12, (236, 226, 196))
    cv.hline(2, 13, 12, (196, 182, 146))
    cv.rect(6, 14, 9, 14, (250, 244, 224))
    cv.set(7, 15, (250, 244, 224))
    cv.set(8, 15, (250, 244, 224))
    for gy, row in enumerate(E_GLYPH):
        for gx, ch in enumerate(row):
            if ch == "1":
                cv.set(5 + gx, 3 + gy, (58, 40, 30))
    cv.outline(P.OUTLINE)
    return cv


def title_backdrop(w=640, h=360, seed=7):
    rng = random.Random(seed)
    cv = Canvas(w, h)
    top, mid, low = (26, 38, 84), (206, 112, 84), (244, 190, 112)
    horizon = 232
    for y in range(h):
        if y < horizon * 0.6:
            col = mix(top, mid, y / (horizon * 0.6))
        elif y < horizon:
            col = mix(mid, low, (y - horizon * 0.6) / (horizon * 0.4))
        else:
            col = low
        for x in range(w):
            cv.set(x, y, col)
    for _ in range(70):  # fading stars
        x, y = rng.randrange(w), rng.randrange(0, 90)
        cv.set(x, y, (240, 232, 214))
    sx, sy = 430, 214
    for r, a in ((54, 36), (40, 60), (30, 90)):  # glow, then disc
        cv.ellipse(sx, sy, r, r, (255, 220, 150, a))
    cv.ellipse(sx, sy, 22, 22, (255, 240, 200))
    layers = ((190, (130, 86, 96), 0.010), (216, (96, 62, 72), 0.016), (250, (64, 46, 56), 0.022))
    for base, col, freq in layers:
        phase = rng.random() * 6
        for x in range(w):
            hgt = base - 14 * math.sin(x * freq + phase) - 7 * math.sin(x * freq * 2.7 + phase * 2)
            for y in range(int(hgt), h):
                cv.set(x, y, col)
    for x in range(w):  # foreground slope
        top_y = 300 + int(8 * math.sin(x * 0.02) + 4 * math.sin(x * 0.07))
        for y in range(top_y, h):
            cv.set(x, y, (34, 28, 30))
    for tx, th in ((78, 70), (168, 52), (560, 74), (610, 50)):  # olive silhouettes
        trunk_top = 304 - th // 2
        cv.rect(tx - 2, trunk_top, tx + 2, 306, (34, 28, 30))
        for cx, cy, rx, ry in ((tx, trunk_top - 8, 26, 14), (tx - 16, trunk_top, 16, 10), (tx + 16, trunk_top, 16, 10)):
            cv.ellipse(cx, cy, rx, ry, (34, 28, 30))
    return cv


def write(out_dir):
    prompt_icon().save(os.path.join(out_dir, "prompt_e.png"))
    title_backdrop().save(os.path.join(out_dir, "title_bg.png"))


if __name__ == "__main__":
    write(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "ui"))
