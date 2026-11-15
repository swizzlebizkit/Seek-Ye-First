"""Modular 32x48 character sprites -> assets/characters/<id>.png (4 columns of walk frames x 4 rows).

Row order: down, left, right, up. Frame order: stand, step A, stand, step B.
Every character is composed from the same shared walk template; only the appearance spec differs
(skin, hair, beard, robe, sash, mantle, head cover, long/short garment, child proportions).
"""
import json
import os

import palette as P
from pxl import Canvas, shade

FW, FH = 32, 48
DIRS = ["down", "left", "right", "up"]
EYE = (36, 26, 22)


def make_spec(**kw):
    base = {
        "skin": 1, "hair": "dark", "hair_style": "short", "beard": "none",
        "robe": "wool", "sash": "indigo", "trim": None, "mantle": None, "cover": None,
        "long": False, "child": False,
    }
    base.update(kw)
    return base


def _colors(sp):
    return {
        "skin": P.SKIN[sp["skin"]],
        "hair": P.HAIR[sp["hair"]],
        "robe": P.CLOTH[sp["robe"]],
        "sash": P.CLOTH[sp["sash"]],
        "trim": P.CLOTH[sp["trim"]] if sp["trim"] else None,
        "mantle": P.CLOTH[sp["mantle"]] if sp["mantle"] else None,
        "cover": P.CLOTH[sp["cover"]] if sp["cover"] else None,
    }


def _front_back(sp, back, f):
    c = _colors(sp)
    cv = Canvas(FW, FH)
    lift = 1 if f in (1, 3) else 0
    step = (0, 1, 0, -1)[f]
    by = -lift
    robe, skin = c["robe"], c["skin"]
    skin_d = shade(skin, 0.84)
    long_robe = sp["long"]
    hem = 43 if long_robe else 39

    def r(x0, y0, x1, y1, col, bob=True):
        cv.rect(x0, y0 + (by if bob else 0), x1, y1 + (by if bob else 0), col)

    # legs and sandals
    for x0, dy in ((12, step), (17, -step)):
        if not long_robe:
            cv.rect(x0, 38, x0 + 2, 43 + dy, skin_d)
        cv.rect(x0 - 1, 44 + dy, x0 + 3, 45 + dy, P.SANDAL)
        cv.hline(x0 - 1, x0 + 3, 44 + dy, shade(P.SANDAL, 1.3))

    # robe
    for y in range(20, hem + 1):
        hw = 6 if y < 34 else 7
        x0, x1 = 16 - hw, 15 + hw
        col = robe
        if y >= hem - 1:
            col = shade(robe, 0.8)
        cv.hline(x0, x1, y + by, col)
        cv.hline(x0, x0 + 1, y + by, shade(robe, 1.12) if y < hem - 1 else shade(robe, 0.95))
        cv.hline(x1 - 1, x1, y + by, shade(robe, 0.8))
    if c["trim"]:
        cv.hline(9, 22, hem - 2 + by, c["trim"])
    cv.vline(16, 31 + by, hem - 2 + by, shade(robe, 0.9))  # fold
    r(10, 29, 21, 30, c["sash"])
    if not back:
        r(19, 31, 20, 33, shade(c["sash"], 0.85))

    # arms and hands
    for x0, swing in ((8, -step), (22, step)):
        bottom = 30 + swing
        r(x0, 21, x0 + 1, bottom, shade(robe, 0.92))
        r(x0, bottom + 1, x0 + 1, bottom + 2, skin)

    if c["mantle"]:
        r(8, 20, 23, 26, c["mantle"])
        r(8, 26, 23, 26, shade(c["mantle"], 0.78))
        r(8, 20, 23, 20, shade(c["mantle"], 1.15))

    # neck + head
    r(14, 19, 17, 20, skin_d)
    for y in range(8, 19):
        x0, x1 = (12, 19) if y in (8, 18) else (11, 20)
        r(x0, y, x1, y, skin)
    r(20, 9, 20, 16, skin_d)

    hair = c["hair"]
    style = sp["hair_style"]
    if back:
        if style != "bald":
            r(10, 7, 21, 17, hair)
            r(11, 6, 20, 6, hair)
            if style == "long":
                r(9, 12, 22, 22, hair)
    else:
        r(13, 13, 13, 13, EYE)
        r(18, 13, 18, 13, EYE)
        if style == "bald":
            r(10, 11, 10, 13, hair)
            r(21, 11, 21, 13, hair)
        else:
            r(11, 7, 20, 10, hair)
            r(10, 8, 10, 12, hair)
            r(21, 8, 21, 12, hair)
            r(11, 6, 20, 6, hair)
            if style == "long":
                r(9, 9, 10, 21, hair)
                r(21, 9, 22, 21, hair)
        if sp["beard"] == "full":
            for y, (x0, x1) in zip(range(15, 21), ((11, 20), (11, 20), (11, 20), (12, 19), (13, 18), (14, 17))):
                r(x0, y, x1, y, hair)
            r(14, 17, 17, 17, shade(skin, 0.7))  # mouth gap
        elif sp["beard"] == "short":
            for y, (x0, x1) in zip(range(15, 19), ((11, 20), (11, 20), (12, 19), (13, 18))):
                r(x0, y, x1, y, hair)
            r(14, 17, 17, 17, shade(skin, 0.7))
    if c["cover"]:
        cov = c["cover"]
        if back:
            r(9, 6, 22, 22, cov)
            r(9, 6, 22, 6, shade(cov, 1.15))
        else:
            r(10, 6, 21, 10, cov)
            r(10, 6, 21, 6, shade(cov, 1.15))
            r(9, 11, 10, 22, cov)
            r(21, 11, 22, 22, shade(cov, 0.85))
            if sp["long"]:
                r(9, 19, 22, 22, cov)
    return cv


