"""Builds the placeholder settlement maps (Cana, Magdala): enterable local maps of the same scale as every other map.

Run from the project root:  python -I tools/mapgen/settlements.py

These are PLACEHOLDERS: a low-walled ring of houses round a plaza, a well and a few stalls, with gates that match the ones drawn
in the surrounding countryside (tools/mapgen/world.py). Real streets, people and stories come later. Each map's `world`
entry is the exact footprint it occupies in the continuous world, so a gate has the same coordinates on both sides.
"""
import json
import os
import random

HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "..", "..", "data", "regions")
TERRAIN = json.load(open(os.path.join(HERE, "..", "..", "assets", "tiles", "terrain.json")))
PROPS = json.load(open(os.path.join(HERE, "..", "..", "assets", "props", "props.json")))
SOLID_TILES = set(TERRAIN["solid"])
W, H = 40, 28
LEGEND = {
    "g": ["grass_0", "grass_0", "grass_0", "grass_1", "grass_1", "grass_2", "grass_2", "grass_2", "grass_1", "grass_flowers"],
    "h": ["grass_dry_0", "grass_dry_1"], "d": ["dirt_0", "dirt_1"], "p": ["path_0", "path_1"],
    "s": ["sand_0", "sand_1"], "w": ["water_0", "water_1"], "c": ["cliff_0", "cliff_1"], "f": ["field_0", "field_1"],
}
SOLID_CHARS = {k for k, v in LEGEND.items() if v[0] in SOLID_TILES}


