"""Procedural props -> assets/props/*.png + props.json.

Each prop's origin is its ground contact point (bottom-centre); `collider` is the footprint [w, h]
centred on that origin, extending upward.
"""
import json
import os
import random

import palette as P
from pxl import Canvas, shade

SHADOW = (30, 24, 20, 70)


def _shadow(cv, cx, cy, rx, ry):
    cv.ellipse(cx, cy, rx, ry, SHADOW)


def _blob(cv, rng, cx, cy, rx, ry, base, dots=None):
    cv.ellipse(cx, cy, rx, ry, shade(base, 0.72))
    cv.ellipse(cx - 1, cy - 1, rx - 1, ry - 1, base)
    cv.ellipse(cx - 2, cy - 3, max(2, rx - 4), max(2, ry - 4), shade(base, 1.14))
    for _ in range(int(rx * ry / 6)):
        x = cx + rng.randrange(-int(rx), int(rx) + 1)
        y = cy + rng.randrange(-int(ry), int(ry) + 1)
        if ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 < 0.8:
            cv.set(x, y, shade(base, rng.choice([0.8, 1.2])))
    if dots:
        for _ in range(6):
            x = cx + rng.randrange(-int(rx) + 3, int(rx) - 2)
            y = cy + rng.randrange(-int(ry) + 3, int(ry) - 2)
            cv.set(x, y, dots)


def olive_tree(seed):
    rng = random.Random(seed)
    cv = Canvas(64, 80)
    _shadow(cv, 32, 74, 22, 5)
    trunk = (104, 84, 66)
    # gnarled, split trunk
    cv.rect(28, 58, 36, 74, trunk)
    cv.rect(29, 58, 30, 74, shade(trunk, 1.2))
    cv.rect(35, 58, 36, 74, shade(trunk, 0.75))
    cv.line(29, 60, 22, 46, trunk)
    cv.line(30, 60, 23, 46, trunk)
    cv.line(35, 60, 42, 44, trunk)
    cv.line(34, 60, 41, 44, trunk)
    cv.set(31, 66, shade(trunk, 0.6))
    cv.set(32, 70, shade(trunk, 0.6))
    # silvery canopy
    for cx, cy, rx, ry in ((32, 34, 20, 14), (19, 40, 14, 11), (45, 40, 14, 11),
                           (26, 26, 14, 11), (40, 26, 14, 11), (32, 20, 12, 9)):
        _blob(cv, rng, cx, cy, rx, ry, shade(P.OLIVE_LEAF, rng.choice([0.94, 1.0, 1.06])), dots=(60, 66, 52))
    cv.outline(P.OUTLINE)
    return cv


def cypress(seed):
    rng = random.Random(seed)
    cv = Canvas(32, 72)
    _shadow(cv, 16, 68, 9, 3)
    cv.rect(14, 62, 17, 68, (92, 70, 52))
    cv.ellipse(16, 34, 9, 30, shade(P.CYPRESS, 0.75))
    cv.ellipse(15, 33, 8, 29, P.CYPRESS)
    for _ in range(90):
        x = rng.randrange(8, 24)
        y = rng.randrange(6, 62)
        if ((x - 16) / 8.0) ** 2 + ((y - 34) / 28.0) ** 2 < 0.85:
            cv.set(x, y, shade(P.CYPRESS, rng.choice([0.8, 1.25, 1.4])))
    cv.outline(P.OUTLINE)
    return cv


def bush(seed, flowers=False):
    rng = random.Random(seed)
    cv = Canvas(32, 24)
    _shadow(cv, 16, 21, 12, 3)
    _blob(cv, rng, 16, 13, 13, 8, P.BUSH, dots=(226, 120, 132) if flowers else None)
    cv.outline(P.OUTLINE)
    return cv


