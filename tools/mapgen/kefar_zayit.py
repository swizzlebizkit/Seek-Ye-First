"""Builds data/regions/kefar_zayit.json -- the prologue village (an invented settlement).

Run from the project root:  python -I tools/mapgen/kefar_zayit.py
Ground is an ASCII grid; buildings, props, NPCs and interactables are listed explicitly.
"""
import json
import os
import random

W, H = 40, 28
rng = random.Random(31)

ground = [["g"] * W for _ in range(H)]
objects = []  # [x, y, tile_name]
props = []  # {prop, tile:[x,y]}  (placed at the bottom-centre of the tile)
occupied = set()


def fill(x0, y0, x1, y1, ch):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if 0 <= x < W and 0 <= y < H:
                ground[y][x] = ch


def occupy(x0, y0, x1, y1, pad=0):
    for y in range(y0 - pad, y1 + pad + 1):
        for x in range(x0 - pad, x1 + pad + 1):
            occupied.add((x, y))


def prop(name, x, y, block=True, pad=0):
    props.append({"prop": name, "tile": [x, y]})
    if block:
        occupy(x, y, x, y, pad)


# --- boundary cliffs (irregular, 2-3 tiles thick) ---------------------------------------------
fill(0, 0, W - 1, 1, "c")
fill(0, H - 2, W - 1, H - 1, "c")
fill(0, 0, 1, H - 1, "c")
fill(W - 2, 0, W - 1, H - 1, "c")
for x in range(2, W - 2):
    for y in (2, H - 3):
        if rng.random() < 0.45:
            ground[y][x] = "c"
for y in range(2, H - 2):
    for x in (2, W - 3):
        if rng.random() < 0.45:
            ground[y][x] = "c"
fill(0, 0, W - 1, 1, "c")

# dry grass patches
for _ in range(10):
    cx, cy = rng.randrange(4, W - 4), rng.randrange(4, H - 4)
    for yy in range(cy - 1, cy + 2):
        for xx in range(cx - 2, cx + 3):
            if ground[yy][xx] == "g" and rng.random() < 0.8:
                ground[yy][xx] = "h"

# --- roads and plaza ---------------------------------------------------------------------------
fill(3, 13, 37, 14, "d")  # east-west road, runs to the east signpost
fill(19, 3, 20, 24, "d")  # north-south lane
fill(16, 11, 23, 16, "p")  # flagstone plaza around the well

# --- pond with a sandy shore (south-west) ------------------------------------------------------
fill(3, 17, 9, 21, "s")
fill(4, 18, 8, 20, "w")
fill(5, 17, 7, 17, "w")
ground[21][4] = "s"
occupy(3, 17, 9, 21, 1)


# --- buildings ---------------------------------------------------------------------------------
def house(x, y, w, rh, door_dx, window_dxs=(), yard=True):
    """Flat-roofed limestone house. Roof rows y..y+rh-1, front wall at y+rh."""
    for ry in range(rh):
        for rx in range(w):
            row = "t" if ry == 0 else ("b" if ry == rh - 1 else "")
            col = "l" if rx == 0 else ("r" if rx == w - 1 else "")
            name = {("t", "l"): "tl", ("t", ""): "t", ("t", "r"): "tr",
                    ("", "l"): "l", ("", ""): "c", ("", "r"): "r",
                    ("b", "l"): "bl", ("b", ""): "b", ("b", "r"): "br"}[(row, col)]
            objects.append([x + rx, y + ry, f"roof_{name}"])
    wy = y + rh
    for rx in range(w):
        if rx == door_dx:
            tile = "wall_door"
        elif rx in window_dxs:
            tile = "wall_window"
        else:
            tile = rng.choice(["wall_stone", "wall_stone_b"])
        objects.append([x + rx, wy, tile])
    occupy(x, y, x + w - 1, wy, 1)
    door = (x + door_dx, wy)
    if yard:
        fill(door[0] - 1, wy + 1, door[0] + 1, wy + 2, "d")
    return door


h1 = house(5, 4, 5, 2, 2, window_dxs=(0, 4))      # the protagonist's home
h2 = house(11, 4, 5, 3, 2, window_dxs=(4,))       # Elder Ezra
h3 = house(24, 4, 5, 2, 1, window_dxs=(3,))
h4 = house(31, 5, 5, 3, 1, window_dxs=(3,))
h5 = house(12, 19, 5, 2, 2, window_dxs=(0,))
h6 = house(22, 17, 6, 3, 2, window_dxs=(0, 4))