def _side(sp, f):
    """Left-facing profile; the right-facing row is a mirror of this."""
    c = _colors(sp)
    cv = Canvas(FW, FH)
    lift = 1 if f in (1, 3) else 0
    step = (0, 1, 0, -1)[f]
    by = -lift
    robe, skin = c["robe"], c["skin"]
    skin_d = shade(skin, 0.84)
    long_robe = sp["long"]
    hem = 43 if long_robe else 39

    def r(x0, y0, x1, y1, col):
        cv.rect(x0, y0 + by, x1, y1 + by, col)

    # legs (back leg first)
    for cx, dim in ((15 - 2 * step, True), (15 + 2 * step, False)):
        if not long_robe:
            cv.rect(cx - 1, 38, cx + 1, 43, shade(skin_d, 0.9) if dim else skin_d)
        cv.rect(cx - 3, 44, cx + 1, 45, shade(P.SANDAL, 0.85) if dim else P.SANDAL)
        cv.hline(cx - 3, cx + 1, 44, shade(P.SANDAL, 1.3))

    for y in range(20, hem + 1):
        x0, x1 = (12, 19) if y < 34 else (11, 20)
        col = shade(robe, 0.8) if y >= hem - 1 else robe
        r(x0, y, x1, y, col)
        r(x0, y, x0 + 1, y, shade(robe, 1.1) if y < hem - 1 else shade(robe, 0.95))
        r(x1 - 1, y, x1, y, shade(robe, 0.8))
    if c["trim"]:
        r(11, hem - 2, 20, hem - 2, c["trim"])
    r(12, 29, 19, 30, c["sash"])
    if c["mantle"]:
        r(11, 20, 20, 26, c["mantle"])
        r(11, 26, 20, 26, shade(c["mantle"], 0.78))

    # near arm
    ax = 14 + 2 * step
    r(ax, 21, ax + 2, 30, shade(robe, 0.9))
    r(ax, 31, ax + 2, 32, skin)

    r(14, 19, 16, 20, skin_d)
    for y in range(8, 19):
        x0, x1 = (13, 18) if y in (8, 18) else (12, 19)
        r(x0, y, x1, y, skin)
    r(11, 14, 11, 14, skin)  # nose
    r(13, 13, 13, 13, EYE)
    r(17, 12, 17, 14, skin_d)  # ear

    hair, style = c["hair"], sp["hair_style"]
    if style == "bald":
        r(17, 10, 19, 13, hair)
    else:
        r(12, 7, 19, 10, hair)
        r(13, 6, 19, 6, hair)
        r(16, 8, 20, 16, hair)
        if style == "long":
            r(16, 8, 21, 22, hair)
    if sp["beard"] == "full":
        r(12, 15, 16, 19, hair)
        r(13, 20, 15, 20, hair)
    elif sp["beard"] == "short":
        r(12, 15, 15, 18, hair)
    if c["cover"]:
        cov = c["cover"]
        r(11, 6, 20, 11, cov)
        r(11, 6, 20, 6, shade(cov, 1.15))
        r(16, 12, 21, 22, shade(cov, 0.9))
        if sp["long"]:
            r(12, 19, 21, 22, cov)
    return cv


