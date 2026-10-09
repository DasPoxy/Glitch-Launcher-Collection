#!/usr/bin/env python3
"""A picture's size and its dominant colours, as JSON (for the readout).

    palette.py IMAGE

{path, w, h, colors: ["#rrggbb", ...]} - eight colours, most common first,
from a small copy of the image. Cached by path + mtime.
"""
import hashlib
import json
import os
import sys

from PIL import Image

CACHE = os.path.expanduser("~/.cache/glitch-background-selector/palettes")


def main():
    path = sys.argv[1]
    st = os.stat(path)
    key = hashlib.md5(f"{path}:{st.st_mtime}".encode()).hexdigest()
    cached = os.path.join(CACHE, key + ".json")
    if os.path.exists(cached):
        print(open(cached).read())
        return
    with Image.open(path) as im:
        w, h = im.size
        im.draft("RGB", (160, 160))                  # JPEGs decode small
        im = im.convert("RGB")
        im.thumbnail((96, 96))
        q = im.quantize(colors=24, method=Image.Quantize.MEDIANCUT)
        pal = q.getpalette()
        counts = sorted(q.getcolors(), reverse=True)
        # most common first, skipping any too close to one already picked,
        # so a dark picture doesn't come back as eight blacks
        picked = []
        for _, i in counts:
            c = tuple(pal[i * 3:i * 3 + 3])
            if all(sum((a - b) ** 2 for a, b in zip(c, p)) > 42 ** 2 for p in picked):
                picked.append(c)
            if len(picked) == 8:
                break
        cols = ["#%02x%02x%02x" % c for c in picked]
    out = json.dumps({"path": path, "w": w, "h": h, "colors": cols})
    os.makedirs(CACHE, exist_ok=True)
    with open(cached, "w") as f:
        f.write(out)
    print(out)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:                           # unreadable: say so, don't crash
        print(json.dumps({"path": sys.argv[1] if len(sys.argv) > 1 else "", "w": 0, "h": 0, "colors": [], "error": str(e)}))
