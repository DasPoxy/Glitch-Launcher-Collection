"""Tests for the collection's helper scripts, each run the way its component
runs it (a separate process) in a throwaway home. Pillow is needed for the
picture helpers. Run: python3 -m unittest discover -s tests"""
import json
import os
import struct
import subprocess
import sys
import tempfile
import unittest
import zipfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
try:
    from PIL import Image
except ImportError:   # pragma: no cover
    Image = None


def helper(component, script):
    return os.path.join(REPO, component, script)


class Home(unittest.TestCase):
    """A fresh home for each test, with an empty PATH for Omarchy's tools."""

    def setUp(self):
        self.home = tempfile.mkdtemp(prefix="glitch-test-")
        self.env = dict(os.environ, HOME=self.home, OMARCHY_PATH=os.path.join(self.home, "omarchy"),
                        XDG_CONFIG_HOME="", XDG_CACHE_HOME="")
        self.env.pop("XDG_CONFIG_HOME")
        self.env.pop("XDG_CACHE_HOME")

    def path(self, *parts):
        p = os.path.join(self.home, *parts)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        return p

    def write(self, rel, text):
        with open(self.path(rel), "w") as f:
            f.write(text)
        return self.path(rel)

    def picture(self, rel, size=(64, 36), colour=(200, 40, 120)):
        p = self.path(rel)
        Image.new("RGB", size, colour).save(p)
        return p

    def run_json(self, args, **kw):
        r = subprocess.run([sys.executable] + args, capture_output=True, text=True, env=self.env, timeout=120, **kw)
        self.assertEqual(r.returncode, 0, r.stderr)
        return json.loads(r.stdout)

    def run_lines(self, args):
        r = subprocess.run(args, capture_output=True, text=True, env=self.env, timeout=120)
        return r.returncode, r.stdout.strip().split("\n")


class Themes(Home):
    def test_user_theme_overrides_stock_file_by_file(self):
        self.write("omarchy/themes/neon/colors.toml", 'mode = "dark"\naccent = "#ff00aa"\nbackground = "#000000"\n')
        self.picture("omarchy/themes/neon/preview.png")
        # the user's copy only overrides one file: the rest comes from stock
        self.write(".config/omarchy/themes/neon/shell.toml", "x = 1\n")
        # an old-style theme: a palette in alacritty.toml only
        self.write("omarchy/themes/retro/alacritty.toml", '[colors.primary]\nbackground = "0x101010"\nforeground = "0xeeeeee"\n')
        self.write(".config/omarchy/themes/.backup-stuff/colors.toml", "")
        out = {t["slug"]: t for t in self.run_json([helper("glitch-theme-selector", "themes.py")])}
        self.assertEqual(sorted(out), ["neon", "retro"])          # hidden folders skipped
        self.assertTrue(out["neon"]["user"])
        self.assertIn(["accent", "#ff00aa"], out["neon"]["colors"])
        self.assertTrue(out["neon"]["preview"].endswith("preview.png"))
        self.assertIn(["background", "#101010"], out["retro"]["colors"])


@unittest.skipIf(Image is None, "needs Pillow")
class Backgrounds(Home):
    def test_theme_first_then_folder(self):
        self.write(".local/state/omarchy/current/theme.name", "neon\n")
        self.picture(".local/state/omarchy/current/theme/backgrounds/b.png")
        self.picture(".config/omarchy/backgrounds/neon/a.png")
        self.picture("Wallpapers/z.png")
        self.picture("Wallpapers/deeper/y.jpg")
        self.write("Wallpapers/notes.txt", "x")
        out = self.run_json([helper("glitch-background-selector", "backgrounds.py"), self.path("Wallpapers")])
        names = [(i["section"], i["name"]) for i in out["items"]]
        # the theme's own first; then the folder's, its own files before its subfolders'
        self.assertEqual(names, [("theme", "a.png"), ("theme", "b.png"), ("folder", "z.png"), ("folder", "y.jpg")])

    def test_palette_and_bad_files(self):
        pic = self.picture("p.png", size=(80, 40))
        out = self.run_json([helper("glitch-background-selector", "palette.py"), pic])
        self.assertEqual((out["w"], out["h"]), (80, 40))
        self.assertTrue(out["colors"][0].startswith("#"))
        bad = self.write("not-a-picture.png", "nope")
        out = self.run_json([helper("glitch-background-selector", "palette.py"), bad])
        self.assertEqual(out["colors"], [])                         # reported, not a crash

    def test_fits_and_looks_render_at_screen_size(self):
        pic = self.picture("p.png", size=(300, 100))
        # no hyprctl here: the renderer falls back to 2560x1440
        for args in (["fit"], ["blur"], ["stretch"], ["center"], ["tile"], ["fill", "glyph", "#ff00aa", "#5500aa", "#000000"],
                     ["stretch", "clean", "#111111", "#222222", "#333333"]):
            r = subprocess.run([sys.executable, helper("glitch-background-selector", "render-bg.py"), pic] + args,
                               capture_output=True, text=True, env=self.env, timeout=120)
            self.assertEqual(r.returncode, 0, (args, r.stderr))
            with Image.open(r.stdout.strip()) as im:
                self.assertEqual(im.size, (2560, 1440), args)
        # plain fill and no look: the picture itself, untouched
        r = subprocess.run([sys.executable, helper("glitch-background-selector", "render-bg.py"), pic, "fill"],
                           capture_output=True, text=True, env=self.env)
        self.assertEqual(r.stdout.strip(), os.path.realpath(pic))