def boulder(seed):
    rng = random.Random(seed)
    cv = Canvas(32, 24)
    _shadow(cv, 16, 21, 12, 3)
    base = (150, 138, 120)
    cv.ellipse(16, 14, 13, 8, shade(base, 0.7))
    cv.ellipse(15, 13, 12, 7, base)
    cv.ellipse(12, 10, 7, 4, shade(base, 1.18))
    for _ in range(14):
        cv.set(rng.randrange(5, 27), rng.randrange(8, 20), shade(base, 0.8))
    cv.outline(P.OUTLINE)
    return cv


def well(seed):
    rng = random.Random(seed)
    cv = Canvas(48, 56)
    _shadow(cv, 24, 50, 20, 5)
    stone = P.LIMESTONE
    # wooden posts behind the rim
    for x0 in (7, 38):
        cv.rect(x0, 6, x0 + 2, 36, P.WOOD)
        cv.vline(x0, 6, 36, P.WOOD_LIGHT)
    cv.rect(5, 5, 42, 8, P.WOOD_LIGHT)
    cv.hline(5, 42, 8, P.WOOD_DARK)
    # rope + bucket
    cv.vline(24, 9, 22, (170, 150, 110))
    cv.rect(21, 22, 27, 27, P.WOOD)
    cv.hline(21, 27, 22, P.WOOD_LIGHT)
    cv.hline(21, 27, 26, P.WOOD_DARK)
    # stone drum
    cv.rect(6, 28, 41, 44, shade(stone, 0.9))
    cv.ellipse(24, 44, 18, 6, shade(stone, 0.8))
    cv.ellipse(24, 28, 18, 10, P.LIMESTONE_LIGHT)
    cv.ellipse(24, 28, 13, 7, (34, 60, 78))
    cv.ellipse(22, 27, 7, 3, (58, 98, 124))
    for y in (33, 38):
        cv.hline(7, 40, y, P.MORTAR)
    for x in range(10, 40, 7):
        cv.vline(x, 29, 33, P.MORTAR)
        cv.vline(x + 3, 34, 38, P.MORTAR)
        cv.vline(x + 1, 39, 43, P.MORTAR)
    cv.outline(P.OUTLINE)
    return cv


def jar_small(seed):
    cv = Canvas(16, 16)
    _shadow(cv, 8, 14, 5, 2)
    cv.ellipse(8, 9, 5.5, 5.5, shade(P.CLAY, 0.78))
    cv.ellipse(8, 8.5, 5, 5, P.CLAY)
    cv.ellipse(6, 7, 2, 2.5, shade(P.CLAY, 1.25))
    cv.rect(6, 2, 9, 4, shade(P.CLAY, 0.9))
    cv.hline(5, 10, 2, shade(P.CLAY, 1.15))
    cv.hline(5, 10, 8, shade(P.CLAY, 0.7))
    cv.outline(P.OUTLINE)
    return cv


def jar_large(seed):
    cv = Canvas(20, 30)
    _shadow(cv, 10, 27, 7, 2)
    cv.ellipse(10, 17, 7.5, 9, shade(P.CLAY, 0.78))
    cv.ellipse(10, 16.5, 7, 8.5, P.CLAY)
    cv.ellipse(7, 14, 2.5, 4, shade(P.CLAY, 1.22))
    cv.rect(7, 4, 12, 9, shade(P.CLAY, 0.92))
    cv.rect(6, 3, 13, 4, shade(P.CLAY, 1.1))
    cv.vline(4, 7, 13, shade(P.CLAY, 0.8))
    cv.vline(15, 7, 13, shade(P.CLAY, 0.8))
    cv.hline(4, 15, 15, shade(P.CLAY, 0.65))
    cv.hline(5, 14, 19, shade(P.CLAY, 0.65))
    cv.outline(P.OUTLINE)
    return cv


def crate(seed):
    cv = Canvas(24, 24)
    _shadow(cv, 12, 21, 10, 3)
    cv.rect(2, 6, 21, 19, P.WOOD)
    cv.rect(2, 6, 21, 8, P.WOOD_LIGHT)
    cv.hline(2, 21, 13, P.WOOD_DARK)
    cv.vline(2, 6, 19, P.WOOD_DARK)
    cv.vline(21, 6, 19, P.WOOD_DARK)
    cv.vline(11, 9, 19, P.WOOD_DARK)
    cv.outline(P.OUTLINE)
    return cv


