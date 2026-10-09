#!/usr/bin/env python3
"""Glitch-Globe-Launcher's 3D model preview: a turntable of a model, rendered to PNG
frames (grey, lit, transparent background - the preview shader colours them).

    render-model.py MODEL CACHE_DIR

Reads STL (binary or ASCII), 3MF and OBJ. Prints "tris N" once the model is
read, then the path of each frame as it's written; frames are cached in
CACHE_DIR/<key>/ and a later run just prints them again.

No numpy here, so: a model of up to MAX_POLY triangles is drawn as polygons,
far to near (painter's algorithm); a denser one is sampled down to
MAX_SPLAT triangles and drawn as splats into a depth buffer, which keeps its
surface solid at preview size.
"""
import hashlib
import math
import os
import re
import struct
import sys
import zipfile

from PIL import Image, ImageDraw, ImageFilter

FRAMES = 24
SIZE = 520
MAX_POLY = 20000
MAX_SPLAT = 160000
ELEVATION = math.radians(24)


# ------------------------------------------------------------------ readers
def read_stl(path):
    with open(path, "rb") as f:
        data = f.read()
    if len(data) >= 84:
        n = struct.unpack_from("<I", data, 80)[0]
        if 84 + n * 50 == len(data):
            step = max(1, n // MAX_SPLAT) if n > MAX_POLY else 1
            tris = []
            for i in range(0, n, step):
                v = struct.unpack_from("<9f", data, 84 + i * 50 + 12)
                tris.append((v[0:3], v[3:6], v[6:9]))
            return tris, n
    text = data.decode("ascii", "ignore")
    vs = [tuple(map(float, m)) for m in re.findall(
        r"vertex\s+(\S+)\s+(\S+)\s+(\S+)", text)]
    tris = [(vs[i], vs[i + 1], vs[i + 2]) for i in range(0, len(vs) - 2, 3)]
    return tris, len(tris)


def read_3mf(path):
    tris = []
    with zipfile.ZipFile(path) as z:
        names = [n for n in z.namelist() if n.lower().endswith(".model")]
        for name in names:
            if z.getinfo(name).file_size > 600_000_000:     # a zip bomb, or far too big to preview
                raise ValueError("model too large to preview")
            xml = z.read(name).decode("utf-8", "ignore")
            for obj in re.findall(r"<(?:\w+:)?mesh>(.*?)</(?:\w+:)?mesh>", xml, re.S):
                verts = [tuple(float(a) for a in m) for m in re.findall(
                    r'<(?:\w+:)?vertex\s+x="([^"]+)"\s+y="([^"]+)"\s+z="([^"]+)"', obj)]
                for m in re.findall(r'<(?:\w+:)?triangle\s+v1="(\d+)"\s+v2="(\d+)"\s+v3="(\d+)"', obj):
                    a, b, c = (int(x) for x in m)
                    if max(a, b, c) < len(verts):
                        tris.append((verts[a], verts[b], verts[c]))
    n = len(tris)
    if n > MAX_POLY:
        step = max(1, n // MAX_SPLAT)
        tris = tris[::step]
    return tris, n


def read_obj(path):
    verts, tris = [], []
    with open(path, errors="ignore") as f:
        for line in f:
            if line.startswith("v "):
                p = line.split()
                verts.append((float(p[1]), float(p[2]), float(p[3])))
            elif line.startswith("f "):
                idx = [int(t.split("/")[0]) for t in line.split()[1:]]
                idx = [i - 1 if i > 0 else len(verts) + i for i in idx]
                for k in range(1, len(idx) - 1):
                    tris.append((verts[idx[0]], verts[idx[k]], verts[idx[k + 1]]))
    # OBJ is usually Y-up; the rest of this treats Z as up
    tris = [tuple((v[0], -v[2], v[1]) for v in t) for t in tris]
    n = len(tris)
    if n > MAX_POLY:
        tris = tris[::max(1, n // MAX_SPLAT)]
    return tris, n


# ------------------------------------------------------------------ drawing
def normalise(tris):
    xs = [v[0] for t in tris for v in t]
    ys = [v[1] for t in tris for v in t]
    zs = [v[2] for t in tris for v in t]
    cx, cy, cz = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2
    r = max(math.sqrt((v[0] - cx) ** 2 + (v[1] - cy) ** 2 + (v[2] - cz) ** 2) for t in tris for v in t) or 1
    return [tuple(((v[0] - cx) / r, (v[1] - cy) / r, (v[2] - cz) / r) for v in t) for t in tris]


def shade_of(n, view_n):
    # a key light from the upper left, a fill, and a rim
    lx, ly, lz = -0.62, 0.55, 0.56
    d = max(0.0, n[0] * lx + n[1] * ly + n[2] * lz)
    rim = (1 - abs(view_n)) ** 3
    return min(1.0, 0.1 + 0.8 * d ** 1.4 + 0.3 * rim)


def project(tris, angle):
    """Turn about the model's up (Z), tilt toward the camera; screen x, y, depth."""
    ca, sa = math.cos(angle), math.sin(angle)
    ce, se = math.cos(ELEVATION), math.sin(ELEVATION)
    half = SIZE / 2
    scale = SIZE * 0.46
    out = []
    for t in tris:
        pts = []
        for x, y, z in t:
            x1, y1 = x * ca - y * sa, x * sa + y * ca          # turntable
            yv, zv = z * ce - y1 * se, z * se + y1 * ce         # camera tilt: zv toward viewer
            pts.append((half + x1 * scale, half - yv * scale, zv))
        out.append(pts)
    return out


def tri_normal(p):
    (x0, y0, z0), (x1, y1, z1), (x2, y2, z2) = p
    ax, ay, az = x1 - x0, y1 - y0, z1 - z0
    bx, by, bz = x2 - x0, y2 - y0, z2 - z0
    nx, ny, nz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
    ln = math.sqrt(nx * nx + ny * ny + nz * nz) or 1
    return nx / ln, ny / ln, nz / ln


def render_poly(tris, angle):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    faces = []
    for p in project(tris, angle):
        # normal in screen space (y down), facing the viewer when z > 0
        q = [(x, -y, z / 1.0 * (SIZE * 0.46)) for x, y, z in p]
        n = tri_normal(q)
        depth = (p[0][2] + p[1][2] + p[2][2]) / 3
        faces.append((depth, p, n))
    faces.sort(key=lambda f: f[0])
    for depth, p, n in faces:
        nz = n[2]
        if nz < 0:                     # wound the other way: flip it
            n = (-n[0], -n[1], -nz)
            nz = -nz
        g = int(255 * shade_of((n[0], n[1], n[2]), nz))
        draw.polygon([(p[0][0], p[0][1]), (p[1][0], p[1][1]), (p[2][0], p[2][1])], fill=(g, g, g, 255))
    return img


def render_splat(tris, angle):
    # depth buffer at half size, a splat per triangle, then smoothed up
    s = SIZE // 2
    depth = [-1e9] * (s * s)
    shade = [0] * (s * s)
    for p in project(tris, angle):
        q = [(x, -y, z * (SIZE * 0.46)) for x, y, z in p]
        n = tri_normal(q)
        if n[2] < 0:
            n = (-n[0], -n[1], -n[2])
        cx = (p[0][0] + p[1][0] + p[2][0]) / 6
        cy = (p[0][1] + p[1][1] + p[2][1]) / 6
        z = (p[0][2] + p[1][2] + p[2][2]) / 3
        g = int(255 * shade_of(n, n[2]))
        ix, iy = int(cx), int(cy)
        for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1)):
            x, y = ix + dx, iy + dy
            if 0 <= x < s and 0 <= y < s:
                i = y * s + x
                if z > depth[i]:
                    depth[i] = z
                    shade[i] = g
    lum = Image.new("L", (s, s))
    lum.putdata(shade)
    alpha = Image.new("L", (s, s))
    alpha.putdata([255 if d > -1e9 else 0 for d in depth])
    lum = lum.filter(ImageFilter.MedianFilter(3))
    img = Image.merge("RGBA", (lum, lum, lum, alpha))
    return img.resize((SIZE, SIZE), Image.LANCZOS)


def main():
    path, cache = sys.argv[1], sys.argv[2]
    st = os.stat(path)
    key = hashlib.md5(f"{path}:{st.st_mtime}:{st.st_size}:{FRAMES}:{SIZE}".encode()).hexdigest()[:20]
    out = os.path.join(cache, key)
    done = os.path.join(out, "done")
    if os.path.exists(done):
        with open(done) as f:
            print(f.read().strip(), flush=True)
        for i in range(FRAMES):
            print(os.path.join(out, f"{i:02d}.png"), flush=True)
        return
    os.makedirs(out, exist_ok=True)

    ext = path.lower().rsplit(".", 1)[-1]
    reader = {"stl": read_stl, "3mf": read_3mf, "obj": read_obj}.get(ext)
    if not reader:
        print("error unsupported", flush=True)
        return
    try:
        tris, total = reader(path)
    except Exception as e:                    # broken or hostile files: say so, don't hang the preview
        print(f"error can't read this model ({type(e).__name__})", flush=True)
        return
    if not tris:
        print("error no triangles", flush=True)
        return
    print(f"tris {total}", flush=True)
    tris = normalise(tris)
    render = render_poly if len(tris) <= MAX_POLY else render_splat
    for i in range(FRAMES):
        frame = os.path.join(out, f"{i:02d}.png")
        tmp = frame + ".tmp.png"
        render(tris, 2 * math.pi * i / FRAMES).save(tmp)
        os.replace(tmp, frame)
        print(frame, flush=True)
    with open(done, "w") as f:
        f.write(f"tris {total}\n")


if __name__ == "__main__":
    main()
