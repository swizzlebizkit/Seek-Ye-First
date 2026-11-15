"""Regenerate every procedural asset deterministically.

    python -I tools/procgen/generate_all.py            # from the project root
    python -I tools/procgen/generate_all.py --preview DIR   # also write 3x enlarged previews

All randomness uses fixed seeds, so re-running produces byte-identical PNGs.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import characters  # noqa: E402
import props  # noqa: E402
import tiles  # noqa: E402
import ui_art  # noqa: E402
from pxl import Canvas  # noqa: E402

ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))


def main():
    preview = None
    if "--preview" in sys.argv:
        preview = sys.argv[sys.argv.index("--preview") + 1]
        os.makedirs(preview, exist_ok=True)

    atlas = tiles.write(os.path.join(ROOT, "assets", "tiles"))
    props.write(os.path.join(ROOT, "assets", "props"))
    characters.write(os.path.join(ROOT, "assets", "characters"), os.path.join(ROOT, "data", "characters"))
    ui_art.write(os.path.join(ROOT, "assets", "ui"))
    print("generated tiles, props, characters, ui")

    if preview:
        atlas.scaled(3).save(os.path.join(preview, "terrain_x3.png"))
        sheet = Canvas(len(characters.CHARACTERS) * 128, 192)
        for i, (name, sp) in enumerate(characters.CHARACTERS.items()):
            sheet.blit(characters.sheet(sp), i * 128, 0)
        sheet.scaled(2).save(os.path.join(preview, "characters_x2.png"))
        board = Canvas(520, 96)
        x = 4
        for name, build, origin, collider in props.PROPS:
            cv = build()
            board.blit(cv, x, 90 - cv.h)
            x += cv.w + 4
        board.scaled(2).save(os.path.join(preview, "props_x2.png"))
        print("previews written to", preview)


if __name__ == "__main__":
    main()