# short dirt paths from each door down to the roads
for dx, dy in (h1, h2, h3, h4):
    fill(dx, dy + 1, dx, 13, "d")
# doors on the southern houses face away from the road, so their paths run along the yard to the lane
fill(h5[0], h5[1] + 2, 19, h5[1] + 2, "d")
fill(20, h6[1] + 2, h6[0], h6[1] + 2, "d")

# --- fields (south-east) -----------------------------------------------------------------------
fill(30, 22, 36, 25, "f")
for x in range(29, 37):
    objects.append([x, 21, "lowwall_h"])
for y in range(22, 26):
    objects.append([29, y, "lowwall_v"])
occupy(29, 21, 37, 26)

# --- props -------------------------------------------------------------------------------------
prop("well", 19, 13)  # sits on the plaza edge between the paving
occupy(18, 12, 21, 14)
prop("market_stall", 28, 11)
occupy(26, 10, 31, 12, 0)
prop("signpost", 36, 12)
occupy(35, 11, 37, 13)
prop("clay_oven", 8, 8)
prop("basket", 22, 15, pad=0)
prop("crate", 24, 15)
prop("jar_large", 17, 12)
prop("jar_large", 14, 8, pad=0)
prop("basket", 30, 12)
prop("crate", 33, 12, pad=0)

# olive grove (south-west). The lost jar rolls into the middle of it.
grove = [(5, 24), (8, 25), (11, 24), (14, 25), (6, 22), (10, 22), (3, 25)]
for i, (gx, gy) in enumerate(grove):
    prop("olive_tree_a" if i % 2 else "olive_tree_b", gx, gy)
    occupy(gx - 1, gy - 2, gx + 1, gy)

for tx, ty in ((18, 8), (22, 8), (17, 18), (34, 17), (5, 10)):
    prop("cypress", tx, ty)
    occupy(tx - 1, ty - 1, tx + 1, ty)
for tx, ty in ((4, 5), (30, 9), (36, 10), (10, 16), (33, 19)):
    prop("olive_tree_b" if tx % 2 else "olive_tree_a", tx, ty)
    occupy(tx - 1, ty - 2, tx + 1, ty)

# scatter shrubs, rocks and flowers on free grass
cells = [(x, y) for y in range(3, H - 3) for x in range(3, W - 3)
         if ground[y][x] in ("g", "h") and (x, y) not in occupied]
rng.shuffle(cells)
placed = 0
for x, y in cells:
    if placed >= 26:
        break
    if (x, y) in occupied:
        continue
    kind = rng.choice(["bush", "bush", "bush_flowers", "boulder", "flowers_patch", "flowers_patch"])
    prop(kind, x, y, block=kind in ("bush", "bush_flowers", "boulder"), pad=1 if kind != "flowers_patch" else 0)
    placed += 1

# --- people ------------------------------------------------------------------------------------
npcs = [
    {"id": "miriam", "name": "Miriam", "dialogue": "miriam", "tile": [17.5, 14.6], "wander": 40},
    {"id": "yosef", "name": "Yosef the trader", "dialogue": "yosef", "tile": [28.0, 12.7], "wander": 28},
    {"id": "ezra", "name": "Elder Ezra", "dialogue": "ezra", "tile": [13.5, 8.6], "wander": 24},
    {"id": "hannah", "name": "Hannah", "dialogue": "hannah", "tile": [34.4, 12.8], "wander": 12},
    {"id": "asher", "name": "Asher", "dialogue": "asher", "tile": [21.5, 15.6], "wander": 80},
]

