"""Builds the continuous physical world: the regional maps and the placeholder settlement maps.

Run from the project root:  python -I tools/mapgen/world.py   (then python -I tools/mapgen/kefar_zayit.py is NOT needed)

The whole countryside is generated as ONE raster in world tile coordinates (x east, y south, Kefar Zayit's centre at 0,0;
one tile is 50 m of strategic distance), then cut into the region rectangles below. Roads, streams, outcrops and the lake
therefore continue across every shared boundary by construction. Edges that have no neighbour become cliff bands.
Settlements are footprints in the raster: each is a copy of its local map (wall ring, gates, houses).
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
TREES = {"olive_tree_a", "olive_tree_b", "cypress"}

# (id, name, x, y, w, h, extra)  -- world tile rectangles of the regional maps
REGIONS = [
    ("kefar_zayit_outskirts", "Around Kefar Zayit", -48, -36, 96, 72, {}),
    ("cana_road", "The Cana road", -112, -28, 64, 72, {}),
    ("cana_approach", "The approach to Cana", -176, 44, 128, 64, {"sights": [{"place": "cana", "level": "discovered"}]}),
    ("galilee_hills", "The hills above the lake", 48, -44, 64, 72, {}),
    ("hills_north", "The northern hills", 48, -116, 64, 72, {}),
    ("magdala_shore", "Magdala and the lake shore", 112, -140, 128, 72, {"sights": [{"place": "magdala", "level": "discovered"}]}),
]
# settlement footprints: id -> (x, y, w, h); the local map of the same size sits exactly here
FOOT = {"kefar_zayit": (-20, -14, 40, 28), "cana": (-132, 52, 40, 28), "magdala": (166, -126, 40, 28)}


class World:
    def __init__(self):
        self.rng = random.Random(1606)
        self.x0 = min(r[2] for r in REGIONS)
        self.y0 = min(r[3] for r in REGIONS)
        self.x1 = max(r[2] + r[4] for r in REGIONS)
        self.y1 = max(r[3] + r[5] for r in REGIONS)
        self.g = {}
        self.roads = set()
        self.objects = []  # [x, y, tile]
        self.props = []  # {prop, tile}
        self.occupied = set()
        self.noprop = set()

    # -- regions --------------------------------------------------------------------------------
    def region_at(self, x, y):
        for rid, _n, rx, ry, rw, rh, _e in REGIONS:
            if rx <= x < rx + rw and ry <= y < ry + rh:
                return rid
        return None

    def get(self, x, y):
        return self.g.get((x, y), "c")

    def put(self, x, y, ch):
        if self.region_at(x, y):
            self.g[(x, y)] = ch

    def fill(self, x0, y0, x1, y1, ch, only=None):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                if self.region_at(x, y) and (only is None or self.get(x, y) in only):
                    self.g[(x, y)] = ch

    # -- terrain --------------------------------------------------------------------------------
    def base(self):
        for _id, _n, rx, ry, rw, rh, _e in REGIONS:
            for y in range(ry, ry + rh):
                for x in range(rx, rx + rw):
                    self.g[(x, y)] = "g"
        for _ in range(60):
            cx = self.rng.randrange(self.x0 + 4, self.x1 - 4)
            cy = self.rng.randrange(self.y0 + 4, self.y1 - 4)
            for yy in range(cy - 1, cy + 2):
                for xx in range(cx - 3, cx + 4):
                    if self.get(xx, yy) == "g" and self.rng.random() < 0.8:
                        self.g[(xx, yy)] = "h"

    def ridge(self, x0, y0, x1, y1):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                edge = x in (x0, x1) or y in (y0, y1)
                if self.region_at(x, y) and (not edge or self.rng.random() < 0.6):
                    self.g[(x, y)] = "c"

    def stream(self, xf, y_from, y_to):
        for y in range(y_from, y_to + 1):
            cx = xf(y)
            for x in range(cx - 2, cx + 3):
                if self.get(x, y) in ("g", "h"):
                    self.put(x, y, "s")
            self.put(cx - 1, y, "w")
            self.put(cx, y, "w")

    def lake(self):
        rx, ry, rw, rh = 112, -140, 128, 72
        for y in range(ry, ry + rh):
            shore = 216 + round(1.5 * math.sin(y / 3.0))
            for x in range(shore - 2, shore + 1):
                self.put(x, y, "s")
            for x in range(shore + 1, rx + rw):
                self.put(x, y, "w")

    def road(self, pts, width=3):
        r = (width - 1) / 2.0
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            steps = int(max(abs(bx - ax), abs(by - ay)) * 2) + 1
            for i in range(steps + 1):
                t = i / steps
                cx, cy = ax + (bx - ax) * t, ay + (by - ay) * t
                for y in range(int(cy - r - 1), int(cy + r + 2)):
                    for x in range(int(cx - r - 1), int(cx + r + 2)):
                        if math.hypot(x - cx, y - cy) <= r + 0.5 and self.region_at(x, y):
                            self.g[(x, y)] = "p" if self.get(x, y) in ("w", "s", "p") else "d"
                            self.roads.add((x, y))

    def pond(self, cx, cy, rx, ry):
        for y in range(cy - ry - 1, cy + ry + 2):
            for x in range(cx - rx - 1, cx + rx + 2):
                d = ((x - cx) / (rx + 1.0)) ** 2 + ((y - cy) / (ry + 1.0)) ** 2
                if d <= 1.0 and self.region_at(x, y):
                    self.g[(x, y)] = "w" if d <= 0.45 else "s"

    # -- settlements ----------------------------------------------------------------------------
    def roof_block(self, x, y, w, h):
        for ry in range(h):
            for rx in range(w):
                row = "t" if ry == 0 else ("b" if ry == h - 1 else "")
                col = "l" if rx == 0 else ("r" if rx == w - 1 else "")
                name = {("t", "l"): "tl", ("t", ""): "t", ("t", "r"): "tr", ("", "l"): "l", ("", ""): "c",
                        ("", "r"): "r", ("b", "l"): "bl", ("b", ""): "b", ("b", "r"): "br"}[(row, col)]
                self.objects.append([x + rx, y + ry, "roof_" + name])

    def footprint(self, sid):
        """A village seen from outside: exactly its local map (ground, low wall ring with gates, houses, props) laid on
        the countryside, so nothing is invented that the inside does not have. Run the local generators first."""
        x, y, w, h = FOOT[sid]
        d = json.load(open(os.path.join(OUT, sid + ".json")))
        assert d["size"] == [w, h] and d["world"] == [x, y], f"{sid}: local map does not match its footprint"
        for ty, row in enumerate(d["ground"]):
            for tx, ch in enumerate(row):
                self.g[(x + tx, y + ty)] = ch
        for ox, oy, name in d["objects"]:
            self.objects.append([x + ox, y + oy, name])
        for p in d["props"]:
            self.props.append({"prop": p["prop"], "tile": [x + p["tile"][0], y + p["tile"][1]]})
        for tx in range(x, x + w):
            for ty in range(y, y + h):
                self.occupied.add((tx, ty))
                self.noprop.add((tx, ty))
        for tx in range(x - 2, x + w + 2):
            for ty in range(y - 2, y + h + 2):
                self.noprop.add((tx, ty))

    # -- the borders of the world ---------------------------------------------------------------
    def edge_bands(self):
        """Cliff bands stand wherever the world itself ends (no map beyond). They depend only on the world's outline,
        never on which map owns a tile, so they are identical on both sides of every seam."""
        def depth(x, y):
            return 1 + ((x * 7919 + y * 104729) % 7 < 4) + ((x * 31 + y * 17) % 5 == 0)
        for rid, _n, rx, ry, rw, rh, _e in REGIONS:
            for y in range(ry, ry + rh):
                for x in range(rx, rx + rw):
                    if (x, y) in self.roads:
                        continue
                    d = depth(x, y) + 1
                    near = False
                    for dy in range(-d, d + 1):
                        for dx in range(-d, d + 1):
                            if self.region_at(x + dx, y + dy) is None:
                                near = True
                    if near:
                        self.g[(x, y)] = "c"

    def seal_seams(self):
        """Where a cliff band reaches a seam on one side, it carries on over the seam, so no one steps from open ground into rock."""
        for _ in range(3):
            changed = False
            for (x, y), ch in list(self.g.items()):
                if ch != "c":
                    continue
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    n = (x + dx, y + dy)
                    if n in self.g and self.region_at(*n) != self.region_at(x, y) and self.g[n] not in ("c", "w") and n not in self.roads:
                        self.g[n] = "c"
                        changed = True
            if not changed:
                break

    # -- props ----------------------------------------------------------------------------------
    def prop(self, name, x, y, pad=0, force=False):
        if not force and ((x, y) in self.noprop or (x, y) in self.occupied):
            return False
        ch = self.get(x, y)
        if name in TREES and ch not in ("g", "h"):
            return False
        if ch in ("w", "c"):
            return False
        self.props.append({"prop": name, "tile": [x, y]})
        for yy in range(y - pad, y + pad + 1):
            for xx in range(x - pad, x + pad + 1):
                self.occupied.add((xx, yy))
        return True

    def near_open_boundary(self, x, y, margin=4):
        """True if (x, y) is within `margin` tiles of an edge that has a neighbour, so nothing is cut by the seam."""
        rid = self.region_at(x, y)
        if not rid:
            return True
        for dx in range(-margin, margin + 1):
            for dy in range(-margin, margin + 1):
                o = self.region_at(x + dx, y + dy)
                if o and o != rid:
                    return True
        return False

    def groves_and_scatter(self, roads):
        # olive trees in loose groups to either side of the roads
        for pts in roads:
            for (ax, ay), (bx, by) in zip(pts, pts[1:]):
                length = math.hypot(bx - ax, by - ay)
                n = int(length / 7)
                for i in range(n):
                    t = (i + self.rng.random()) / max(n, 1)
                    cx, cy = ax + (bx - ax) * t, ay + (by - ay) * t
                    nx, ny = -(by - ay) / length, (bx - ax) / length
                    side = self.rng.choice((-1, 1))
                    off = self.rng.uniform(4, 9)
                    for k in range(self.rng.randint(1, 3)):
                        px = int(cx + nx * side * off + self.rng.uniform(-3, 3))
                        py = int(cy + ny * side * off + self.rng.uniform(-3, 3))
                        if not self.near_open_boundary(px, py) and self.near_road(px, py) > 2:
                            self.prop(self.rng.choice(["olive_tree_a", "olive_tree_b"]), px, py, pad=1)
        cells = [(x, y) for (x, y), ch in self.g.items() if ch in ("g", "h") and (x, y) not in self.occupied and (x, y) not in self.noprop]
        self.rng.shuffle(cells)
        placed = 0
        for x, y in cells:
            if placed >= 520:
                break
            if self.near_open_boundary(x, y) or self.near_road(x, y) <= 1 or (x, y) in self.occupied:
                continue
            kind = self.rng.choice(["bush", "bush", "bush_flowers", "boulder", "flowers_patch", "flowers_patch", "flowers_patch"])
            solid = PROPS[kind]["collider"] is not None
            if self.prop(kind, x, y, pad=1 if solid else 0):
                placed += 1

    def near_road(self, x, y):
        best = 99
        for dx in range(-3, 4):
            for dy in range(-3, 4):
                if (x + dx, y + dy) in self.roads:
                    best = min(best, max(abs(dx), abs(dy)))
        return best

    # -- reachability ---------------------------------------------------------------------------
    def blocked(self):
        b = {(x, y) for (x, y), ch in self.g.items() if ch in SOLID_CHARS}
        for o in self.objects:
            if o[2] in SOLID_TILES:
                b.add((o[0], o[1]))
        for p in self.props:
            if PROPS[p["prop"]]["collider"] is not None:
                b.add((p["tile"][0], p["tile"][1]))
        return b

    def reach(self, start):
        b = self.blocked()
        assert start not in b, f"start {start} is blocked"
        seen = {start}
        q = [start]
        while q:
            cx, cy = q.pop()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (cx + dx, cy + dy)
                if n in self.g and n not in b and n not in seen:
                    seen.add(n)
                    q.append(n)
        return seen


# ================================================================================================
def build():
    w = World()
    w.base()
    # outcrops (barriers to walk round); roads are laid after, so a road always wins
    for r in [(-44, -34, -32, -26), (30, -32, 44, -24), (28, 24, 42, 32), (-44, 24, -30, 32),
              (-108, -24, -96, -10), (-72, -20, -56, -8), (-108, 12, -98, 28), (-70, 30, -56, 40),
              (-172, 48, -150, 62), (-70, 52, -54, 68), (-172, 92, -140, 104), (-92, 92, -56, 104), (-120, 90, -104, 100),
              (92, 4, 108, 20), (53, -40, 62, -28), (52, 14, 56, 26),
              (50, -112, 64, -100), (74, -112, 88, -98), (52, -62, 60, -50), (102, -92, 108, -80),
              (114, -136, 130, -120), (116, -74, 134, -69), (142, -138, 162, -126), (176, -84, 206, -72)]:
        w.ridge(*r)
    w.stream(lambda y: 100 + round(3 * math.sin(y / 10.0)), -116, 27)
    w.lake()
    w.pond(68, 21, 2, 1)

    roads = {
        "west": [(-20, 0), (-48, 3), (-70, 13), (-84, 30), (-96, 42), (-108, 48), (-112, 51)],
        "east": [(20, 0), (48, 0), (64, -6), (72, -20), (78, -34), (84, -44), (88, -64), (100, -72), (112, -80), (140, -96), (162, -110), (165, -112)],
        "cairn": [(78, -34), (72, -46), (68, -58), (66, -60)],
        "spring": [(56, 0), (58, 12), (62, 20), (64, 22)],
        "pier": [(206, -112), (216, -112)],
    }
    w.road(roads["west"], 3)
    w.road(roads["east"], 3)
    w.road(roads["cairn"], 2)
    w.road(roads["spring"], 2)
    w.road(roads["pier"], 3)
    # the pier into the lake
    w.fill(216, -113, 228, -112, "p")
    for x in range(216, 229):
        for y in (-113, -112):
            w.roads.add((x, y))
    # clearing round the cairn
    w.fill(63, -63, 69, -57, "h", only=("g", "h"))
    w.fill(65, -62, 67, -58, "p")

    # settlement footprints
    w.footprint("kefar_zayit")
    w.footprint("cana")
    w.footprint("magdala")
    for (cx, cy) in [(-21, 0), (20, 0), (-112, 51), (165, -112), (206, -112)]:
        w.roads.add((cx, cy))

    w.edge_bands()
    w.seal_seams()
    # a road must never run into a barrier
    for (x, y) in w.roads:
        assert w.get(x, y) in ("d", "p"), f"road tile {(x, y)} was overwritten by {w.get(x, y)}"

    # signs, then trees and scatter
    signs = {
        "kz_east": (24, -4), "kz_west": (-25, -4), "road_mid": (-70, 8), "cana_gate": (-118, 49),
        "hills_mid": (56, -7), "magdala_gate": (158, -115),
    }
    for (sx, sy) in signs.values():
        assert w.prop("signpost", sx, sy, pad=1, force=True)
    w.groves_and_scatter(list(roads.values()))
    for (cx, cy) in [(64, -62), (68, -62), (64, -57), (68, -57)]:
        w.prop("cypress", cx, cy, pad=1, force=True)
    w.prop("boulder", 66, -61, force=True)
    w.prop("boulder", 67, -60, force=True)
    for (cx, cy, nm) in [(214, -118, "jar_large"), (213, -106, "basket"), (212, -105, "crate"), (210, -119, "basket")]:
        w.prop(nm, cx, cy, force=True)

    entries_w, exits_w, inter_w, npcs_w = {}, [], [], []
    # gates between the countryside and the settlements (world coordinates; local maps use the same ones)
    gates = [
        ("kz_east", "kefar_zayit", (19, -2, 1, 4), "gate_east", "from_kz_east", (21, -2), 3, "y", "right"),
        ("kz_west", "kefar_zayit", (-20, -2, 1, 4), "gate_west", "from_kz_west", (-22, -2), 3, "y", "left"),
        ("cana_north", "cana", (-114, 52, 4, 1), "gate_north", "from_cana_gate", (-114, 50), 3, "x", "up"),
        ("magdala_west", "magdala", (166, -114, 1, 4), "gate_west", "from_magdala_west", (164, -114), 3, "y", "left"),
        ("magdala_east", "magdala", (205, -114, 1, 4), "gate_east", "from_magdala_east", (207, -114), 3, "y", "right"),
    ]
    for gid, local, rect, local_entry, outside_entry, tile, span, axis, facing in gates:
        exits_w.append({"id": gid, "rect": list(rect), "to": {"region": local, "entry": local_entry},
                        "facing": {"right": "right", "left": "left", "up": "up"}.get(facing, "up")})
        entries_w[outside_entry] = {"tile": list(tile), "span": span, "axis": axis, "facing": facing}

    markers = [
        ("Road marker", signs["kz_east"], {"place": "kefar_zayit"}, "East of the village the road forks toward the lake and the northern hills. West, it runs back through the gate. Other roads lead on from the places along them."),
        ("Road marker", signs["kz_west"], {"place": "kefar_zayit"}, "A squared stone beside the western gate. The road west bends south toward Cana of Galilee."),
        ("Road marker", signs["road_mid"], {"route": "cana__kefar_zayit__land", "at": 0.45}, "A squared milestone on the road between Kefar Zayit and Cana. Travelers who do not care to walk the whole way arrange passage on the long roads from here."),
        ("Road marker", signs["cana_gate"], {"place": "cana"}, "A squared stone by the road outside Cana. Ahead is the gate."),
        ("Road marker", signs["hills_mid"], {"route": "kefar_zayit__magdala__land", "at": 0.15}, "A squared stone where the road toward Magdala leaves the hills above Kefar Zayit."),
        ("Road marker", signs["magdala_gate"], {"place": "magdala"}, "A squared stone by the road outside Magdala. Ahead is the gate; the lake lies beyond the town."),
    ]
    for nm, (sx, sy), where, text in markers:
        inter_w.append({"type": "waymark", "name": nm, "tile": [sx + 0.5, sy + 0.6], "radius": 34, "modes": ["land"], "text": [text], **where})
    inter_w.append({"type": "waymark", "name": "The landing", "tile": [226, -111.5], "radius": 40, "modes": ["water"], "place": "magdala",
                    "text": ["Boats are drawn up on the sand, and a few rest at the end of the pier, tarred and patched.",
                             "Fishermen will carry a passenger across the water for a small fee, when the weather lets them."]})
    inter_w += [
        {"type": "examine", "name": "The shepherds' cairn", "tile": [66.5, -59.5], "radius": 38, "landmark": "shepherds_cairn",
         "variants": [
             {"when": {"not_flag": "saw_cairn"},
              "text": ["A heap of fieldstones taller than a man, each one laid by a passing shepherd for luck or for a landmark.",
                       "From up here the land opens out. East, beyond the hills, the lake lies like a dropped blue coin. Smoke rises from the fishing towns on its shore."],
              "effects": [{"landmark": "shepherds_cairn"}, {"set_flag": "saw_cairn"},
                          {"reveal_place": {"place": "tiberias", "level": "discovered"}},
                          {"reveal_place": {"place": "capernaum", "level": "rumored"}}]},
             {"text": ["The shepherds' cairn. Someone has added a stone since you were last here."]},
         ]},
        {"type": "examine", "name": "The spring", "tile": [67.0, 21.5], "radius": 34,
         "text": ["A spring seeps from the foot of the rocks into a clear pool. The ground around it is trodden by sheep and, you think, by people who prefer not to be seen."]},
        {"type": "examine", "name": "The ford", "tile": [99.5, -71.5], "radius": 44,
         "text": ["Flat stones set across the stream where the road crosses. The water runs cold and fast underneath."]},
        {"type": "examine", "name": "Cana of Galilee", "tile": [-112, 49.5], "radius": 40, "when": {"place_known": {"place": "cana", "level": "discovered"}},
         "text": ["The gate of Cana stands ahead, a gap between two stone posts in the low wall that rings the village. Smoke rises beyond the roofs."]},
        {"type": "examine", "name": "The gate of Magdala", "tile": [165.5, -111.5], "radius": 40,
         "text": ["A gap in the low wall between two stone posts. Beyond it the lanes of Magdala run down toward the lake."]},
    ]
    npcs_w.append({"id": "hills_highwayman", "name": "Highwayman", "sprite": "highwayman", "profile": "highwayman", "dialogue": "",
                   "encounter": "hills_highwayman", "tile": [63.5, 22.5], "wander": 0, "facing": "right",
                   "when": {"time_of_day": {"from": 360, "to": 1080}}})
    camps = {
        "kefar_zayit_outskirts": (26, -3), "cana_road": (-66, 9), "cana_approach": (-120, 48),
        "galilee_hills": (58, -9), "hills_north": (70, -60), "magdala_shore": (160, -114),
    }
    blk = w.blocked()
    for rid, (cx, cy) in camps.items():
        for dx in range(0, 6):
            for dy in range(0, 6):
                if (cx + dx, cy + dy) not in blk and w.region_at(cx + dx, cy + dy) == rid and w.get(cx + dx, cy + dy) in "gh":
                    entries_w.setdefault("camp@" + rid, {"tile": [cx + dx, cy + dy], "facing": "down"})
    # verification: everything the player should reach is reachable from the village gate
    seen = w.reach((21, 0))
    for label, t in [("cana gate", (-112, 50)), ("magdala west gate", (164, -112)), ("pier", (227, -112)), ("cairn", (66, -62)), ("spring", (64, 23)),
                     ("ford", (100, -72))]:
        assert t in seen, f"{label} {t} is not reachable by walking"
    for nm, e in list(entries_w.items()):
        assert tuple(e["tile"]) in seen, f"entry {nm} {e['tile']} unreachable"
    for it in inter_w:
        t = (int(it["tile"][0]), int(it["tile"][1]))
        assert any((t[0] + dx, t[1] + dy) in seen for dx in range(-2, 3) for dy in range(-2, 3)), f"interactable {it['name']} {t} unreachable"
    for n in npcs_w:
        assert (int(n["tile"][0]), int(n["tile"][1])) in seen, f"npc {n['id']} unreachable"
    # every tree stands on open ground
    for p in w.props:
        if p["prop"] in TREES:
            assert w.get(*p["tile"]) in ("g", "h"), f"tree at {p['tile']} on {w.get(*p['tile'])}"

    # -- cut the raster into the regional maps ---------------------------------------------------
    for rid, name, rx, ry, rw, rh, extra in REGIONS:
        def inside(x, y):
            return rx <= x < rx + rw and ry <= y < ry + rh
        ground = ["".join(w.get(x, y) for x in range(rx, rx + rw)) for y in range(ry, ry + rh)]
        objs = [[o[0] - rx, o[1] - ry, o[2]] for o in w.objects if inside(o[0], o[1])]
        props = [{"prop": p["prop"], "tile": [p["tile"][0] - rx, p["tile"][1] - ry]} for p in w.props if inside(*p["tile"])]
        inters = []
        for it in inter_w:
            if inside(int(it["tile"][0]), int(it["tile"][1])):
                c = dict(it)
                c["tile"] = [it["tile"][0] - rx, it["tile"][1] - ry]
                inters.append(c)
        npcs = []
        for n in npcs_w:
            if inside(int(n["tile"][0]), int(n["tile"][1])):
                c = dict(n)
                c["tile"] = [n["tile"][0] - rx, n["tile"][1] - ry]
                npcs.append(c)
        entries = {}
        for nm, e in entries_w.items():
            if inside(*e["tile"]):
                c = dict(e)
                c["tile"] = [e["tile"][0] - rx, e["tile"][1] - ry]
                entries[nm.split("@")[0]] = c
        exits = []
        for ex in exits_w:
            r = ex["rect"]
            if inside(r[0], r[1]):
                c = dict(ex)
                c["rect"] = [r[0] - rx, r[1] - ry, r[2], r[3]]
                exits.append(c)
        camp = entries.get("camp")
        assert camp, f"{rid} has no camp entry"
        d = {
            "id": rid, "name": name, "kind": "regional", "origin": "fiction",
            "note": "Invented countryside of lower Galilee, generated as part of the continuous world (tools/mapgen/world.py).",
            "world": [rx, ry], "size": [rw, rh], "spawn": [camp["tile"][0] + 0.5, camp["tile"][1] + 0.5],
            "entries": entries, "exits": exits, "ground": ground, "ground_legend": LEGEND,
            "objects": objs, "props": props, "npcs": npcs, "interactables": inters,
        }
        d.update(extra)
        with open(os.path.join(OUT, rid + ".json"), "w") as f:
            json.dump(d, f, indent=1)
        print("wrote", rid, f"{rw}x{rh} at world ({rx},{ry})", f"{len(props)} props", f"{len(inters)} interactables")
    return w


if __name__ == "__main__":
    build()
