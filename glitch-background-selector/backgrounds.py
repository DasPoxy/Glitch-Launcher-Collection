#!/usr/bin/env python3
"""Glitch-Background-Selector's catalogue, as JSON.

    backgrounds.py [FOLDER]

{theme, current, items: [{path, name, section, dir}]} - the current theme's
wallpapers first (your own for it in ~/.config/omarchy/backgrounds/<theme>,
then the theme's, sorted, as Omarchy cycles them), then the images under
FOLDER (a few levels deep, sorted by path), each listed once.
"""
import json
import os
import sys

HOME = os.path.expanduser("~")
STATE = os.path.join(HOME, ".local/state/omarchy/current")
IMAGES = (".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp")
MAX_DEPTH = 3
MAX_FOLDER = 3000


def images_in(d):
    try:
        return sorted(os.path.join(d, f) for f in os.listdir(d)
                      if f.lower().endswith(IMAGES) and os.path.isfile(os.path.join(d, f)))
    except OSError:
        return []


def walk(root):
    out = []
    root = os.path.realpath(os.path.expanduser(root))
    base_depth = root.rstrip("/").count("/")
    for d, dirs, files in os.walk(root, followlinks=True):
        if d.count("/") - base_depth >= MAX_DEPTH:
            dirs[:] = []
        dirs[:] = sorted(x for x in dirs if not x.startswith("."))
        for f in sorted(files):
            if f.lower().endswith(IMAGES):
                out.append(os.path.join(d, f))
                if len(out) >= MAX_FOLDER:
                    return out
    return out


def main():
    folder = sys.argv[1] if len(sys.argv) > 1 else ""
    try:
        theme = open(os.path.join(STATE, "theme.name")).read().strip()
    except OSError:
        theme = ""
    try:
        current = os.path.realpath(os.readlink(os.path.join(STATE, "background")))
    except OSError:
        current = ""
    # a picture set in another fit is a rendered copy: report the original
    mode, look = "fill", "clean"
    try:
        hit = json.load(open(os.path.expanduser("~/.cache/glitch-background-selector/rendered/map.json"))).get(current)
        if hit:
            current, mode, look = hit["source"], hit["mode"], hit.get("look", "clean")
    except (OSError, ValueError):
        pass
    seen, items = set(), []

    def add(path, section):
        real = os.path.realpath(path)
        if real in seen:
            return
        seen.add(real)
        items.append({"path": real, "name": os.path.basename(real), "section": section,
                      "dir": os.path.dirname(real).replace(HOME, "~", 1)})

    themed = images_in(os.path.join(HOME, ".config/omarchy/backgrounds", theme)) + images_in(os.path.join(STATE, "theme/backgrounds"))
    for p in sorted(themed, key=lambda p: os.path.basename(p)):
        add(p, "theme")
    if folder:
        for p in walk(folder):
            add(p, "folder")
    print(json.dumps({"theme": theme, "current": current, "mode": mode, "look": look, "folder": folder, "items": items}))


if __name__ == "__main__":
    main()