def _finish(cv, sp):
    if sp["child"]:
        cv = cv.remove_rows(22, 27)
    cv.outline(P.OUTLINE)
    out = Canvas(FW, FH)
    out.ellipse(16, 45.5, 8, 2, (30, 24, 20, 60))
    out.blit(cv, 0, 0)
    return out


def sheet(sp):
    out = Canvas(FW * 4, FH * 4)
    for row, d in enumerate(DIRS):
        for f in range(4):
            if d == "down":
                fr = _front_back(sp, False, f)
            elif d == "up":
                fr = _front_back(sp, True, f)
            else:
                fr = _side(sp, f)
            fr = _finish(fr, sp)
            if d == "right":
                fr = fr.flip_h()
            out.blit(fr, f * FW, row * FH)
    return out


CHARACTERS = {
    "protagonist": make_spec(skin=1, hair="dark", robe="wool", sash="indigo"),
    "miriam": make_spec(skin=1, hair="black", robe="madder", sash="cream", cover="indigo", long=True, trim="cream"),
    "yosef": make_spec(skin=3, hair="black", hair_style="short", beard="short", robe="olive", sash="saffron",
                       mantle="umber"),
    "ezra": make_spec(skin=0, hair="white", hair_style="long", beard="full", robe="linen", sash="dust",
                      mantle="indigo", long=True),
    "hannah": make_spec(skin=2, hair="brown", robe="brown", sash="dust", cover="dust", mantle="umber", long=True),
    "asher": make_spec(skin=2, hair="black", robe="cream", sash="madder", child=True),
    # combat-test cast (see data/combat/profiles.json); looks carry no meaning about behaviour
    "toll_taker": make_spec(skin=3, hair="black", beard="short", robe="umber", sash="madder", cover="dust"),
    "highwayman": make_spec(skin=2, hair="dark", beard="full", robe="brown", sash="olive", mantle="umber"),
    "cutthroat": make_spec(skin=1, hair="brown", robe="dust", sash="umber", cover="umber"),
    "guard": make_spec(skin=2, hair="black", robe="madder", sash="umber", mantle="brown", trim="saffron"),
    "traveler": make_spec(skin=0, hair="gray", robe="olive", sash="cream", mantle="dust", long=True),
    "merchant": make_spec(skin=3, hair="brown", beard="short", robe="saffron", sash="indigo", mantle="cream"),
}

ATTACK_FW, ATTACK_FH = 48, 48
ATTACK_PAD = 8  # a 32px walk frame sits at x=8 inside the 48px attack frame
STEEL = (214, 220, 226)
STEEL_D = (150, 160, 172)
HILT = (120, 84, 52)
GUARD = (202, 162, 72)


def _blade(cv, x0, y0, x1, y1):
    """Blade from the hand (x0,y0) to the tip (x1,y1): steel with a darker edge, plus a cross-guard."""
    cv.line(x0, y0, x1, y1, STEEL_D)
    dx, dy = (1, 0) if abs(y1 - y0) >= abs(x1 - x0) else (0, 1)
    cv.line(x0 + dx, y0 + dy, x1 + dx, y1 + dy, STEEL)
    cv.set(x1, y1, (250, 252, 255))
    # grip + guard at the hand
    cv.set(x0, y0, HILT)
    cv.set(x0 - dy, y0 - dx, GUARD)
    cv.set(x0 + dy, y0 + dx, GUARD)
    cv.set(x0 + 2 * dy, y0 + 2 * dx, GUARD)


