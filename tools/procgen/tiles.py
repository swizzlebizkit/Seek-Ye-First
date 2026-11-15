"""Procedural 32x32 terrain/building tiles -> assets/tiles/terrain.png + terrain.json."""
import json
import os
import random

import palette as P
from pxl import Canvas, shade

T = 32


def _noise(cv, rng, base, count, factors):
    for _ in range(count):
        cv.set(rng.randrange(T), rng.randrange(T), shade(base, rng.choice(factors)))


def grass(seed, base=P.GRASS, flowers=False):
    rng = random.Random(seed)
    cv = Canvas(T, T, base)
    _noise(cv, rng, base, 110, (0.9, 0.94, 1.06, 1.1))
    for _ in range(9):
        x, y = rng.randrange(1, T - 2), rng.randrange(3, T)
        cv.set(x, y, shade(base, 0.76))
        cv.set(x, y - 1, shade(base, 0.9))
        cv.set(x + 1, y - 2, shade(base, 1.2))
        cv.set(x - 1, y - 2, shade(base, 1.2))
    if flowers:
        for _ in range(7):
            x, y = rng.randrange(2, T - 2), rng.randrange(3, T - 2)
            col = rng.choice([(240, 236, 220), (226, 190, 70), (196, 84, 96), (236, 236, 236)])
            cv.set(x, y, col)
            cv.set(x, y + 1, (84, 110, 56))
    return cv


def dirt(seed):
    rng = random.Random(seed)
    cv = Canvas(T, T, P.DIRT)
    _noise(cv, rng, P.DIRT, 130, (0.88, 0.93, 1.07, 1.12))
    for _ in range(7):
        x, y = rng.randrange(1, T - 3), rng.randrange(1, T - 2)
        cv.set(x, y, (206, 186, 154))
        cv.set(x + 1, y, (190, 168, 134))
        cv.set(x, y + 1, (120, 92, 62))
        cv.set(x + 1, y + 1, (120, 92, 62))
    for _ in range(3):
        x, y = rng.randrange(2, T - 8), rng.randrange(2, T - 2)
        for i in range(rng.randrange(3, 7)):
            cv.set(x + i, y, shade(P.DIRT, 0.82))
    return cv


def flagstone(seed):
    rng = random.Random(seed)
    cv = Canvas(T, T, P.MORTAR)
    rows = [(0, 10), (10, 11), (21, 11)]
    for y0, h in rows:
        # slab cuts always end exactly at the tile edge so the pattern tiles seamlessly
        cuts = [0]
        acc = 0
        while True:
            acc += rng.randrange(9, 15)
            if acc >= T - 5:
                break
            cuts.append(acc)
        cuts.append(T)
        for i in range(len(cuts) - 1):
            x0, x1 = cuts[i], cuts[i + 1] - 1
            if x1 - x0 < 5 and i > 0:
                continue
            base = shade(P.LIMESTONE, rng.choice([0.93, 0.97, 1.0, 1.04, 1.07]))
            cv.rect(x0 + 1, y0 + 1, x1 - 1, y0 + h - 2, base)
            cv.hline(x0 + 1, x1 - 1, y0 + 1, shade(base, 1.1))
            cv.hline(x0 + 1, x1 - 1, y0 + h - 2, shade(base, 0.86))
            for _ in range(3):
                cv.set(rng.randrange(x0 + 2, max(x0 + 3, x1 - 1)), rng.randrange(y0 + 2, y0 + h - 2),
                       shade(base, 0.9))
    return cv


def sand(seed):
    rng = random.Random(seed)
    cv = Canvas(T, T, P.SAND)
    _noise(cv, rng, P.SAND, 120, (0.93, 0.96, 1.04, 1.07))
    for _ in range(3):
        x, y = rng.randrange(0, T - 10), rng.randrange(2, T - 2)
        for i in range(rng.randrange(5, 10)):
            cv.set(x + i, y + (1 if i % 5 == 4 else 0), shade(P.SAND, 0.92))
    return cv


def water(seed):
    rng = random.Random(seed)
    cv = Canvas(T, T, P.WATER)
    _noise(cv, rng, P.WATER, 80, (0.92, 0.96, 1.06))
    for row in range(4):
        y = 3 + row * 8 + rng.randrange(-1, 2)
        x = rng.randrange(0, T - 8)
        ln = rng.randrange(4, 8)
        cv.hline(x, x + ln, y, P.WATER_LIGHT)
        cv.hline(x + 1, x + ln + 1, y + 1, shade(P.WATER, 0.85))
    return cv


