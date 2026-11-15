"""Builds the W1 regions: galilee_hills, magdala_shore, and the template regions road_camp and outskirts.

Run from the project root:  python -I tools/mapgen/galilee.py
Each region is an ASCII ground grid plus explicit objects, props, NPCs, interactables, entries and exits.
Every exit, entry, NPC and interactable is checked for reachability before anything is written.
"""
import json
import math
import os
import random

HERE = os.path.dirname(__file__)
OUT = os.path.join(HERE, "..", "..", "data", "regions")

TERRAIN = json.load(open(os.path.join(HERE, "..", "..", "assets", "tiles", "terrain.json")))
PROPS = json.load(open(os.path.join(HERE, "..", "..", "assets", "props", "props.json")))
SOLID_TILES = set(TERRAIN["solid"])

LEGEND = {
    "g": ["grass_0", "grass_0", "grass_0", "grass_1", "grass_1", "grass_2", "grass_2", "grass_2", "grass_1", "grass_flowers"],
    "h": ["grass_dry_0", "grass_dry_1"],
    "d": ["dirt_0", "dirt_1"],
    "p": ["path_0", "path_1"],
    "s": ["sand_0", "sand_1"],
    "w": ["water_0", "water_1"],
    "c": ["cliff_0", "cliff_1"],
    "f": ["field_0", "field_1"],
}
SOLID_CHARS = {k for k, v in LEGEND.items() if v[0] in SOLID_TILES}


