#!/usr/bin/env python3
"""Glitch-Background-Selector's fit modes: a wallpaper laid out at the
screen's own size, so the shell (which always crops to fill) shows it as is.

    render-bg.py IMAGE MODE        prints the path to set

MODE: fit (letterboxed on its darkest colour), blur (fit, over a blurred,
dimmed copy of itself filling the screen), stretch, center (actual size),
tile (actual size, repeated). "fill" just prints IMAGE back. Rendered files
are cached; map.json remembers which picture each came from.
"""
import hashlib
import json
import os
import subprocess
import sys

from PIL import Image, ImageFilter

CACHE = os.path.expanduser("~/.cache/glitch-background-selector/rendered")


def screen_size():
    """the largest monitor's pixels (one image goes to every screen)"""
    try:
        mons = json.loads(subprocess.run(["hyprctl", "monitors", "-j"], capture_output=True, text=True, timeout=3).stdout)
        sizes = []
        for m in mons:
            w, h = m["width"], m["height"]
            if m.get("transform", 0) % 2 == 1:                 # rotated
                w, h = h, w
            sizes.append((w, h))
        return max(sizes, key=lambda s: s[0] * s[1])
    except Exception:
        return 2560, 1440


def darkest(im):
    small = im.copy()
    small.thumbnail((48, 48))
    px = list(small.get_flattened_data()) if hasattr(small, "get_flattened_data") else list(small.getdata())
    return min(px, key=lambda c: c[0] * 0.2126 + c[1] * 0.7152 + c[2] * 0.0722)


def render(src, mode, W, H):
    im = Image.open(src).convert("RGB")
    w, h = im.size
    if mode == "stretch":
        return im.resize((W, H), Image.LANCZOS)
    if mode == "tile":
        out = Image.new("RGB", (W, H))
        for y in range(0, H, h):
            for x in range(0, W, w):
                out.paste(im, (x, y))
        return out
    if mode == "center":
        out = Image.new("RGB", (W, H), darkest(im))
        out.paste(im, ((W - w) // 2, (H - h) // 2))
        return out
    # fit / blur: the whole picture, as large as fits
    k = min(W / w, H / h)
    fw, fh = max(1, round(w * k)), max(1, round(h * k))
    fitted = im.resize((fw, fh), Image.LANCZOS)
    if mode == "blur":
        kc = max(W / w, H / h)
        back = im.resize((max(1, round(w * kc / 8)), max(1, round(h * kc / 8))), Image.BILINEAR)
        back = back.filter(ImageFilter.GaussianBlur(6)).resize((round(w * kc), round(h * kc)), Image.BILINEAR)
        back = back.crop(((back.width - W) // 2, (back.height - H) // 2, (back.width - W) // 2 + W, (back.height - H) // 2 + H))
        back = Image.eval(back, lambda v: int(v * 0.55))
        out = back
    else:
        out = Image.new("RGB", (W, H), darkest(im))
    out.paste(fitted, ((W - fw) // 2, (H - fh) // 2))
    return out


def main():
    src, mode = os.path.realpath(sys.argv[1]), sys.argv[2]
    if mode not in ("fit", "blur", "stretch", "center", "tile"):
        print(src)
        return
    W, H = screen_size()
    st = os.stat(src)
    key = hashlib.md5(f"{src}:{st.st_mtime}:{mode}:{W}x{H}".encode()).hexdigest()[:20]
    os.makedirs(CACHE, exist_ok=True)
    out = os.path.join(CACHE, f"{key}-{mode}.jpg")
    if not os.path.exists(out):
        tmp = out + ".tmp.jpg"
        render(src, mode, W, H).save(tmp, quality=94)
        os.replace(tmp, out)
    # remember where it came from, so the selector still knows what's on screen
    mp = os.path.join(CACHE, "map.json")
    try:
        m = json.load(open(mp))
    except Exception:
        m = {}
    m[out] = {"source": src, "mode": mode}
    with open(mp + ".tmp", "w") as f:
        json.dump(m, f)
    os.replace(mp + ".tmp", mp)
    print(out)


if __name__ == "__main__":
    main()