def cliff(seed):
    rng = random.Random(seed)
    cv = Canvas(T, T, shade(P.ROCK, 0.82))
    _noise(cv, rng, P.ROCK, 90, (0.82, 0.9, 1.08))
    for _ in range(5):
        cx, cy = rng.randrange(2, T - 2), rng.randrange(3, T - 2)
        rx, ry = rng.randrange(5, 9), rng.randrange(4, 7)
        cv.ellipse(cx, cy + 1, rx, ry, shade(P.ROCK, 0.66))
        cv.ellipse(cx, cy, rx, ry, shade(P.ROCK, rng.choice([0.98, 1.05, 1.12])))
        cv.ellipse(cx - 1, cy - 1, rx - 2, ry - 2, shade(P.ROCK, 1.2))
    return cv


def field(seed):
    rng = random.Random(seed)
    base = (118, 88, 60)
    cv = Canvas(T, T, base)
    _noise(cv, rng, base, 60, (0.9, 1.08))
    for y0 in range(0, T, 8):
        cv.hline(0, T - 1, y0 + 5, (84, 60, 40))
        cv.hline(0, T - 1, y0 + 6, (84, 60, 40))
        cv.hline(0, T - 1, y0 + 2, (142, 108, 74))
        for x in range(2 + rng.randrange(0, 3), T, 6):
            cv.set(x, y0 + 1, (110, 140, 70))
            cv.set(x, y0, (136, 168, 84))
    return cv


def _wall_base(seed):
    rng = random.Random(seed)
    cv = Canvas(T, T, P.LIMESTONE)
    for ri, y0 in enumerate(range(0, T, 8)):
        x = -rng.randrange(0, 9) if ri % 2 else 0
        while x < T:
            w = rng.randrange(10, 15)
            base = shade(P.LIMESTONE, rng.choice([0.94, 0.98, 1.0, 1.04, 1.07]))
            cv.rect(x, y0, x + w - 2, y0 + 6, base)
            cv.hline(x, x + w - 2, y0, shade(base, 1.1))
            cv.hline(x, x + w - 2, y0 + 6, shade(base, 0.88))
            cv.vline(x + w - 1, y0, y0 + 7, P.MORTAR)
            x += w
        cv.hline(0, T - 1, y0 + 7, P.MORTAR)
    # shade under the roof lip and at the foot of the wall
    for x in range(T):
        for y in (0, 1):
            p = cv.get(x, y)
            cv.set(x, y, shade(p, 0.82 if y == 0 else 0.92))
        for y in (30, 31):
            p = cv.get(x, y)
            cv.set(x, y, shade(p, 0.84))
    return cv


def wall_stone(seed):
    return _wall_base(seed)


def wall_window(seed):
    cv = _wall_base(seed)
    cv.rect(9, 6, 22, 7, P.LIMESTONE_LIGHT)
    cv.rect(11, 8, 20, 21, (44, 34, 30))
    cv.rect(11, 8, 20, 9, (30, 22, 20))
    cv.vline(15, 8, 21, P.WOOD)
    cv.vline(16, 8, 21, P.WOOD_DARK)
    cv.hline(11, 20, 14, P.WOOD)
    cv.rect(9, 22, 22, 23, P.LIMESTONE_LIGHT)
    cv.hline(9, 22, 24, shade(P.LIMESTONE, 0.7))
    return cv


def wall_door(seed):
    cv = _wall_base(seed)
    cv.rect(8, 3, 23, 5, P.LIMESTONE_LIGHT)  # lintel
    cv.hline(8, 23, 6, shade(P.LIMESTONE, 0.72))
    cv.rect(9, 7, 22, 31, (40, 30, 26))  # doorway
    for x in range(10, 22):
        cv.vline(x, 8, 31, P.WOOD if (x % 3) else P.WOOD_DARK)
    cv.hline(10, 21, 8, P.WOOD_LIGHT)
    cv.rect(10, 18, 21, 19, P.WOOD_DARK)  # crossbar
    cv.set(19, 20, (200, 190, 150))  # handle
    cv.set(19, 21, (140, 130, 100))
    cv.hline(8, 23, 31, shade(P.LIMESTONE, 0.7))  # threshold
    return cv