class Region:
    def __init__(self, rid, name, w, h, seed, **meta):
        self.id, self.name, self.w, self.h = rid, name, w, h
        self.rng = random.Random(seed)
        self.ground = [["g"] * w for _ in range(h)]
        self.objects, self.props, self.npcs, self.interactables = [], [], [], []
        self.entries, self.exits = {}, []
        self.occupied = set()
        self.meta = meta
        self.spawn = [w / 2, h / 2]

    # -- drawing -------------------------------------------------------------------------------
    def fill(self, x0, y0, x1, y1, ch):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if 0 <= x < self.w and 0 <= y < self.h:
                    self.ground[y][x] = ch

    def occupy(self, x0, y0, x1, y1, pad=0):
        for y in range(y0 - pad, y1 + pad + 1):
            for x in range(x0 - pad, x1 + pad + 1):
                self.occupied.add((x, y))

    def road(self, pts, width=3, ch="d"):
        """A road through waypoints; every tile within width/2 of the polyline."""
        r = (width - 1) / 2.0
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            steps = int(max(abs(bx - ax), abs(by - ay)) * 2) + 1
            for i in range(steps + 1):
                t = i / steps
                cx, cy = ax + (bx - ax) * t, ay + (by - ay) * t
                for y in range(int(cy - r - 1), int(cy + r + 2)):
                    for x in range(int(cx - r - 1), int(cx + r + 2)):
                        if math.hypot(x - cx, y - cy) <= r + 0.5 and 0 <= x < self.w and 0 <= y < self.h:
                            self.ground[y][x] = ch
                            self.occupied.add((x, y))

    def border(self, thick=2, jitter=0.45):
        w, h = self.w, self.h
        self.fill(0, 0, w - 1, thick - 1, "c")
        self.fill(0, h - thick, w - 1, h - 1, "c")
        self.fill(0, 0, thick - 1, h - 1, "c")
        self.fill(w - thick, 0, w - 1, h - 1, "c")
        for x in range(thick, w - thick):
            for y in (thick, h - thick - 1):
                if self.rng.random() < jitter:
                    self.ground[y][x] = "c"
        for y in range(thick, h - thick):
            for x in (thick, w - thick - 1):
                if self.rng.random() < jitter:
                    self.ground[y][x] = "c"

    def ridge(self, x0, y0, x1, y1):
        """A rocky outcrop with a ragged edge: a barrier the player must walk around."""
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                edge = x in (x0, x1) or y in (y0, y1)
                if not edge or self.rng.random() < 0.6:
                    self.ground[y][x] = "c"
        self.occupy(x0, y0, x1, y1, 1)

    def dry_patches(self, n):
        for _ in range(n):
            cx, cy = self.rng.randrange(4, self.w - 4), self.rng.randrange(4, self.h - 4)
            for yy in range(cy - 1, cy + 2):
                for xx in range(cx - 2, cx + 3):
                    if self.ground[yy][xx] == "g" and self.rng.random() < 0.8:
                        self.ground[yy][xx] = "h"

    def prop(self, name, x, y, block=True, pad=0):
        self.props.append({"prop": name, "tile": [x, y]})
        if block:
            self.occupy(x, y, x, y, pad)

    def scatter(self, n, kinds, margin=3):
        cells = [(x, y) for y in range(margin, self.h - margin) for x in range(margin, self.w - margin)
                 if self.ground[y][x] in ("g", "h") and (x, y) not in self.occupied]
        self.rng.shuffle(cells)
        placed = 0
        for x, y in cells:
            if placed >= n:
                break
            if (x, y) in self.occupied:
                continue
            kind = self.rng.choice(kinds)
            solid = PROPS[kind]["collider"] is not None
            self.prop(kind, x, y, block=solid, pad=1 if solid else 0)
            placed += 1

    def house(self, x, y, w, rh, door_dx, windows=()):
        for ry in range(rh):
            for rx in range(w):
                row = "t" if ry == 0 else ("b" if ry == rh - 1 else "")
                col = "l" if rx == 0 else ("r" if rx == w - 1 else "")
                name = {("t", "l"): "tl", ("t", ""): "t", ("t", "r"): "tr", ("", "l"): "l", ("", ""): "c",
                        ("", "r"): "r", ("b", "l"): "bl", ("b", ""): "b", ("b", "r"): "br"}[(row, col)]
                self.objects.append([x + rx, y + ry, f"roof_{name}"])
        wy = y + rh
        for rx in range(w):
            tile = "wall_door" if rx == door_dx else ("wall_window" if rx in windows else self.rng.choice(["wall_stone", "wall_stone_b"]))
            self.objects.append([x + rx, wy, tile])
        self.occupy(x, y, x + w - 1, wy, 1)
        return (x + door_dx, wy)

    # -- checks and output ---------------------------------------------------------------------
    def blocked(self):
        b = set()
        for y in range(self.h):
            for x in range(self.w):
                if self.ground[y][x] in SOLID_CHARS:
                    b.add((x, y))
        for o in self.objects:
            if o[2] in SOLID_TILES:
                b.add((o[0], o[1]))
        for p in self.props:
            if PROPS[p["prop"]]["collider"] is not None:
                b.add((p["tile"][0], p["tile"][1]))
        return b

    def reach(self, start):
        b = self.blocked()
        start = (int(start[0]), int(start[1]))
        assert start not in b, f"{self.id}: start {start} is blocked"
        seen = {start}
        q = [start]
        while q:
            cx, cy = q.pop()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (cx + dx, cy + dy)
                if 0 <= n[0] < self.w and 0 <= n[1] < self.h and n not in b and n not in seen:
                    seen.add(n)
                    q.append(n)
        return seen

    def verify(self):
        seen = self.reach(self.spawn)
        for eid, e in self.entries.items():
            assert (int(e["tile"][0]), int(e["tile"][1])) in seen, f"{self.id}: entry {eid} unreachable"
        for e in self.exits:
            rx, ry, rw, rh = e["rect"]
            assert any((x, y) in seen for x in range(rx, rx + rw) for y in range(ry, ry + rh)), f"{self.id}: exit {e['id']} unreachable"
        for n in self.npcs:
            assert (int(n["tile"][0]), int(n["tile"][1])) in seen, f"{self.id}: npc {n['id']} unreachable"
        for i in self.interactables:
            t = (int(i["tile"][0]), int(i["tile"][1]))
            near = any((t[0] + dx, t[1] + dy) in seen for dx in range(-2, 3) for dy in range(-2, 3))
            assert near, f"{self.id}: interactable {i.get('name')} unreachable"

    def write(self):
        self.verify()
        d = {
            "id": self.id, "name": self.name, **self.meta,
            "size": [self.w, self.h], "spawn": self.spawn,
            "entries": self.entries, "exits": self.exits,
            "ground": ["".join(r) for r in self.ground], "ground_legend": LEGEND,
            "objects": self.objects, "props": self.props, "npcs": self.npcs, "interactables": self.interactables,
        }
        path = os.path.join(OUT, self.id + ".json")
        with open(path, "w") as f:
            json.dump(d, f, indent=1)
        print("wrote", self.id, f"{self.w}x{self.h}", f"{len(self.props)} props", f"{len(self.npcs)} npcs")