class Models(Home):
    def stl(self, rel, tris):
        data = b"\0" * 80 + struct.pack("<I", len(tris))
        for t in tris:
            data += struct.pack("<12fH", 0, 0, 1, *t[0], *t[1], *t[2], 0)
        p = self.path(rel)
        with open(p, "wb") as f:
            f.write(data)
        return p

    def frames(self, model):
        cache = self.path("cache/models")
        code, out = self.run_lines([sys.executable, helper("glitch-globe-launcher", "render-model.py"), model, cache])
        return code, out

    @unittest.skipIf(Image is None, "needs Pillow")
    def test_stl_obj_3mf_render(self):
        tri = [((0, 0, 0), (1, 0, 0), (0, 1, 1))]
        obj = self.write("m.obj", "v 0 0 0\nv 1 0 0\nv 0 1 1\nf 1 2 3\n")
        mf = self.path("m.3mf")
        with zipfile.ZipFile(mf, "w") as z:
            z.writestr("3D/3dmodel.model", '<model><mesh><vertices><vertex x="0" y="0" z="0"/><vertex x="1" y="0" z="0"/>'
                                           '<vertex x="0" y="1" z="1"/></vertices><triangles><triangle v1="0" v2="1" v3="2"/>'
                                           '</triangles></mesh></model>')
        for model in (self.stl("m.stl", tri), obj, mf):
            code, out = self.frames(model)
            self.assertEqual(code, 0, model)
            self.assertEqual(out[0], "tris 1", model)
            self.assertEqual(len(out), 25, model)                    # tris + 24 frames
            self.assertTrue(os.path.isfile(out[1]))

    def test_broken_models_report_errors(self):
        for name, body in (("bad.obj", "v 0 0 0\nf 1 2 9\n"), ("bad.3mf", "not a zip")):
            code, out = self.frames(self.write(name, body))
            self.assertEqual(code, 0, name)
            self.assertTrue(out[0].startswith("error"), (name, out))


class Previews(Home):
    """preview.sh keeps secrets off the screen."""

    def preview(self, rel, text):
        f = self.write(rel, text)
        code, out = self.run_lines(["bash", helper("glitch-globe-launcher", "preview.sh"), f, self.path("thumbs")])
        self.assertEqual(code, 0)
        return out

    def test_secrets_hidden(self):
        secret = "s3cr3t-" + "q" * 30
        for rel, text in (("Documents/client_secret_123.json", '{"client_secret": "%s"}' % secret),
                          ("notes/id_ed25519", secret),
                          ("notes/key.txt", "-----BEGIN OPENSSH PRIVATE KEY-----\n%s\n" % secret),
                          ("notes/env.txt", "GITHUB_TOKEN=ghp_%s\n" % ("a" * 36) + secret + "\n"),
                          ("notes/creds.md", "password = %s\n" % secret)):
            out = self.preview(rel, text)
            self.assertNotIn(secret, "\n".join(out), rel)          # never on screen

    def test_ordinary_text_shown(self):
        out = self.preview("notes/plan.md", "# My plan\nthe secret ingredient is love\n")
        self.assertEqual(out[0].split("\t")[1], "text")
        self.assertIn("# My plan", out)


class Eggs(unittest.TestCase):
    def test_every_component_has_the_shared_eggs(self):
        with open(os.path.join(REPO, "eggs.js")) as f:
            shared = f.read()
        for comp in ("glitch-globe-launcher", "glitch-theme-selector", "glitch-background-selector", "glitch-overview"):
            with open(os.path.join(REPO, comp, "eggs.js")) as f:
                self.assertEqual(f.read(), shared, comp + "/eggs.js differs from eggs.js")


class Shaders(unittest.TestCase):
    def test_no_const_arrays(self):
        # the GL driver rejects them at runtime (the effect just vanishes)
        import glob
        import re
        for f in glob.glob(os.path.join(REPO, "*", "shaders", "*.frag")):
            with open(f) as h:
                self.assertIsNone(re.search(r"\bconst\s+\w+\s+\w+\s*\[", h.read()), f)


if __name__ == "__main__":
    unittest.main()
