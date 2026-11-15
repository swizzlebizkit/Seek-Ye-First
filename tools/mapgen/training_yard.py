"""Builds data/regions/training_yard.json -- the dev-only combat training yard.

Run from the project root:  python -I tools/mapgen/training_yard.py
A walled test area with three conflict lanes (talk it out, get away, fight), a guard who only reacts
to what he sees, and two bystanders. It is reachable from the main menu in debug builds only.
"""
import json
import os
import random

W, H = 34, 22
rng = random.Random(77)
ground = [["g"] * W for _ in range(H)]
objects = []
props = []


def fill(x0, y0, x1, y1, ch):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if 0 <= x < W and 0 <= y < H:
                ground[y][x] = ch


# boundary cliffs
fill(0, 0, W - 1, 1, "c")
fill(0, H - 2, W - 1, H - 1, "c")
fill(0, 0, 1, H - 1, "c")
fill(W - 2, 0, W - 1, H - 1, "c")

# arena floor, flagstone start area, and the toll road
fill(12, 3, 31, 19, "d")
fill(3, 3, 10, 14, "p")
fill(11, 7, 31, 8, "p")
for _ in range(40):
    x, y = rng.randrange(2, W - 2), rng.randrange(2, H - 2)
    if ground[y][x] == "g":
        ground[y][x] = "h"

# walls: one to break line of sight, one fencing the cutthroat's alcove
for x in range(17, 21):
    objects.append([x, 11, "lowwall_h"])
for y in range(13, 16):
    objects.append([25, y, "lowwall_v"])
for x in range(27, 31):
    objects.append([x, 16, "lowwall_h"])

props.append({"prop": "signpost", "tile": [4, 12]})
props.append({"prop": "signpost", "tile": [6, 12]})
for x, y in ((13, 4), (30, 4), (31, 11), (12, 12), (24, 18), (22, 4)):
    props.append({"prop": "boulder", "tile": [x, y]})
for x, y in ((10, 18), (3, 17), (3, 18), (5, 17)):
    props.append({"prop": "bush", "tile": [x, y]})

crates = [
    ("yard_crate_shield", "Crate of shields", "wicker_shield", [4, 4], "A crate of wicker shields."),
    ("yard_crate_cap", "Crate of caps", "felt_cap", [6, 4], "A crate of felt caps."),
    ("yard_crate_belt", "Crate of belts", "leather_belt", [8, 4], "A crate of leather belts."),
    ("yard_crate_vest", "Crate of vests", "quilted_vest", [4, 7], "A crate of quilted vests."),
    ("yard_crate_boots", "Crate of boots", "road_boots", [6, 7], "A crate of road boots."),
    ("yard_crate_coin", "Coin box", "lepton", [8, 7], "A box of copper coins for the toll-taker."),
]
interactables = []
for cid, name, item, tile, text in crates:
    interactables.append({"type": "pickup", "id": cid, "name": name, "item": item, "prop": "crate",
                          "tile": tile, "radius": 20, "text": [text + " You take one."]})
interactables += [
    {"type": "ledger", "name": "Training ledger", "tile": [4.5, 12.4], "radius": 28},
    {"type": "examine", "name": "Yard rules", "tile": [6.5, 12.4], "radius": 28,
     "text": ["TRAINING YARD (development only).",
              "K or X swings the sword. Shift or L is a quick dodge step. I or Q opens equipment.",
              "The toll-taker on the road will talk. The highwayman will give chase and can be outrun. "
              "The cutthroat by the wall will fight. The guard reacts only to what he sees you do.",
              "Every way an encounter can end counts. Nothing here has to be fought."]},
]

npcs = [
    {"id": "yard_toll_taker", "name": "Toll-taker", "sprite": "toll_taker", "profile": "toll_taker",
     "dialogue": "yard_toll_taker", "encounter": "yard_toll", "tile": [20.5, 7.9], "wander": 0, "facing": "left"},
    {"id": "yard_highwayman", "name": "Highwayman", "sprite": "highwayman", "profile": "highwayman",
     "dialogue": "", "encounter": "yard_highwayman", "tile": [24.5, 12.0], "wander": 0, "facing": "left"},
    {"id": "yard_cutthroat", "name": "Cutthroat", "sprite": "cutthroat", "profile": "cutthroat",
     "dialogue": "", "encounter": "yard_cutthroat", "tile": [28.5, 18.4], "wander": 0, "facing": "up"},
    {"id": "yard_guard", "name": "Guard", "sprite": "guard", "profile": "guard",
     "dialogue": "yard_guard", "encounter": "yard_guard", "tile": [14.5, 14.5], "wander": 0, "facing": "down"},
    {"id": "yard_traveler", "name": "Traveler", "sprite": "traveler", "profile": "wayfarer",
     "dialogue": "yard_traveler", "tile": [16.5, 16.5], "wander": 20, "facing": "left"},
    {"id": "yard_merchant", "name": "Merchant", "sprite": "merchant", "profile": "merchant",
     "dialogue": "yard_merchant", "tile": [12.5, 17.5], "wander": 20, "facing": "right"},
]

region = {
    "id": "training_yard",
    "name": "Training Yard",
    "origin": "fiction",
    "note": "Developer test area for combat and conflict resolution. Not part of the story.",
    "size": [W, H],
    "spawn": [5.5, 10.5],
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
    out = os.path.join(os.path.dirname(__file__), "..", "..", "data", "regions", "training_yard.json")
    with open(out, "w") as f:
        json.dump(region, f, indent=1)
    print("wrote", os.path.abspath(out))
    for r in region["ground"]:
        print(r)
