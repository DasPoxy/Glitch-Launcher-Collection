# Glitch-Background-Selector

![Hand carousel, blur fit](preview.jpg)

An Omarchy wallpaper selector with an old-monitor, glitchy matrix / cyberpunk
feel - a sibling of [Glitch-Theme-Selector](https://github.com/DasPoxy/glitch-theme-selector)
and [Glitch-Globe-Launcher](https://github.com/DasPoxy/glitch-globe-launcher).

- **Your wallpapers, the theme's first**: the current theme's wallpapers
  (yours for it in `~/.config/omarchy/backgrounds/<theme>`, then its own)
  come first, together, marked with a bar; then every image in your
  wallpapers folder (set in the options, a few levels deep). **T** jumps to
  the start of the theme's, **W** to your folder's, **R** to a random one
  (**Shift+R** sets a random one straight away).
- **The monitor**: the highlighted wallpaper on a glowing CRT set,
  materialising as you move to it - plain, or through a grid, glyph or code
  rain look (Tab).
- **The readout**: its name, folder, section, size and shape, and its
  colours (the eight that stand out, most common first).
- **The look on your desktop too** (options > Desktop look): **Baked**
  renders the monitor's look (grid, glyph or rain) into the picture when
  you set it - free, but a still; **Live** draws it over the wallpaper as it
  is on the monitor, animated (about 30 fps for rain, slower for the rest),
  on a click-through layer just above the wallpaper, paused whenever a
  window on that screen is fullscreen. Either way in the picture's colours.
- **The whole UI wears the highlighted wallpaper's colours**, easing across
  as you browse.
- **The carousel**: arc, line, hand, ring, panorama, triple, grid, pills or
  blips (options). Arrows, the wheel or a click browse; **/** filters.
- **Set it**: Enter (or a click on the highlighted card) runs
  `omarchy theme bg set` - with a hard glitch - and the selector stays open.
- **The feel**: CRT scanlines and phosphor mask (Ctrl+T), the screen acting
  up now and then, a light glitch as you browse, and glitching in over your
  desktop and back out to it.

**Options** (Ctrl+, or the button top right): the wallpapers folder, how
the wallpaper fits the screen (fill, fit, blur fit, stretch, center, tile -
anything but fill is rendered at the screen's size by `render-bg.py`, since
the shell always crops to fill), the carousel style, the monitor's look, CRT on / off, glitches normal / subtle /
off, the open / close glitch, and whether setting a wallpaper leaves it open
or glitches out to the desktop. Kept in
`~/.config/glitch-background-selector/settings.json`.

## Install

```sh
omarchy plugin add https://github.com/DasPoxy/glitch-background-selector --enable
```

Then bind a key for it in `~/.config/hypr/bindings.lua` - for example in
place of Omarchy's background switcher:

```lua
hl.unbind("SUPER + CTRL + SPACE")
o.bind("SUPER + CTRL + SPACE", "Glitch-Background-Selector", "omarchy-shell shell toggle glitch-background-selector '{}'")
```

Or open it with `omarchy-shell shell toggle glitch-background-selector '{}'`.

Needs Python 3 with Pillow (`python-pillow`) for wallpaper colours, fits and
baked looks. Optional: `noto-fonts-cjk` for the glyph and rain looks'
katakana.

It's one of four in
[Glitch-Launcher-Collection](https://github.com/DasPoxy/Glitch-Launcher-Collection),
whose installer can add any or all of them and bind their keys for you.

## Uninstall

```sh
omarchy plugin remove glitch-background-selector
```

Then take its lines out of `~/.config/hypr/bindings.lua` - the `hl.unbind`
too, so Omarchy's own key for it works again. Its settings
(`~/.config/glitch-background-selector`) and cache
(`~/.cache/glitch-background-selector`) are left; delete them
too if you want them gone.

A baked or rendered wallpaper it set stays your wallpaper; pick another with
Omarchy's background switcher.

## How it works

`backgrounds.py` lists the wallpapers as JSON; `palette.py` reads one's size
and colours (cached in `~/.cache/glitch-background-selector`). The shaders
in `shaders/` are shared with Glitch-Theme-Selector and Globe-Launcher;
after editing one, recompile it with
`/usr/lib/qt6/bin/qsb --qt6 -o shaders/X.frag.qsb shaders/X.frag`.

## License

MIT
