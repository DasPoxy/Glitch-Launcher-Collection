# Glitch-Theme-Selector

An Omarchy theme selector with an old-monitor, matrix / cyberpunk feel - a
sibling of [Glitch-Globe-Launcher](../glitch-globe-launcher).

- **The monitor**: the highlighted theme's preview on a glowing CRT set,
  materialising as you move to it - plain, or through a grid, glyph or code
  rain look (Tab). Themes without a preview show their palette as colour bars.
- **The carousel**: every theme as a card, its palette in a strip along the
  bottom, in one of nine styles (options): arc (cover flow), line, hand (a
  fanned hand of cards), ring (3D), panorama, triple, grid, pills (thin
  pills in each theme's colours, the highlighted one opening into its card)
  or blips (a dot per theme, the card risen over its blip). Arrows, the
  wheel or a click browse; **/** filters; **R** jumps to a random theme
  (**Shift+R** applies a random one straight away).
- **Options** (Ctrl+, or the button top right): the carousel style, the
  monitor's look, CRT on / off, glitches normal / subtle / off, the open /
  close glitch, and whether applying a theme leaves it open or glitches out
  to the desktop.
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

Settings are kept in `~/.config/glitch-theme-selector/settings.json`.

## Install

Part of [Glitch-Launcher-Collection](../README.md): from a clone of it,

```sh
./install.sh theme           # add --keys to bind its key too
```

Open it with `omarchy-shell shell toggle glitch-theme-selector '{}'`.

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
