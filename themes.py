#!/usr/bin/env python3
"""Matrix-Theme-Select's catalogue: every Omarchy theme as JSON.

    themes.py

One object per theme, sorted by name:
    {slug, name, dir, user, mode, preview, backgrounds: [...], colors: [[key, hex], ...], current}
A user-installed theme (~/.config/omarchy/themes) wins over the stock one of
the same slug, file by file (a user folder may only override a few). Colours come from colors.toml in
file order; previews from preview.png / preview.jpg (or the first background).
"""
import json
import os
import re
import subprocess

HOME = os.path.expanduser("~")
USER_DIR = os.path.join(HOME, ".config/omarchy/themes")
STOCK_DIR = os.path.join(os.environ.get("OMARCHY_PATH", "/usr/share/omarchy"), "themes")
IMAGE = re.compile(r"\.(png|jpe?g|webp|gif|bmp)$", re.I)


def title(slug):
    return " ".join(w[:1].upper() + w[1:] for w in slug.split("-"))


def colours(path):
    out, mode = [], "dark"
    try:
        with open(path) as f:
            for line in f:
                m = re.match(r'\s*([A-Za-z0-9_]+)\s*=\s*"([^"]*)"', line)
                if not m:
                    continue
                key, value = m.groups()
                if key == "mode":
                    mode = value
                elif re.fullmatch(r"#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?", value):
                    out.append([key, value])
    except OSError:
        pass
    return out, mode


def alacritty_colours(path):
    """older themes have no colors.toml: their terminal palette stands in"""
    try:
        import tomllib
        with open(path, "rb") as f:
            data = tomllib.load(f).get("colors", {})
    except Exception:
        return []
    out = []
    for group, prefix in (("primary", ""), ("normal", ""), ("bright", "bright_"), ("selection", "selection_")):
        for key, value in (data.get(group) or {}).items():
            if isinstance(value, str):
                value = value.replace("0x", "#")
                if re.fullmatch(r"#[0-9a-fA-F]{6}", value):
                    out.append([prefix + key, value])
    return out


def current_slug():
    try:
        name = subprocess.run(["omarchy-theme-current"], capture_output=True, text=True, timeout=3).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""
    return name.lower().replace(" ", "-")


def main():
    # each slug's folders, user copy first: a user folder may only override a
    # few files (a shell.toml, say), so each file falls back to the stock one
    found = {}
    for base, user in ((USER_DIR, True), (STOCK_DIR, False)):
        try:
            names = os.listdir(base)
        except OSError:
            continue
        for slug in names:
            if slug.startswith("."):                    # backups and the like
                continue
            d = os.path.join(base, slug)
            if os.path.isdir(d):                         # (skips broken links)
                found.setdefault(slug, []).append((os.path.realpath(d), user))
    now = current_slug()
    out = []
    for slug, dirs in sorted(found.items()):
        def first(*names):
            for d, _ in dirs:
                for n in names:
                    if os.path.isfile(os.path.join(d, n)):
                        return os.path.join(d, n)
            return ""
        cols, mode = colours(first("colors.toml"))
        if not cols:
            cols = alacritty_colours(first("alacritty.toml"))
            mode = "light" if "light" in slug else "dark"
        bgs = []
        for d, _ in dirs:
            bgdir = os.path.join(d, "backgrounds")
            try:
                bgs = sorted(os.path.join(bgdir, f) for f in os.listdir(bgdir) if IMAGE.search(f))
            except OSError:
                bgs = []
            if bgs:
                break
        preview = first("preview.png", "preview.jpg", "preview.jpeg", "preview.webp", "theme.png") or (bgs[0] if bgs else "")
        out.append({"slug": slug, "name": title(slug), "dir": dirs[0][0], "user": dirs[0][1], "mode": mode,
                    "preview": preview, "backgrounds": bgs[:6], "colors": cols,
                    "current": slug == now})
    print(json.dumps(out))


if __name__ == "__main__":
    main()