def basket(seed):
    cv = Canvas(20, 18)
    _shadow(cv, 10, 16, 8, 2)
    cv.ellipse(10, 11, 8, 5, (176, 140, 84))
    for x in range(3, 17, 3):
        cv.vline(x, 8, 14, (140, 106, 62))
    cv.hline(3, 17, 11, (140, 106, 62))
    cv.ellipse(10, 7, 7, 3, (120, 70, 96))  # figs
    for x, y in ((7, 6), (10, 5), (13, 6), (9, 8), (12, 8)):
        cv.set(x, y, (156, 98, 124))
    cv.outline(P.OUTLINE)
    return cv


def market_stall(seed):
    rng = random.Random(seed)
    cv = Canvas(72, 60)
    _shadow(cv, 36, 54, 30, 5)
    # table
    cv.rect(8, 36, 63, 42, P.WOOD_LIGHT)
    cv.rect(8, 42, 63, 46, P.WOOD)
    cv.hline(8, 63, 42, P.WOOD_DARK)
    for x in (10, 60):
        cv.rect(x, 46, x + 2, 54, P.WOOD_DARK)
    # goods on the table
    for i in range(7):  # dried fish
        x = 12 + i * 5
        cv.rect(x, 31, x + 1, 36, (150, 150, 140))
        cv.set(x, 31, (190, 190, 180))
    for i in range(6):  # figs
        cv.ellipse(46 + i * 3, 34, 1.8, 1.8, (110, 62, 96))
    cv.ellipse(56, 33, 3.5, 2.5, (204, 164, 100))  # bread
    cv.ellipse(60, 34, 3, 2, (190, 146, 86))
    # posts + awning
    for x in (6, 64):
        cv.rect(x, 12, x + 2, 46, P.WOOD)
        cv.vline(x, 12, 46, P.WOOD_LIGHT)
    for i, x in enumerate(range(2, 70, 5)):
        col = (170, 72, 58) if i % 2 == 0 else (228, 214, 176)
        for y in range(8, 22):
            cv.rect(x, y, x + 4, y, shade(col, 0.9 + (y - 8) * 0.008))
        cv.rect(x, 22, x + 4, 24, shade(col, 0.8))
    cv.hline(2, 70, 8, (240, 228, 196))
    cv.outline(P.OUTLINE)
    return cv


def signpost(seed):
    cv = Canvas(32, 48)
    _shadow(cv, 16, 44, 8, 2)
    cv.rect(14, 8, 17, 44, P.WOOD)
    cv.vline(14, 8, 44, P.WOOD_LIGHT)
    cv.vline(17, 8, 44, P.WOOD_DARK)
    # arrow board pointing right (east)
    cv.rect(10, 10, 24, 18, P.WOOD_LIGHT)
    cv.line(25, 10, 29, 14, P.WOOD_LIGHT)
    cv.line(25, 18, 29, 14, P.WOOD_LIGHT)
    cv.rect(25, 11, 27, 17, P.WOOD_LIGHT)
    cv.hline(12, 23, 12, P.WOOD_DARK)
    cv.hline(12, 20, 14, P.WOOD_DARK)
    cv.hline(12, 22, 16, P.WOOD_DARK)
    # small board pointing left
    cv.rect(4, 22, 17, 28, P.WOOD)
    cv.line(3, 25, 7, 21, P.WOOD)
    cv.line(3, 25, 7, 29, P.WOOD)
    cv.hline(7, 15, 25, P.WOOD_DARK)
    cv.outline(P.OUTLINE)
    return cv


