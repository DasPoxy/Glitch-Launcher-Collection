# Glitch-Globe-Launcher

![Holo Earth](preview.jpg)
![Unicron](screenshots/globe-unicron.jpg)
![Bestagon](screenshots/globe-hex.jpg)
![File preview](screenshots/globe-files.jpg)

A full-screen app launcher for [Omarchy](https://omarchy.org): your installed
apps, projected out from a spinning dot-globe over a starfield, with the feel
of being jacked into a terminal.

- **The globe**, in one of nine styles (or **random**: a different one each
  time it opens): glowing rings of **dots**, a
  **wireframe**, **binary** (a skin of flickering 0s and 1s, light rays
  round the rim), **code earth** (the continents built of matrix glyphs,
  debris drifting about) or **holo earth** (dotted continents, lit
  coastlines, satellites on orbit rings), **unicron** (an armoured
  planet-eater of raised, bevelled, riveted plates engraved with circuitry,
  torn open in three ragged wounds that crumble into glowing machinery and
  shed tumbling debris; a cratered cap with a trench across it, a belt with antennae,
  a glowing eye-vent, a mouth firing a beam as it turns, between two great segmented jaws
  that curve out past the rim and hook round the beam, a ring of
  lights round it) or a **dyson sphere** (a lattice shell round a star, its light
  escaping through the gaps), **matrix rain** (code falling down the sphere in
  columns) or **bestagon** (a Goldberg sphere of whole glass hex tiles - and the
  twelve pentagons any such sphere needs - with glowing edges and data points,
  the far side's lattice showing through, solid tiles popped out, loose ones
  drifting off the edge). Its far side shows faintly
  through, with a rim glow and a halo. Every app sits on it, evenly
  spread, and is projected out on a beam.
- **Spin it**: drag (it keeps its momentum), scroll to zoom, or leave it to
  turn by itself. Whatever faces you is selected: it bulges out and unfolds
  its name; a card at the bottom shows its logo and description.
- **Keyboard**: arrow keys hop to the nearest app that way, typing filters,
  Enter launches, Esc clears the search or closes.
- **Omarchy updates**: when one is waiting (the same check as the bar's
  update icon) it shows top left; Ctrl+U or a click on it opens Omarchy's
  updater.
- **Opening and closing**: the launcher glitches in over your desktop (captured as it
  opens) in one of the enabled glitch kinds - torn bands, blocks, a rolling
  VHS band, a CRT switching off and on, dripping columns, a negative flash -
  and glitches back out to it when it closes (a random kind each time).
- **CRT monitor** (toggle): heavier scanlines, an aperture-grille mask, dark
  rounded glass corners (the picture isn't bent, so clicks stay true), a faint rolling bar and flicker.
- **Atmosphere**: a full-resolution starfield under a nebula (swirling gas
  and near dust lanes and motes, sliding past one another in parallax as the
  globe turns and the mouse moves; toggle it in the options), and now and then a glitch, one of:
  tear, blocks (datamosh), VHS, CRT collapse, code bleed or invert (pick
  which in the options) - and a terminal in the corner types a line. Linger on a selection for a
  few seconds and it scans it: an app's description, categories and command;
  a file's type, size, length or pixels, folder; a command's arguments.
- **Network traffic**: your real throughput (from `/proc/net/dev`), as
  **particles** - packets of light streaming in to the globe (downloads) and
  out of it (uploads), with static crackling over the screen - or as
  **orbits** - rings round the globe with packets riding them, more rings and
  faster the busier it is. Or off.
  The rates show under the prompt.
- **Space traffic**: shooting stars streak past, a comet now and then, and
  spacecraft (fighters, freighters, satellites, sometimes a formation)
  cross the sky in the distance.
- **`>` Omarchy commands**: type `>` to see every action in the Omarchy menu
  (its glyphs on the globe, `Trigger › Capture › Screenshot` on the card);
  keep typing to search those and all of `omarchy commands`. Enter runs the
  selected one (Shift+Enter runs it in a floating terminal); a command that
  needs arguments fills the prompt first so you can type them.
- **`/` files**: type `/` to fuzzy-find files in your home, `~/.config` and
  `~/.local/bin` (`fd` + `fzf`). Enter opens the file, Shift+Enter its folder.
  A terminal pane beside the globe previews the selected one: pictures,
  videos (muted, looping) and PDFs' first pages through a look you cycle with
  Tab - clean, grid (duotone with glowing traced blocks), glyph (a mosaic of
  characters) or rain (code falling through it) - and text files' first
  lines, archives' contents, audio tags. 3D models (STL, 3MF, OBJ) spin on a
  turntable rendered by `render-model.py` (Python + Pillow, cached in
  `~/.cache/glitch-globe-launcher/models`), through the same looks.
- **Options** (Ctrl+, or the button top right): colours from your Omarchy
  theme, a prebuilt theme (Matrix, Cyber, Ice, Amber, Mono) or your own,
  the globe's style, auto-spin, nebula, network and space traffic, the preview's look, and glitches normal / subtle / off and which kinds. Saved in
  `~/.config/glitch-globe-launcher/settings.json`.

Clicking the selected app (or Enter) launches it and closes the launcher;
clicking another app turns the globe to it.

## Install

```sh
omarchy plugin add https://github.com/DasPoxy/glitch-globe-launcher --enable
```

Then bind a key for it in `~/.config/hypr/bindings.lua` - for example in
place of the Omarchy menu, which this moves to Super + Ctrl + Alt + Space:

```lua
hl.unbind("SUPER + SPACE")
o.bind("SUPER + SPACE", "Glitch-Globe-Launcher", "omarchy-shell shell toggle glitch-globe-launcher '{}'")
o.bind("SUPER + CTRL + ALT + SPACE", "Omarchy menu", "omarchy-menu toggle")
```

Or open it with `omarchy-shell shell toggle glitch-globe-launcher '{}'`.

Needs `fd` and `fzf` for the `/` file search, and Python 3 with Pillow
(`python-pillow`) for 3D model previews. Optional, for richer previews:
`ffmpeg` (video and audio details), `poppler` (PDF pages), `libarchive`
(what's in an archive), `qt6-multimedia` (video), `noto-fonts-cjk` (the
glyph and rain looks' katakana).

It's one of four in
[Glitch-Launcher-Collection](https://github.com/DasPoxy/Glitch-Launcher-Collection),
whose installer can add any or all of them and bind their keys for you.

## Uninstall

```sh
omarchy plugin remove glitch-globe-launcher
```

Then take its lines out of `~/.config/hypr/bindings.lua` - the `hl.unbind`
too, so Omarchy's own key for it works again. Its settings
(`~/.config/glitch-globe-launcher`) and cache
(`~/.cache/glitch-globe-launcher`) are left; delete them
too if you want them gone.

## How it's drawn

Small GPU shaders (`shaders/`, compiled to `.qsb` with Qt's `qsb`):
the starfield, the globe (each pixel finds its point on the sphere, turns it
back by the globe's rotation and measures the distance to the nearest dot on
the rings of latitude), the file preview's looks, and the glitch pass over
everything. The apps come
from the same desktop entries every launcher reads; their places on the globe
are a Fibonacci sphere, projected with the same rotation the shader uses.

After editing a shader, recompile it:

```sh
/usr/lib/qt6/bin/qsb --qt6 -o shaders/globe.frag.qsb shaders/globe.frag
```

## License

MIT

The earth styles' map (`land.png`) is rasterised from
[Natural Earth](https://www.naturalearthdata.com/)'s 1:50m land, which is
in the public domain.