def roof(edges, seed):
    rng = random.Random(seed)
    cv = Canvas(T, T, P.PLASTER_ROOF)
    for y in range(T):
        f = rng.choice([0.96, 1.0, 1.0, 1.04])
        for x in range(T):
            cv.set(x, y, shade(P.PLASTER_ROOF, f * rng.choice([0.98, 1.0, 1.02])))
    rim = P.LIMESTONE_LIGHT
    lip = shade(P.LIMESTONE, 0.78)
    inner = shade(P.PLASTER_ROOF, 0.82)
    if "t" in edges:
        cv.rect(0, 0, T - 1, 4, rim)
        cv.hline(0, T - 1, 5, inner)
    if "b" in edges:
        cv.rect(0, T - 5, T - 1, T - 1, rim)
        cv.hline(0, T - 1, T - 6, inner)
        cv.hline(0, T - 1, T - 1, lip)
    if "l" in edges:
        cv.rect(0, 0, 3, T - 1, rim)
        cv.vline(4, 0, T - 1, inner)
    if "r" in edges:
        cv.rect(T - 4, 0, T - 1, T - 1, rim)
        cv.vline(T - 5, 0, T - 1, inner)
    return cv


def _grass_band(seed, horizontal):
    cv = grass(seed)
    stone = P.LIMESTONE
    if horizontal:
        cv.rect(0, 14, T - 1, 26, shade(P.GRASS, 0.55))  # cast shadow
        cv.rect(0, 9, T - 1, 12, P.LIMESTONE_LIGHT)
        cv.rect(0, 13, T - 1, 23, stone)
        for x in range(0, T, 11):
            cv.vline(x, 13, 23, P.MORTAR)
            cv.vline((x + 5) % T, 18, 23, P.MORTAR)
        cv.hline(0, T - 1, 17, P.MORTAR)
        cv.hline(0, T - 1, 23, shade(stone, 0.78))
    else:
        cv.rect(12, 0, 25, T - 1, shade(P.GRASS, 0.55))
        cv.rect(9, 0, 12, T - 1, P.LIMESTONE_LIGHT)
        cv.rect(13, 0, 21, T - 1, stone)
        for y in range(0, T, 11):
            cv.hline(13, 21, y, P.MORTAR)
        cv.vline(17, 0, T - 1, P.MORTAR)
        cv.vline(21, 0, T - 1, shade(stone, 0.78))
    return cv


def build_all():
    tiles = []  # (name, canvas, solid)
    for i in range(3):
        tiles.append((f"grass_{i}", grass(100 + i), False))
    tiles.append(("grass_flowers", grass(110, flowers=True), False))
    tiles.append(("grass_dry_0", grass(120, P.GRASS_DRY), False))
    tiles.append(("grass_dry_1", grass(121, P.GRASS_DRY), False))
    for i in range(2):
        tiles.append((f"dirt_{i}", dirt(200 + i), False))
    for i in range(2):
        tiles.append((f"path_{i}", flagstone(300 + i), False))
    for i in range(2):
        tiles.append((f"sand_{i}", sand(400 + i), False))
    for i in range(2):
        tiles.append((f"water_{i}", water(500 + i), True))
    for i in range(2):
        tiles.append((f"cliff_{i}", cliff(600 + i), True))
    for i in range(2):
        tiles.append((f"field_{i}", field(700 + i), False))
    tiles.append(("wall_stone", wall_stone(800), True))
    tiles.append(("wall_stone_b", wall_stone(801), True))
    tiles.append(("wall_window", wall_window(802), True))
    tiles.append(("wall_door", wall_door(803), True))
    tiles.append(("lowwall_h", _grass_band(810, True), True))
    tiles.append(("lowwall_v", _grass_band(811, False), True))
    for name, edges in (("tl", "tl"), ("t", "t"), ("tr", "tr"), ("l", "l"), ("c", ""),
                        ("r", "r"), ("bl", "bl"), ("b", "b"), ("br", "br")):
        tiles.append((f"roof_{name}", roof(set(edges), 900 + len(tiles)), True))
    return tiles


def write(out_dir):
    tiles = build_all()
    cols = 8
    rows = (len(tiles) + cols - 1) // cols
    atlas = Canvas(cols * T, rows * T)
    meta = {"tile_size": T, "columns": cols, "tiles": {}, "solid": []}
    for i, (name, cv, solid) in enumerate(tiles):
        cx, cy = i % cols, i // cols
        atlas.blit(cv, cx * T, cy * T)
        meta["tiles"][name] = [cx, cy]
        if solid:
            meta["solid"].append(name)
    atlas.save(os.path.join(out_dir, "terrain.png"))
    with open(os.path.join(out_dir, "terrain.json"), "w") as f:
        json.dump(meta, f, indent=1)
    return atlas


if __name__ == "__main__":
    write(os.path.join(os.path.dirname(__file__), "..", "..", "assets", "tiles"))
