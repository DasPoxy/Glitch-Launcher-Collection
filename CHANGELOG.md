# Changelog

The collection is released as a whole (each component's manifest carries
the same version). Each release is a git tag; to go to one:

```sh
git checkout v0.1.0-beta.1 && ./install.sh update
```

## Unreleased

- **Glitch-Globe-Launcher**: spinning the globe hard could crash the shell.
  Node icons are now decoded once at a fixed size instead of on every
  frame, as the tiles shrink and grow with depth.
- **Glitch-Globe-Launcher**: a waiting Omarchy update shows top left (the
  same check as the bar's update icon, run on opening); Ctrl+U or a click
  on it opens Omarchy's updater.

## 0.1.0-beta.1 - 2026-10-09

The first tagged release, for testing beyond its author's machine.

- **Glitch-Globe-Launcher**: apps projected from a spinning globe (nine
  styles, random), `>` the Omarchy menu and commands, `/` files with
  previews (pictures, video, PDFs, 3D models; secrets kept off screen),
  space and network traffic, a nebula, glitches and a CRT, glitching in and
  out.
- **Glitch-Theme-Selector**: every Omarchy theme on a CRT with its palette
  and backgrounds, nine carousel styles, the UI in the highlighted theme's
  colours; with Glitch-Background-Selector, the monitor's look follows to
  the desktop.
- **Glitch-Background-Selector**: the theme's wallpapers then your own
  folder, fit modes, the monitor's look on the desktop (baked or live).
- **Glitch-Overview**: Alt+Tab across workspaces, every window live, what
  each costs; hold Alt or toggle.
- **Shared**: corner-terminal easter eggs; plain-text labels everywhere
  (nothing from a window title, file or note can load from the internet).
- **install.sh**: install any or all, `--keys`, `update`, `remove` (asks
  first, gives Omarchy's own keys back, `--purge`), `doctor`.
- **Tests and CI** on Arch (Omarchy's Qt): the helpers, every shader
  compiles, every QML file parses.