# ================================================================================================
# galilee_hills: the countryside between Kefar Zayit and the lake
# ================================================================================================
def galilee_hills():
    r = Region("galilee_hills", "The hills above the lake", 64, 44, 61, kind="regional", anchor="kefar_zayit", origin="fiction",
               note="An invented stretch of lower-Galilean countryside on the way from Kefar Zayit to Magdala.")
    r.border()
    r.dry_patches(18)
    # the stream: a spring in the northern cliffs, wandering south to the cliffs below
    def sx(y):
        return 20 + round(2 * math.sin(y / 4.0))
    for y in range(2, r.h - 2):
        for x in range(sx(y) - 2, sx(y) + 3):
            r.ground[y][x] = "s"
        for x in range(sx(y) - 1, sx(y) + 1):
            r.ground[y][x] = "w"
    # main road, west to east, with a stone ford where it crosses the stream
    main = [(0, 22), (8, 22), (14, 21), (24, 20), (30, 21), (36, 21), (44, 23), (54, 23), (63, 22)]
    r.road(main, 3)
    for y in range(19, 24):
        for x in range(sx(y) - 2, sx(y) + 3):
            if r.ground[y][x] in ("w", "s"):
                r.ground[y][x] = "p"
    # branches: north to the shepherds' cairn, south to the spring grove
    r.road([(36, 21), (36, 14), (37, 9), (41, 6)], 2)
    r.road([(46, 24), (46, 31), (43, 36), (40, 38)], 2)
    # open the cliff at both ends of the road (the exits)
    r.fill(0, 21, 1, 24, "d")
    r.fill(62, 21, 63, 24, "d")
    # the cairn clearing
    r.fill(38, 4, 44, 8, "h")
    r.fill(40, 5, 42, 7, "p")
    # the spring pool
    r.fill(33, 40, 37, 41, "s")
    r.fill(34, 40, 36, 41, "w")
    # outcrops (elevation barriers) that the road and branches wind around
    r.ridge(4, 6, 15, 12)
    r.ridge(52, 29, 60, 35)
    r.ridge(24, 29, 30, 37)
    r.ridge(48, 7, 58, 12)
    r.occupy(0, 21, 63, 24)
    r.occupy(35, 4, 46, 21)

    # olive groves along the road
    for i, (gx, gy) in enumerate([(10, 18), (13, 26), (17, 17), (28, 25), (31, 17), (40, 26), (50, 19), (55, 26), (7, 27)]):
        r.prop("olive_tree_a" if i % 2 else "olive_tree_b", gx, gy)
        r.occupy(gx - 1, gy - 2, gx + 1, gy)
    for tx, ty in ((38, 4), (44, 5), (39, 9), (35, 12)):
        r.prop("cypress", tx, ty)
        r.occupy(tx - 1, ty - 1, tx + 1, ty)
    # the cairn itself is a heap of boulders on the paved spot, with a clear spot to stand beside it
    r.prop("boulder", 41, 5, block=True)
    r.prop("boulder", 42, 6, block=True)
    r.prop("signpost", 35, 19)
    r.scatter(46, ["bush", "bush", "bush_flowers", "boulder", "flowers_patch", "flowers_patch"])

    r.spawn = [36.5, 22.5]
    r.entries = {
        "from_village": {"tile": [3, 21], "span": 3, "axis": "y", "facing": "right"},
        "from_shore": {"tile": [60, 21], "span": 3, "axis": "y", "facing": "left"},
        "camp": {"tile": [34, 23], "facing": "down"},
    }
    r.exits = [
        {"id": "to_village", "rect": [0, 21, 1, 4], "to": {"region": "kefar_zayit", "entry": "from_hills"}, "facing": "left"},
        {"id": "to_shore", "rect": [63, 21, 1, 4], "to": {"region": "magdala_shore", "entry": "from_hills"}, "facing": "right"},
    ]
    r.interactables = [
        {"type": "waymark", "name": "Road marker", "tile": [35, 20], "radius": 34, "modes": ["land"],
         "text": ["A squared stone at the meeting of the roads, its top worn smooth by travelers' hands.",
                  "West, the road runs back to Kefar Zayit. East, it falls toward the lake and Magdala. From there, other roads lead on."]},
        {"type": "examine", "name": "The shepherds' cairn", "tile": [41, 7], "radius": 38, "landmark": "shepherds_cairn",
         "variants": [
             {"when": {"not_flag": "saw_cairn"},
              "text": ["A heap of fieldstones taller than a man, each one laid by a passing shepherd for luck or for a landmark.",
                       "From up here the land opens out. East, beyond the hills, the lake lies like a dropped blue coin. Smoke rises from the fishing towns on its shore."],
              "effects": [{"landmark": "shepherds_cairn"}, {"set_flag": "saw_cairn"},
                          {"reveal_place": {"place": "tiberias", "level": "discovered"}},
                          {"reveal_place": {"place": "capernaum", "level": "rumored"}}]},
             {"text": ["The shepherds' cairn. Someone has added a stone since you were last here."]},
         ]},
        {"type": "examine", "name": "The spring", "tile": [35, 39], "radius": 34,
         "text": ["A spring seeps from the foot of the rocks into a clear pool. The ground around it is trodden by sheep and, you think, by people who prefer not to be seen."]},
        {"type": "examine", "name": "The ford", "tile": [20, 21.5], "radius": 40,
         "text": ["Flat stones set across the stream where the road crosses. The water runs cold and fast underneath."]},
    ]
    r.npcs = [
        {"id": "hills_highwayman", "name": "Highwayman", "sprite": "highwayman", "profile": "highwayman", "dialogue": "",
         "encounter": "hills_highwayman", "tile": [41.5, 37.5], "wander": 0, "facing": "up",
         "when": {"time_of_day": {"from": 360, "to": 1080}}},
    ]
    r.write()