class Local:
    def __init__(self, rid, name, loc, world, seed):
        self.id, self.name, self.loc, self.world = rid, name, loc, world
        self.rng = random.Random(seed)
        self.g = [["g"] * W for _ in range(H)]
        self.objects, self.props, self.interactables = [], [], []
        self.entries, self.exits = {}, []
        self.occupied = set()
        self.ring = {}

    def fill(self, x0, y0, x1, y1, ch):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < W and 0 <= y < H:
                    self.g[y][x] = ch

    def occupy(self, x0, y0, x1, y1, pad=0):
        for y in range(y0 - pad, y1 + pad + 1):
            for x in range(x0 - pad, x1 + pad + 1):
                self.occupied.add((x, y))

    def border(self):
        """The same low wall ring the countryside shows round the village (tools/mapgen/world.py copies this map's
        ground, wall ring and houses, so the village looks the same from outside and inside)."""
        self.ring = {}
        for x in range(W):
            for y in (0, H - 1):
                self.ring[(x, y)] = "lowwall_h"
        for y in range(1, H - 1):
            for x in (0, W - 1):
                self.ring[(x, y)] = "lowwall_v"

    def gate(self, side, a, b):
        """An opening in the wall ring with a stone post either side. side n/s/e/w, a..b along the wall."""
        if side in ("w", "e"):
            x = (0, 1, 2) if side == "w" else (W - 3, W - 2, W - 1)
            self.fill(min(x), a, max(x), b, "d")
            wall = [(0 if side == "w" else W - 1, k) for k in range(a - 1, b + 2)]
        else:
            y = (0, 1, 2) if side == "n" else (H - 3, H - 2, H - 1)
            self.fill(a, min(y), b, max(y), "d")
            wall = [(k, 0 if side == "n" else H - 1) for k in range(a - 1, b + 2)]
        for t in wall:
            self.ring[t] = "wall_stone" if t in (wall[0], wall[-1]) else None

    def finish_ring(self):
        for (x, y), name in self.ring.items():
            if name:
                self.objects.append([x, y, name])

    def house(self, x, y, w, rh, door_dx, windows=()):
        for ry in range(rh):
            for rx in range(w):
                row = "t" if ry == 0 else ("b" if ry == rh - 1 else "")
                col = "l" if rx == 0 else ("r" if rx == w - 1 else "")
                name = {("t", "l"): "tl", ("t", ""): "t", ("t", "r"): "tr", ("", "l"): "l", ("", ""): "c",
                        ("", "r"): "r", ("b", "l"): "bl", ("b", ""): "b", ("b", "r"): "br"}[(row, col)]
                self.objects.append([x + rx, y + ry, "roof_" + name])
        wy = y + rh
        for rx in range(w):
            tile = "wall_door" if rx == door_dx else ("wall_window" if rx in windows else self.rng.choice(["wall_stone", "wall_stone_b"]))
            self.objects.append([x + rx, wy, tile])
        self.occupy(x, y, x + w - 1, wy, 1)
        return (x + door_dx, wy)

    def prop(self, name, x, y, block=True, pad=0):
        if (x, y) in self.occupied or self.g[y][x] not in ("g", "h", "d", "p"):
            return False
        if name in ("olive_tree_a", "olive_tree_b", "cypress") and self.g[y][x] not in ("g", "h"):
            return False
        self.props.append({"prop": name, "tile": [x, y]})
        if block:
            self.occupy(x, y, x, y, pad)
        return True

    def blocked(self):
        b = {(x, y) for y in range(H) for x in range(W) if self.g[y][x] in SOLID_CHARS}
        b |= {(o[0], o[1]) for o in self.objects if o[2] in SOLID_TILES}
        b |= {(p["tile"][0], p["tile"][1]) for p in self.props if PROPS[p["prop"]]["collider"] is not None}
        return b

    def write(self, spawn):
        self.finish_ring()
        b = self.blocked()
        start = (int(spawn[0]), int(spawn[1]))
        assert start not in b, f"{self.id}: spawn blocked"
        seen, q = {start}, [start]
        while q:
            cx, cy = q.pop()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (cx + dx, cy + dy)
                if 0 <= n[0] < W and 0 <= n[1] < H and n not in b and n not in seen:
                    seen.add(n)
                    q.append(n)
        for nm, e in self.entries.items():
            assert (e["tile"][0], e["tile"][1]) in seen, f"{self.id}: entry {nm} unreachable"
        for ex in self.exits:
            r = ex["rect"]
            assert any((x, y) in seen for x in range(r[0], r[0] + r[2]) for y in range(r[1], r[1] + r[3])), f"{self.id}: exit {ex['id']} unreachable"
        for it in self.interactables:
            t = (int(it["tile"][0]), int(it["tile"][1]))
            assert any((t[0] + dx, t[1] + dy) in seen for dx in range(-2, 3) for dy in range(-2, 3)), f"{self.id}: {it['name']} unreachable"
        for p in self.props:
            if p["prop"] in ("olive_tree_a", "olive_tree_b", "cypress"):
                assert self.g[p["tile"][1]][p["tile"][0]] in ("g", "h"), f"{self.id}: tree on bad ground"
        d = {
            "id": self.id, "name": self.name, "kind": "local", "anchor": self.loc, "placeholder": True, "origin": "fiction",
            "note": "PLACEHOLDER settlement map: a walled ring of houses, a plaza and a well. Real streets, people and stories are not built yet.",
            "world": self.world, "size": [W, H], "spawn": spawn,
            "entries": self.entries, "exits": self.exits,
            "ground": ["".join(r) for r in self.g], "ground_legend": LEGEND,
            "objects": self.objects, "props": self.props, "npcs": [], "interactables": self.interactables,
        }
        with open(os.path.join(OUT, self.id + ".json"), "w") as f:
            json.dump(d, f, indent=1)
        print("wrote", self.id, "(placeholder)", f"{len(self.props)} props")


def layout(m, plaza=(14, 9, 25, 18), houses=()):
    m.border()
    m.fill(*plaza, "p")
    m.occupy(*plaza)
    for (x, y, w, rh, door, win) in houses:
        d = m.house(x, y, w, rh, door, win)
        m.fill(d[0], d[1] + 1, d[0], d[1] + 2, "d")
        m.occupy(d[0], d[1] + 1, d[0], d[1] + 2)
    m.prop("well", 19, 13)
    m.occupy(18, 12, 21, 14)


