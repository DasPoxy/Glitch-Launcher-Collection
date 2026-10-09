# Glitch-Overview

An Alt+Tab workspace overview in the Glitch-Launcher-Collection style - a
sibling of [Glitch-Globe-Launcher](../glitch-globe-launcher),
[Glitch-Theme-Selector](../glitch-theme-selector) and
[Glitch-Background-Selector](../glitch-background-selector).

- **Alt+Tab**: opens on the workspace you were on before this one; Alt+Tab
  again (Alt still held) steps on, Alt+Shift+Tab steps back, and letting go
  of Alt goes there - glitching out onto it.
- **The monitor**: the selected workspace on a CRT set, every window live
  (Screencopy) at its place and size, titled; the picked window outlined.
- **The readout**: what that workspace is costing - each window's CPU and
  memory, counting the processes it started (`wsstats.py`, sampled every
  1.5 s while open), as bars and numbers, with the workspace's totals.
- **The carousel**: every workspace as a small picture of itself, in any of
  the collection's carousel styles (options).
- **Fully keyboard driven**: Tab / Shift+Tab or ← → for workspaces, ↑ ↓ (or
  W) to pick a window in one, 1-9 to jump, Enter or Space to go (to the
  window, if one's picked), Esc to stay where you are, Ctrl+T for the CRT,
  Ctrl+, for the options.
- **The feel**: glitching in over your desktop and out onto the workspace
  you chose, the screen acting up now and then, a light glitch as you move;
  CRT scanlines; a starfield and nebula in the running theme's colours.

Options (Ctrl+, or the button top right): the carousel style, CRT on / off,
glitches normal / subtle / off, and the open / close glitch. Kept in
`~/.config/glitch-overview/settings.json`.

## Install

Part of [Glitch-Launcher-Collection](../README.md): from a clone of it,

```sh
./install.sh overview        # add --keys to bind Alt+Tab / Alt+Shift+Tab too
```

The keys must *summon* it (not toggle), with a payload saying which way to
step - that's what lets Alt+Tab pressed again step on instead of closing it:

```lua
hl.unbind("ALT + TAB")
o.bind("ALT + TAB", "Glitch-Overview", "omarchy-shell shell summon glitch-overview '{\"alt\":true,\"step\":1}'")
hl.unbind("ALT + SHIFT + TAB")
o.bind("ALT + SHIFT + TAB", "Glitch-Overview (back)", "omarchy-shell shell summon glitch-overview '{\"alt\":true,\"step\":-1}'")
```

## License

MIT