# ================================================================================================
# magdala_shore: the lake shore and landing outside Magdala
# ================================================================================================
def magdala_shore():
    r = Region("magdala_shore", "Magdala shore", 48, 34, 77, kind="regional", anchor="magdala", origin="documented",
               note="The shore road and landing just outside Magdala. Only the approach is modelled; the town itself is a later chapter.")
    r.border()
    r.dry_patches(8)
    # the lake: water down the east side, sand shore in front of it
    for y in range(2, r.h - 2):
        shore = 33 + round(1.5 * math.sin(y / 3.0))
        r.fill(shore - 2, y, shore, y, "s")
        r.fill(shore + 1, y, r.w - 3, y, "w")
    # lane from the hills to the landing, and the pier
    r.road([(0, 17), (10, 17), (20, 16), (31, 17)], 3)
    r.fill(0, 16, 1, 19, "d")
    r.fill(33, 17, 41, 18, "p")
    r.road([(20, 16), (20, 10)], 2)
    # houses on the rise above the lane (Magdala's edge)
    d1 = r.house(8, 5, 5, 2, 2, windows=(0, 4))
    d2 = r.house(15, 4, 6, 3, 3, windows=(1,))
    d3 = r.house(26, 5, 5, 2, 1, windows=(3,))
    for dx, dy in (d1, d2, d3):
        r.fill(dx, dy + 1, dx, 15, "d")
        r.occupy(dx, dy + 1, dx, 15)
    r.road([(0, 17), (10, 17)], 3)
    r.occupy(0, 15, 41, 19)
    # nets, jars and baskets at the landing
    for name, x, y in (("jar_large", 31, 14), ("basket", 30, 14), ("crate", 32, 20), ("basket", 31, 20), ("jar_large", 29, 21)):
        r.prop(name, x, y, pad=0)
    for i, (gx, gy) in enumerate([(5, 24), (10, 26), (16, 24), (23, 27), (4, 12)]):
        r.prop("olive_tree_a" if i % 2 else "olive_tree_b", gx, gy)
        r.occupy(gx - 1, gy - 2, gx + 1, gy)
    r.prop("signpost", 7, 16)
    r.scatter(24, ["bush", "bush_flowers", "boulder", "flowers_patch", "flowers_patch"])

    r.spawn = [6.5, 17.5]
    r.entries = {
        "from_hills": {"tile": [3, 16], "span": 3, "axis": "y", "facing": "right"},
        "arrival": {"tile": [28, 17], "span": 1, "axis": "y", "facing": "right"},
        "camp": {"tile": [27, 18], "facing": "down"},
    }
    r.exits = [{"id": "to_hills", "rect": [0, 16, 1, 4], "to": {"region": "galilee_hills", "entry": "from_shore"}, "facing": "left"}]
    r.interactables = [
        {"type": "waymark", "name": "Road marker", "tile": [7, 15], "radius": 34, "modes": ["land"],
         "text": ["A squared milestone. The road west climbs back into the hills; the lake road runs along the shore from here to Capernaum in one direction and Tiberias in the other."]},
        {"type": "waymark", "name": "The landing", "tile": [38, 16.2], "radius": 38, "modes": ["water"],
         "text": ["Boats are drawn up on the sand, and a few rest at the end of the pier, tarred and patched.", "Fishermen will carry a passenger across the water for a small fee, when the weather lets them."]},
        {"type": "examine", "name": "Magdala", "tile": [20, 10.5], "radius": 38,
         "text": ["The houses of Magdala run along the shore a little farther on, where the lane bends. Drying racks for salted fish stand between them.",
                  "[The town itself is not yet part of the road.]"]},
        {"type": "examine", "name": "The lake", "tile": [35, 24], "radius": 44,
         "text": ["The lake lies flat and bright. Across the water, the far hills are blue. A boat is working its way back with the wind behind it."]},
    ]
    r.write()


