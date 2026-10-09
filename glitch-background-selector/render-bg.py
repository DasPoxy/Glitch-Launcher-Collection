#!/usr/bin/env python3
"""Glitch-Background-Selector's fit modes: a wallpaper laid out at the
screen's own size, so the shell (which always crops to fill) shows it as is.

    render-bg.py IMAGE MODE [LOOK PRIMARY GLOW BACK]     prints the path to set

MODE: fit (letterboxed on its darkest colour), blur (fit, over a blurred,
dimmed copy of itself filling the screen), stretch, center (actual size),
tile (actual size, repeated). "fill" just prints IMAGE back. Rendered files
are cached; map.json remembers which picture each came from.

LOOK (with three colours, "#rrggbb"): bake the selector's monitor look into
it - grid (duotone, its bright areas traced by blocks), glyph (a mosaic of
characters) or rain (glyphs with code falling through them). A still frame of
what the preview shader draws; "clean" leaves the picture as it is.
"""
import hashlib
import json
import os
import subprocess
import sys

import random

from PIL import Image, ImageDraw, ImageFilter, ImageFont

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


# ------------------------------------------------------------------ looks
GLYPHS = "ｱｲｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾁﾂﾃﾄﾅﾆﾇﾈﾉﾊﾋﾌﾍﾎ0123456789:=+*<>Z"


def hexrgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def tone(l, prim, glow, back):
    """the shader's duotone: background -> glow -> theme colour -> white"""
    c = mix(back, glow, smooth(0.02, 0.4, l))
    c = mix(c, prim, smooth(0.3, 0.75, l))
    return mix(c, (255, 255, 255), smooth(0.78, 1.0, l) * 0.55)


def toned(im, prim, glow, back):
    lut = [tone(i / 255, prim, glow, back) for i in range(256)]
    g = im.convert("L")
    return Image.merge("RGB", [g.point([lut[i][k] for i in range(256)]) for k in range(3)])


def font(px):
    for path in ("/usr/share/fonts/noto-cjk/NotoSansCJK-Bold.ttc", "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc",
                 "/usr/share/fonts/TTF/DejaVuSansMono.ttf"):
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, px, index=0 if path.endswith(".ttf") else 2)
            except Exception:
                pass
    return ImageFont.load_default()


def look_grid(im, prim, glow, back):
    W, H = im.size
    out = toned(im, prim, glow, back)
    px = max(W, H) / 30
    cols, rows = int(W / px) + 1, int(H / px) + 1
    small = im.convert("L").resize((cols, rows), Image.BOX)
    lines = Image.new("L", (W, H), 0)
    fill = Image.new("L", (W, H), 0)
    dl, df = ImageDraw.Draw(lines), ImageDraw.Draw(fill)
    rnd = random.Random(7)
    for r in range(rows):
        for c in range(cols):
            if small.getpixel((c, r)) / 255 > 0.5 + 0.06 * (rnd.random() * 2 - 1):
                x0, y0 = c * px, r * px
                dl.rectangle([x0, y0, x0 + px, y0 + px], outline=255, width=2)
                df.rectangle([x0, y0, x0 + px, y0 + px], fill=40 + (90 if rnd.random() > 0.97 else 0))
    halo = lines.filter(ImageFilter.GaussianBlur(5))
    out = Image.composite(Image.new("RGB", (W, H), prim), out, fill)
    out = Image.composite(Image.new("RGB", (W, H), prim), out, halo.point(lambda v: int(v * 0.6)))
    return Image.composite(Image.new("RGB", (W, H), (230, 230, 230)), out, lines)


def look_glyph(im, prim, glow, back, rain=False):
    W, H = im.size
    cw, ch = 10, 16
    cols, rows = W // cw + 1, H // ch + 1
    small = im.convert("L").resize((cols, rows), Image.BOX)
    out = Image.new("RGB", (W, H), back)
    # a faint copy of the picture under the characters
    under = toned(im, prim, glow, back).point(lambda v: int(v * 0.2))
    out.paste(under)
    d = ImageDraw.Draw(out)
    f = font(14)
    rnd = random.Random(11)
    heads = {}
    if rain:
        for c in range(cols):
            heads[c] = [(rnd.random() * rows * 1.3, 10 + rnd.random() * 22) for _ in range(2)]
    for r in range(rows):
        for c in range(cols):
            cl = small.getpixel((c, r)) / 255
            b = smooth(0.03, 0.7, cl)
            tip = 0.0
            if rain:
                for head, length in heads[c]:
                    dist = head - r
                    if dist >= 0:
                        b = max(b * 0.9, (1 - smooth(0.0, length, dist)) ** 2 * 0.5)
                        if dist < 1:
                            tip = 0.6
            if b < 0.04 and tip == 0:
                continue
            col = tone(min(1.0, b + tip), prim, glow, back)
            k = 1.8 if b > 0.05 else 1.0
            col = tuple(min(255, int(v * k)) for v in col)
            d.text((c * cw + 1, r * ch), GLYPHS[rnd.randrange(len(GLYPHS))], fill=col, font=f)
    return out


def apply_look(im, look, colours):
    if look not in ("grid", "glyph", "rain") or len(colours) < 3:
        return im
    prim, glow, back = (hexrgb(x) for x in colours)
    if look == "grid":
        return look_grid(im, prim, glow, back)
    if look in ("glyph", "rain"):
        return look_glyph(im, prim, glow, back, rain=look == "rain")
    return im


def main():
    src, mode = os.path.realpath(sys.argv[1]), sys.argv[2]
    look = sys.argv[3] if len(sys.argv) > 6 else "clean"
    colours = sys.argv[4:7] if look != "clean" else []
    if mode not in ("fit", "blur", "stretch", "center", "tile"):
        mode = "fill"
    if mode == "fill" and look == "clean":
        print(src)
        return
    W, H = screen_size()
    st = os.stat(src)
    key = hashlib.md5(f"{src}:{st.st_mtime}:{mode}:{W}x{H}:{look}:{colours}".encode()).hexdigest()[:20]
    os.makedirs(CACHE, exist_ok=True)
    out = os.path.join(CACHE, f"{key}-{mode}-{look}.jpg")
    if not os.path.exists(out):
        tmp = out + ".tmp.jpg"
        if mode == "fill":                               # crop to fill, at the screen's size
            im = Image.open(src).convert("RGB")
            k = max(W / im.width, H / im.height)
            im = im.resize((max(W, round(im.width * k)), max(H, round(im.height * k))), Image.LANCZOS)
            im = im.crop(((im.width - W) // 2, (im.height - H) // 2, (im.width - W) // 2 + W, (im.height - H) // 2 + H))
        else:
            im = render(src, mode, W, H)
        apply_look(im, look, colours).save(tmp, quality=94)
        os.replace(tmp, out)
    # remember where it came from, so the selector still knows what's on screen
    mp = os.path.join(CACHE, "map.json")
    try:
        m = json.load(open(mp))
    except Exception:
        m = {}
    m[out] = {"source": src, "mode": mode, "look": look}
    with open(mp + ".tmp", "w") as f:
        json.dump(m, f)
    os.replace(mp + ".tmp", mp)
    print(out)


if __name__ == "__main__":
    main()