def clay_oven(seed):
    cv = Canvas(36, 34)
    _shadow(cv, 18, 31, 15, 3)
    cv.ellipse(18, 20, 14, 12, shade((196, 144, 104), 0.75))
    cv.rect(4, 20, 32, 30, shade((196, 144, 104), 0.75))
    cv.ellipse(18, 19, 13, 11, (196, 144, 104))
    cv.ellipse(14, 14, 7, 5, (216, 168, 126))
    cv.ellipse(18, 25, 6, 5, (40, 24, 20))
    cv.rect(12, 25, 24, 30, (40, 24, 20))
    cv.hline(12, 24, 30, (220, 150, 70))
    cv.outline(P.OUTLINE)
    return cv


def flowers_patch(seed):
    rng = random.Random(seed)
    cv = Canvas(20, 12)
    for _ in range(9):
        x, y = rng.randrange(2, 18), rng.randrange(3, 10)
        cv.set(x, y + 1, (84, 112, 56))
        cv.set(x, y, rng.choice([(240, 236, 220), (226, 190, 70), (196, 84, 96)]))
    return cv


def scroll(seed):
    cv = Canvas(16, 12)
    _shadow(cv, 8, 10, 6, 2)
    cv.rect(2, 3, 13, 8, (226, 208, 160))
    cv.hline(2, 13, 3, (244, 230, 190))
    cv.hline(2, 13, 8, (176, 152, 104))
    cv.hline(4, 11, 5, (150, 126, 86))
    cv.hline(4, 9, 6, (150, 126, 86))
    cv.rect(1, 2, 2, 9, P.WOOD)
    cv.rect(13, 2, 14, 9, P.WOOD)
    cv.set(1, 2, P.WOOD_LIGHT)
    cv.set(13, 2, P.WOOD_LIGHT)
    cv.outline(P.OUTLINE)
    return cv


def flatbread(seed):
    cv = Canvas(14, 10)
    _shadow(cv, 7, 8, 5, 2)
    cv.ellipse(7, 5, 5.5, 3.2, (170, 118, 66))
    cv.ellipse(7, 4.5, 5, 2.8, (216, 170, 104))
    cv.set(5, 4, (170, 118, 66))
    cv.set(8, 3, (170, 118, 66))
    cv.set(9, 5, (170, 118, 66))
    cv.outline(P.OUTLINE)
    return cv


PROPS = [
    # name, builder, origin, collider (w, h) or None
    ("olive_tree_a", lambda: olive_tree(1), (32, 76), (14, 8)),
    ("olive_tree_b", lambda: olive_tree(2), (32, 76), (14, 8)),
    ("cypress", lambda: cypress(3), (16, 68), (8, 6)),
    ("bush", lambda: bush(4), (16, 21), (22, 8)),
    ("bush_flowers", lambda: bush(5, True), (16, 21), (22, 8)),
    ("boulder", lambda: boulder(6), (16, 21), (24, 10)),
    ("well", lambda: well(7), (24, 50), (36, 14)),
    ("jar_small", lambda: jar_small(8), (8, 14), None),
    ("jar_large", lambda: jar_large(9), (10, 27), (10, 6)),
    ("crate", lambda: crate(10), (12, 21), (18, 8)),
    ("basket", lambda: basket(11), (10, 16), (14, 6)),
    ("market_stall", lambda: market_stall(12), (36, 54), (56, 12)),
    ("signpost", lambda: signpost(13), (16, 44), (6, 5)),
    ("clay_oven", lambda: clay_oven(14), (18, 31), (26, 10)),
    ("flowers_patch", lambda: flowers_patch(15), (10, 11), None),
    ("scroll", lambda: scroll(16), (8, 11), None),
    ("flatbread", lambda: flatbread(17), (7, 9), None),
]


def write(out_dir):
    meta = {}
    for name, build, origin, collider in PROPS:
        cv = build()
        cv.save(os.path.join(out_dir, f"{name}.png"))
        meta[name] = {"file": f"{name}.png", "size": [cv.w, cv.h], "origin": list(origin),
                      "collider": list(collider) if collider else None}
    with open(os.path.join(out_dir, "props.json"), "w") as f:
        json.dump(meta, f, indent=1)


if __name__ == "__main__":
    write(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "props"))
