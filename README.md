# Matrix-Theme-Select

An Omarchy theme selector with an old-monitor, matrix / cyberpunk feel - a
sibling of [Globe-Launcher](https://github.com/DasPoxy/globe-launcher).

- **The monitor**: the highlighted theme's preview on a glowing CRT set,
  materialising as you move to it - plain, or through a grid, glyph or code
  rain look (Tab). Themes without a preview show their palette as colour bars.
- **The arc**: every theme as a card on a cover-flow arc, its palette in a
  strip along the bottom; arrows, the wheel or a click browse, typing filters.
- **The readout**: the theme's name, slug, mode, whether it's stock or
  installed and running, its whole palette (every colour by name and hex,
  typing in row by row) and its backgrounds.
- **Apply**: Enter (or a click on the highlighted card) runs
  `omarchy theme set` - with a hard glitch - and the selector stays open, so
  you can try another.
- **The whole UI wears the highlighted theme**: text, borders, panels, the
  sky, the glitches - everything eases into its palette as you browse.
- **The feel**: a starfield and nebula, CRT
  scanlines and phosphor mask (Ctrl+T), the screen acting up now and then, a
  light glitch as you browse, and glitching in over your desktop and back
  out to it.

Settings (CRT, look) are kept in `~/.config/matrix-theme-select/settings.json`.

## Install

```sh
omarchy plugin add https://github.com/DasPoxy/matrix-theme-select.git --enable
```

Open it with:

```sh
omarchy-shell shell toggle matrix-theme-select '{}'
```

and give it a key in `~/.config/hypr/bindings.lua`, for example:

```lua
o.bind("SUPER + ALT + SHIFT + SPACE", "Matrix-Theme-Select", "omarchy-shell shell toggle matrix-theme-select '{}'")
```

## How it works

`themes.py` lists the themes (user-installed ones over stock, file by file,
with older themes' palettes read from their `alacritty.toml`) as JSON. The
shaders in `shaders/` (starfield, nebula, preview looks, glitch / CRT /
transitions) are shared with Globe-Launcher; after editing one, recompile it:

```sh
/usr/lib/qt6/bin/qsb --qt6 -o shaders/glitch.frag.qsb shaders/glitch.frag
```

## License

MIT
