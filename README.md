# Globe-Launcher

A full-screen app launcher for [Omarchy](https://omarchy.org): your installed
apps, projected out from a spinning dot-globe over a starfield, with the feel
of being jacked into a terminal.

- **The globe**: glowing rings of dots (or a wireframe), its far side faintly
  showing through, a rim glow and a halo. Every app sits on it, evenly
  spread, and is projected out on a beam.
- **Spin it**: drag (it keeps its momentum), scroll to zoom, or leave it to
  turn by itself. Whatever faces you is selected: it bulges out and unfolds
  its name; a card at the bottom shows its logo and description.
- **Keyboard**: arrow keys hop to the nearest app that way, typing filters,
  Enter launches, Esc clears the search or closes.
- **Atmosphere**: a full-resolution starfield, and now and then a glitch -
  the screen tears and shakes, colours split, and a terminal in the corner
  types a line.
- **Options** (Ctrl+, or the button top right): colours from your Omarchy
  theme, a prebuilt theme (Matrix, Cyber, Ice, Amber, Mono) or your own,
  dots or wireframe, auto-spin, and glitches normal / subtle / off. Saved in
  `~/.config/globe-launcher/settings.json`.

Clicking the selected app (or Enter) launches it and closes the launcher;
clicking another app turns the globe to it.

## Install

```sh
omarchy plugin add https://github.com/DasPoxy/globe-launcher.git --enable
```

Open it with:

```sh
omarchy-shell shell toggle globe-launcher '{}'
```

and give it a key in `~/.config/hypr/bindings.lua`, for example:

```lua
o.bind("SUPER + ALT + SPACE", "Globe-Launcher", "omarchy-shell shell toggle globe-launcher '{}'")
```

## How it's drawn

Three small GPU shaders (`shaders/`, compiled to `.qsb` with Qt's `qsb`):
the starfield, the globe (each pixel finds its point on the sphere, turns it
back by the globe's rotation and measures the distance to the nearest dot on
the rings of latitude), and the glitch pass over everything. The apps come
from the same desktop entries every launcher reads; their places on the globe
are a Fibonacci sphere, projected with the same rotation the shader uses.

After editing a shader, recompile it:

```sh
/usr/lib/qt6/bin/qsb --qt6 -o shaders/globe.frag.qsb shaders/globe.frag
```

## License

MIT