# ================================================================================================
# road_camp and outskirts: shared template regions used wherever no hand-built scene exists
# ================================================================================================
def road_camp():
    r = Region("road_camp", "Wayside camp: {place}", 30, 20, 91, kind="template", template=True,
               note="Shared by every journey stop that has no hand-built region.")
    r.border()
    r.fill(6, 6, 23, 14, "d")
    r.fill(8, 8, 21, 12, "h")
    r.fill(12, 9, 17, 11, "d")
    r.fill(0, 9, 5, 11, "d")
    r.fill(24, 9, 29, 11, "d")
    r.occupy(0, 6, 29, 14)
    r.prop("clay_oven", 14, 10)
    r.prop("signpost", 14, 7)
    for name, x, y in (("crate", 10, 8), ("basket", 19, 8), ("jar_large", 10, 12), ("crate", 19, 12)):
        r.prop(name, x, y)
    for tx, ty in ((4, 5), (26, 5), (4, 16), (25, 16)):
        r.prop("olive_tree_a", tx, ty)
        r.occupy(tx - 1, ty - 2, tx + 1, ty)
    r.scatter(14, ["bush", "bush_flowers", "boulder", "flowers_patch"], margin=3)
    r.spawn = [14.5, 12.5]
    r.entries = {"camp": {"tile": [14, 12], "facing": "down"}, "arrival": {"tile": [14, 12], "facing": "down"}}
    r.interactables = [
        {"type": "waymark", "name": "The road", "tile": [14, 7.6], "radius": 36, "modes": ["land"],
         "text": ["{place}. A trodden ring of earth where others have camped before you, a hearth of blackened stones, and the road running on past it in both directions."]},
        {"type": "examine", "name": "The hearth", "tile": [14, 10.9], "radius": 34,
         "variants": [
             {"when": {"sabbath": True},
              "text": ["It is the Sabbath. No one lights a fire; the ashes are cold, and the few travelers here sit quietly and wait for the sun to go down."]},
             {"text": ["The ashes are warm. It is a place travelers use again and again."]},
         ]},
    ]
    r.write()


def outskirts():
    r = Region("outskirts", "Outskirts of {place}", 34, 22, 113, kind="template", template=True,
               note="Shared arrival scene for any location that has no hand-built region yet.")
    r.border()
    r.fill(0, 10, 33, 12, "d")
    r.fill(14, 6, 22, 15, "p")
    r.fill(0, 10, 1, 12, "d")
    r.occupy(0, 6, 33, 15)
    for x in range(13, 24):
        r.objects.append([x, 3, "wall_stone"])
        r.objects.append([x, 2, "roof_b"])
    r.objects[:] = [o for o in r.objects if not (o[0] in (17, 18) and o[1] in (2, 3))]
    r.objects.append([17, 3, "wall_door"])
    r.objects.append([18, 3, "wall_door"])
    r.occupy(13, 2, 23, 3, 1)
    for tx, ty in ((6, 5), (28, 5), (6, 17), (28, 17)):
        r.prop("olive_tree_b", tx, ty)
        r.occupy(tx - 1, ty - 2, tx + 1, ty)
    r.prop("well", 21, 8)
    r.prop("signpost", 8, 9)
    r.scatter(18, ["bush", "bush_flowers", "boulder", "flowers_patch"], margin=3)
    r.spawn = [8.5, 11.5]
    r.entries = {"arrival": {"tile": [6, 11], "facing": "right"}, "camp": {"tile": [6, 11], "facing": "right"}}
    r.interactables = [
        {"type": "waymark", "name": "Road marker", "tile": [8, 9.2], "radius": 36, "modes": ["land", "water"],
         "text": ["You are on the approach to {place}. The roads you know lead on from here."]},
        {"type": "examine", "name": "The way into {place}", "tile": [17.5, 4.2], "radius": 44,
         "text": ["The gate of {place} stands before you; the sounds of people and animals drift out from within.",
                  "[The streets of {place} are not yet part of this journey. This is as far as the road goes for now.]"]},
        {"type": "examine", "name": "The well", "tile": [21, 8.7], "radius": 36,
         "text": ["A well with a stone curb, shared by everyone who comes to {place} by this road."]},
    ]
    r.write()


if __name__ == "__main__":
    galilee_hills()
    magdala_shore()
    road_camp()
    outskirts()