SWORD_LIFT = 6

# per direction and phase: (body dx, body dy, (hand x, hand y, tip x, tip y)) in the 48px frame.
# phases: 0 wind-up (blade drawn back), 1 swing (blade fully out), 2 recover (blade lowered)
ATTACK_POSES = {
    "down": [(0, 0, (31, 31, 33, 19)), (0, 2, (31, 33, 31, 47)), (0, 1, (30, 33, 28, 42))],
    "up": [(0, 0, (17, 28, 15, 38)), (0, -2, (18, 26, 18, 6)), (0, -1, (19, 27, 22, 14))],
    "left": [(0, 0, (22, 29, 31, 18)), (-3, 0, (21, 30, 2, 29)), (-1, 0, (20, 31, 7, 38))],
    "right": None,  # mirror of left
}


def _attack_frame(sp, d, phase):
    src = "left" if d == "right" else d
    if src == "down":
        base = _front_back(sp, False, 0)
    elif src == "up":
        base = _front_back(sp, True, 0)
    else:
        base = _side(sp, 0)
    bx, by, (hx, hy, tx, ty) = ATTACK_POSES[src][phase]
    # the blade is held at stomach height, not hip height
    hy, ty = max(1, hy - SWORD_LIFT), max(1, ty - SWORD_LIFT)
    cv = Canvas(ATTACK_FW, ATTACK_FH)
    cv.blit(base, ATTACK_PAD + bx, by)
    if src == "up":  # blade passes behind the head in the back view
        pass
    _blade(cv, hx, hy, tx, ty)
    cv.outline(P.OUTLINE)
    out = Canvas(ATTACK_FW, ATTACK_FH)
    out.ellipse(24, 45.5, 8, 2, (30, 24, 20, 60))
    out.blit(cv, 0, 0)
    return out.flip_h() if d == "right" else out


def attack_sheet(sp):
    """3 phases x 4 directions of 48x48 frames (rows: down, left, right, up)."""
    out = Canvas(ATTACK_FW * 3, ATTACK_FH * 4)
    for row, d in enumerate(DIRS):
        for ph in range(3):
            out.blit(_attack_frame(sp, d, ph), ph * ATTACK_FW, row * ATTACK_FH)
    return out


def swipe_sheet():
    """Crescent sword-swipe effect: 3 growing arcs x 4 directions of 48x48 frames."""
    import math
    out = Canvas(ATTACK_FW * 3, ATTACK_FH * 4)
    for row, d in enumerate(DIRS):
        ang0 = {"down": 90, "left": 180, "right": 0, "up": 270}[d]
        for ph in range(3):
            cv = Canvas(ATTACK_FW, ATTACK_FH)
            span = (40, 90, 120)[ph]
            alpha = (170, 235, 120)[ph]
            for step in range(span * 2):
                a = math.radians(ang0 - span / 2 + step / 2.0)
                for r, col in ((17, (255, 255, 255, alpha)), (18, (255, 244, 200, alpha)), (19, (236, 214, 150, alpha // 2))):
                    cv.set(int(24 + math.cos(a) * r), int(24 + math.sin(a) * r), col)
            out.blit(cv, ph * ATTACK_FW, row * ATTACK_FH)
    return out


def write(out_dir, data_dir):
    for name, sp in CHARACTERS.items():
        sheet(sp).save(os.path.join(out_dir, f"{name}.png"))
        attack_sheet(sp).save(os.path.join(out_dir, f"{name}_attack.png"))
    swipe_sheet().save(os.path.join(out_dir, "swipe_fx.png"))
    with open(os.path.join(data_dir, "appearance.json"), "w") as f:
        json.dump({"frame_size": [FW, FH], "directions": DIRS, "frames": 4, "characters": CHARACTERS}, f, indent=1)


if __name__ == "__main__":
    root = os.path.join(os.path.dirname(__file__), "..", "..")
    write(os.path.join(root, "assets", "characters"), os.path.join(root, "data", "characters"))