# --- interactables -----------------------------------------------------------------------------
interactables = [
    {"type": "pickup", "id": "water_jar", "name": "Clay jar", "item": "water_jar", "prop": "jar_small",
     "tile": [8, 22],
     "text": ["A clay water jar, chipped at the lip but whole. Someone is surely missing it."],
     "effects": [{"quest_objective": {"quest": "missing_jar", "objective": "find_jar"}}]},
    {"type": "pickup", "id": "scroll_malachi", "name": "Old scroll", "item": "scroll_malachi", "prop": "scroll",
     "tile": [12, 15], "radius": 18,
     "text": ["A scroll in a cracked leather case, half hidden in the grass under the olive tree. Hebrew, in a careful hand. You cannot read it well, but someone could."]},
    {"type": "pickup", "id": "scroll_kings", "name": "Dark scroll", "item": "scroll_kings", "prop": "scroll",
     "tile": [27, 19], "radius": 18,
     "text": ["A short scroll, dark with handling, lying where a traveler must have dropped it. Hebrew writing, which you cannot follow."]},
    {"type": "pickup", "id": "village_bread", "name": "Flatbread", "item": "flatbread", "prop": "flatbread",
     "tile": [31, 14], "radius": 18,
     "text": ["A round of barley bread, left on the wall for whoever is hungry. You take it."]},
    {"type": "examine", "name": "The well", "tile": [19, 13.7], "radius": 40,
     "text": ["A stone well, its rim worn smooth by generations of ropes. The water is cool and sweet."]},
    {"type": "examine", "name": "Your home", "tile": [h1[0] + 0.5, h1[1] + 1.15], "radius": 26,
     "text": ["Home. The bread is baked, the floor swept. Today there is little more to do here."]},
    {"type": "examine", "name": "Elder Ezra's house", "tile": [h2[0] + 0.5, h2[1] + 1.15], "radius": 26,
     "text": ["The door of Elder Ezra's house. Scrolls are said to be kept inside, though few have seen them."]},
    {"type": "examine", "name": "Door", "tile": [h3[0] + 0.5, h3[1] + 1.15], "radius": 26,
     "text": ["The door is shut. Its owners are out in the fields."]},
    {"type": "examine", "name": "Door", "tile": [h4[0] + 0.5, h4[1] + 1.15], "radius": 26,
     "text": ["The door is barred from within. A dog barks once, then thinks better of it."]},
    {"type": "examine", "name": "Door", "tile": [h5[0] + 0.5, h5[1] + 1.15], "radius": 26,
     "text": ["Miriam's house. Her door stands open, but nobody is inside."]},
    {"type": "examine", "name": "Door", "tile": [h6[0] + 0.5, h6[1] + 1.15], "radius": 26,
     "text": ["A heavy door. The family that lives here is away at a wedding in Cana."]},
    {"type": "examine", "name": "Pond", "tile": [6, 21.2], "radius": 34,
     "text": ["A small pond fed by a spring. Reeds crowd the sandy edge, and something small plops into the water."]},
    {"type": "examine", "name": "The olive grove", "tile": [8, 23.2], "radius": 30, "once_flag": "saw_grove",
     "text": ["Old olive trees, gnarled and silver-leaved. Some of them were here before your grandfather was born."]},
    {"type": "examine", "name": "Signpost", "tile": [36, 12.9], "radius": 36,
     "variants": [
         {"when": {"flag": "road_east_ready"},
          "text": ["The road east drops out of the hills toward the Jordan valley.",
                   "You cannot stop thinking about what you have heard. You mean to see it for yourself.",
                   "[Prototype boundary] The road to the Jordan opens in Milestone 2."],
          "effects": [{"journal": "obs_decision"}]},
         {"text": ["A weathered signpost. The road east leads down toward the Jordan valley.",
                   "You have no particular reason to go that way. Not yet."]},
     ]},
]

region = {
    "id": "kefar_zayit",
    "name": "Kefar Zayit",
    "origin": "fiction",
    "note": "An invented Galilean village; no canonical event occurs here.",
    "size": [W, H],
    "spawn": [7.5, 8.4],
    "ground": ["".join(r) for r in ground],
    "ground_legend": {
        "g": ["grass_0", "grass_0", "grass_0", "grass_1", "grass_1", "grass_2", "grass_2", "grass_2", "grass_1", "grass_flowers"],
        "h": ["grass_dry_0", "grass_dry_1"],
        "d": ["dirt_0", "dirt_1"],
        "p": ["path_0", "path_1"],
        "s": ["sand_0", "sand_1"],
        "w": ["water_0", "water_1"],
        "c": ["cliff_0", "cliff_1"],
        "f": ["field_0", "field_1"],
    },
    "objects": objects,
    "props": props,
    "npcs": npcs,
    "interactables": interactables,
}

if __name__ == "__main__":
    out = os.path.join(os.path.dirname(__file__), "..", "..", "data", "regions", "kefar_zayit.json")
    with open(out, "w") as f:
        json.dump(region, f, indent=1)
    print("wrote", os.path.abspath(out), f"({W}x{H} tiles, {len(props)} props)")
    for r in region["ground"]:
        print(r)