def cana():
    m = Local("cana", "Cana of Galilee", "cana", [-132, 52], 4101)
    layout(m, houses=[(4, 5, 5, 3, 2, (0, 4)), (11, 4, 5, 3, 2, (4,)), (24, 4, 6, 3, 3, (1,)), (32, 6, 5, 3, 1, (3,)),
                      (4, 19, 6, 3, 2, (0, 4)), (28, 19, 5, 3, 2, (0,))])
    m.gate("n", 18, 21)
    # lane from the gate to the plaza
    m.fill(18, 2, 21, 8, "d")
    m.occupy(18, 2, 21, 8)
    m.prop("market_stall", 27, 14)
    m.occupy(25, 13, 30, 15)
    for gx, gy in ((12, 20), (16, 22), (24, 22), (36, 22), (3, 14)):
        m.prop("olive_tree_a" if gx % 2 else "olive_tree_b", gx, gy)
    for nm, x, y in (("jar_large", 15, 18), ("basket", 24, 12), ("crate", 26, 17)):
        m.prop(nm, x, y)
    m.entries = {"gate_north": {"tile": [18, 2], "span": 3, "axis": "x", "facing": "down"}, "arrival": {"tile": [20, 6], "facing": "down"}}
    m.exits = [{"id": "north_gate", "rect": [18, 0, 4, 1], "to": {"region": "cana_approach", "entry": "from_cana_gate"}, "facing": "up"}]
    m.interactables = [
        {"type": "examine", "name": "Cana of Galilee (placeholder)", "tile": [20.5, 8.5], "radius": 40,
         "text": ["Cana of Galilee. A village of flat-roofed houses round a small plaza and a well.",
                  "[Placeholder settlement. Its streets, people and stories are not built yet.]"]},
        {"type": "examine", "name": "The well", "tile": [19.5, 13.7], "radius": 36,
         "text": ["A stone well with a worn curb. The water is cool and sweet."]},
    ]
    m.write([20.5, 6.5])


def magdala():
    m = Local("magdala", "Magdala", "magdala", [166, -126], 4102)
    layout(m, houses=[(5, 4, 5, 3, 2, (0,)), (12, 4, 6, 3, 3, (1, 5)), (24, 4, 5, 3, 2, (4,)), (31, 5, 5, 3, 1, (3,)),
                      (5, 19, 6, 3, 2, (0, 5)), (26, 19, 6, 3, 3, (1,))])
    m.gate("w", 12, 15)
    m.gate("e", 12, 15)
    m.fill(2, 12, 13, 15, "d")
    m.fill(26, 12, 37, 15, "d")
    m.occupy(2, 12, 13, 15)
    m.occupy(26, 12, 37, 15)
    m.prop("market_stall", 19, 21)
    m.occupy(17, 20, 22, 22)
    for gx, gy in ((12, 23), (23, 8), (35, 22), (3, 21)):
        m.prop("olive_tree_a" if gx % 2 else "olive_tree_b", gx, gy)
    for nm, x, y in (("jar_large", 15, 19), ("basket", 24, 12), ("crate", 25, 19), ("basket", 30, 16)):
        m.prop(nm, x, y)
    m.entries = {"gate_west": {"tile": [3, 12], "span": 3, "axis": "y", "facing": "right"},
                 "gate_east": {"tile": [37, 12], "span": 3, "axis": "y", "facing": "left"},
                 "arrival": {"tile": [6, 13], "facing": "right"}}
    m.exits = [{"id": "west_gate", "rect": [0, 12, 1, 4], "to": {"region": "magdala_shore", "entry": "from_magdala_west"}, "facing": "left"},
               {"id": "east_gate", "rect": [39, 12, 1, 4], "to": {"region": "magdala_shore", "entry": "from_magdala_east"}, "facing": "right"}]
    m.interactables = [
        {"type": "examine", "name": "Magdala (placeholder)", "tile": [20.5, 11.2], "radius": 40,
         "text": ["Magdala, a lake town where fish are salted and carried inland. Drying racks stand between the houses.",
                  "[Placeholder settlement. Its streets, people and stories are not built yet.]"]},
        {"type": "examine", "name": "The well", "tile": [19.5, 13.7], "radius": 36,
         "text": ["A stone well with a worn curb."]},
    ]
    m.write([6.5, 13.5])


if __name__ == "__main__":
    cana()
    magdala()
