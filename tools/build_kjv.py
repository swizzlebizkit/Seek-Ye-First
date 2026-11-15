"""Builds data/scripture/kjv.json (the whole King James Version) from the Bible Bank CSV.

    python -X utf8 -I tools/build_kjv.py path/to/BIBLE_BANK_KJV_master_with_RV1909_backfilled_all.csv

Only the KJV 'Text' column is used. The CSV marks the KJV's italic (supplied) words with [square brackets];
the markers are removed here. The typographic apostrophe is changed to a plain one so text matches the
rest of the game. Verses are checked: 31,102 verses, 66 books, every chapter numbered 1..n with no gaps.
"""
import csv
import json
import os
import re
import sys

csv.field_size_limit(10 ** 9)
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "data", "scripture", "kjv.json")


def main(path):
    books = {}
    count = 0
    with open(path, encoding="utf-8-sig", newline="") as f:
        for r in csv.DictReader(f):
            text = re.sub(r"\[([^\]]*)\]", r"\1", r["Text"]).replace("\u2019", "'").strip()
            if not text:
                raise SystemExit("empty verse: " + r["Ref"])
            ch = books.setdefault(r["Book"], {}).setdefault(r["Chapter"], {})
            if r["Verse"] in ch:
                raise SystemExit("duplicate verse: " + r["Ref"])
            ch[r["Verse"]] = text
            count += 1
    for b, chs in books.items():
        for c, vs in chs.items():
            if sorted(int(v) for v in vs) != list(range(1, len(vs) + 1)):
                raise SystemExit("gap in %s %s" % (b, c))
    if count != 31102 or len(books) != 66:
        raise SystemExit("unexpected size: %d verses, %d books" % (count, len(books)))
    data = {
        "translation": "KJV",
        "name": "King James Version",
        "license": "Public domain",
        "note": "The complete KJV, built by tools/build_kjv.py from the Bible Bank CSV. Italic (supplied) words are plain text.",
        "books": books,
    }
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    print("wrote %d verses in %d books" % (count, len(books)))


if __name__ == "__main__":
    main(sys.argv[1])
