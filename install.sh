#!/bin/bash
# Glitch-Launcher-Collection's installer: put any of its plugins (or all of
# them) into Omarchy's shell, update them, or take them out again.
#
#   ./install.sh [all | globe | theme | background | overview ...] [--keys]
#   ./install.sh update            pull the latest, refresh what's installed
#   ./install.sh remove COMPONENT ... [--yes] [--purge]
#                                  take components out: the plugin, and its
#                                  keys in bindings.lua (commented out, backed
#                                  up) so Omarchy's own key works again;
#                                  --purge also deletes its settings and cache
#   ./install.sh list
#   ./install.sh doctor             what's missing on this machine, and what it affects
#
# --keys also binds each installed component's key in
# ~/.config/hypr/bindings.lua (backing it up first):
#   globe       SUPER + SPACE                  (the Omarchy menu moves to SUPER + CTRL + ALT + SPACE)
#   theme       SUPER + SHIFT + CTRL + SPACE   (in place of Omarchy's theme menu)
#   background  SUPER + CTRL + SPACE           (in place of Omarchy's background switcher)
#   overview    ALT + TAB / ALT + SHIFT + TAB  (in place of Omarchy's window cycling)
#
# Each plugin is copied into ~/.config/omarchy/plugins/<id> and enabled.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PLUGINS="$HOME/.config/omarchy/plugins"
BINDINGS="$HOME/.config/hypr/bindings.lua"

# component -> folder (= plugin id), key, label, extra lines for the binding
declare -A DIR=([globe]=glitch-globe-launcher [theme]=glitch-theme-selector [background]=glitch-background-selector [overview]=glitch-overview)
declare -A KEY=([globe]="SUPER + SPACE" [theme]="SUPER + SHIFT + CTRL + SPACE" [background]="SUPER + CTRL + SPACE" [overview]="ALT + TAB")
declare -A LABEL=([globe]="Glitch-Globe-Launcher" [theme]="Glitch-Theme-Selector" [background]="Glitch-Background-Selector" [overview]="Glitch-Overview")
ORDER=(globe theme background overview)

die() { echo "install.sh: $*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || die "needs $1"; }

component() {                    # accept "theme", "glitch-theme-selector", ...
  local c=${1,,}
  for k in "${ORDER[@]}"; do
    if [[ $c == "$k" || $c == "${DIR[$k]}" ]]; then echo "$k"; return; fi
  done
  die "no component '$1' (globe, theme, background, overview or all)"
}

install_one() {
  local k=$1 id=${DIR[$1]}
  [[ -f $REPO/$id/manifest.json ]] || die "missing $id/manifest.json"
  mkdir -p "$PLUGINS/$id"
  rsync -a --delete --exclude .git --exclude /screenshots --exclude /preview.jpg "$REPO/$id/" "$PLUGINS/$id/"
  # the shared easter eggs (eggs.js at the top is the one to edit)
  [[ -f $REPO/eggs.js ]] && cp "$REPO/eggs.js" "$PLUGINS/$id/eggs.js"
  echo "installed $id"
}

enable_all() {
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  local id
  for id in "$@"; do
    for _ in $(seq 1 40); do
      omarchy plugin list --json 2>/dev/null | jq -e --arg id "$id" 'any(.[]; .id == $id)' >/dev/null && break
      sleep 0.05
    done
    omarchy plugin enable "$id" >/dev/null && echo "enabled $id" || echo "could not enable $id (try: omarchy plugin enable $id)" >&2
  done
}

bind_keys() {
  [[ -f $BINDINGS ]] || die "no $BINDINGS"
  cp "$BINDINGS" "$BINDINGS.backup-$(date +%Y%m%d-%H%M%S)"
  local k
  for k in "$@"; do
    local id=${DIR[$k]} key=${KEY[$k]}
    if grep -q "shell toggle $id\|shell summon $id" "$BINDINGS"; then
      echo "key for $id already bound"
      continue
    fi
    {
      echo ""
      echo "-- ${LABEL[$k]} (Glitch-Launcher-Collection)"
      echo "hl.unbind(\"$key\")"
      if [[ $k == overview ]]; then
        # Alt+Tab summons (never toggles): again while it's up steps on
        echo "o.bind(\"$key\", \"${LABEL[$k]}\", \"omarchy-shell shell summon $id '{\\\"alt\\\":true,\\\"step\\\":1}'\")"
        echo "hl.unbind(\"ALT + SHIFT + TAB\")"
        echo "o.bind(\"ALT + SHIFT + TAB\", \"${LABEL[$k]} (back)\", \"omarchy-shell shell summon $id '{\\\"alt\\\":true,\\\"step\\\":-1}'\")"
      else
        echo "o.bind(\"$key\", \"${LABEL[$k]}\", \"omarchy-shell shell toggle $id '{}'\")"
      fi
      if [[ $k == globe ]] && ! grep -q '"SUPER + CTRL + ALT + SPACE"' "$BINDINGS"; then
        echo "o.bind(\"SUPER + CTRL + ALT + SPACE\", \"Omarchy menu\", \"omarchy-menu toggle\")"
      fi
    } >>"$BINDINGS"
    echo "bound $key -> ${LABEL[$k]}"
  done
  hyprctl reload >/dev/null 2>&1 || true
}

# what each component needs, and what goes missing without it
doctor() {
  local miss=0 ver
  have() { command -v "$1" >/dev/null 2>&1; }
  need_cmd() {     # need_cmd CMD "what for" [required]
    if have "$1"; then printf '  ok       %-22s %s\n' "$1" "$2"
    elif [[ ${3:-} == required ]]; then printf '  MISSING  %-22s %s\n' "$1" "$2"; miss=1
    else printf '  missing  %-22s %s (optional)\n' "$1" "$2"; fi
  }
  ver=$(pacman -Q omarchy 2>/dev/null | awk '{print $2}' | cut -d- -f1)
  echo "Omarchy ${ver:-?} (this collection was made on 4.0.x)"
  need_cmd omarchy-shell "the shell these plugins run in" required
  need_cmd hyprctl "Hyprland: keys, the overview" required
  need_cmd python3 "the helpers (themes, wallpapers, previews, the overview's load)" required
  if python3 -c "import PIL" 2>/dev/null; then printf '  ok       %-22s %s\n' "Pillow (python-pillow)" "wallpaper colours, fits and looks, 3D models"
  else printf '  MISSING  %-22s %s\n' "Pillow (python-pillow)" "background selector colours / fits / baked looks, 3D model previews"; miss=1; fi
  need_cmd fd "launcher: the / file search index"
  need_cmd fzf "launcher: the / file search"
  need_cmd ffprobe "previews: video and audio details (ffmpeg)"
  need_cmd pdftoppm "previews: PDF first pages (poppler)"
  need_cmd bsdtar "previews: what's in an archive (libarchive)"
  need_cmd xdg-open "opening files from the launcher"
  local fonts; fonts=$(fc-list : family 2>/dev/null || true)
  if [[ ${fonts,,} == *"noto sans cjk"* ]]; then printf '  ok       %-22s %s\n' "Noto Sans CJK" "the glyph and rain looks' katakana"
  else printf '  missing  %-22s %s (optional)\n' "Noto Sans CJK" "katakana in the glyph / rain looks (noto-fonts-cjk)"; fi
  if [[ -d /usr/lib/qt6/qml/QtMultimedia ]]; then printf '  ok       %-22s %s\n' "Qt Multimedia" "video in previews"
  else printf '  missing  %-22s %s (optional)\n' "Qt Multimedia" "video in previews (qt6-multimedia)"; fi
  (( miss )) && echo "Something required is missing: install it before the components that need it." || echo "Everything required is here."
  return 0
}

installed() {                    # components installed right now
  local k
  for k in "${ORDER[@]}"; do [[ -d $PLUGINS/${DIR[$k]} ]] && echo "$k"; done
}

need rsync; need jq; need omarchy

cmd=${1:-all}
case $cmd in
  doctor)
    doctor
    ;;
  list)
    for k in "${ORDER[@]}"; do
      printf '%-11s %-28s %s\n' "$k" "${DIR[$k]}" "$([[ -d $PLUGINS/${DIR[$k]} ]] && echo installed || echo -)"
    done
    ;;
  update)
    if git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
      git -C "$REPO" pull --ff-only
    fi
    mapfile -t comps < <(installed)
    (( ${#comps[@]} )) || die "nothing installed yet"
    for k in "${comps[@]}"; do install_one "$k"; done
    echo "restart the shell to load changed views: omarchy restart shell"
    ;;
  remove)
    shift
    yes=0; purge=0; comps=()
    for a in "$@"; do
      case $a in
        --yes|-y) yes=1 ;;
        --purge) purge=1 ;;
        all) comps+=("${ORDER[@]}") ;;
        *) comps+=("$(component "$a")") ;;
      esac
    done
    (( ${#comps[@]} )) || die "remove which? (globe, theme, background, overview or all)"
    echo "Removing:"
    for k in "${comps[@]}"; do
      echo "  - ${LABEL[$k]}: the plugin (${PLUGINS}/${DIR[$k]})"
      grep -q "${DIR[$k]}" "$BINDINGS" 2>/dev/null && echo "    and its keys in bindings.lua (commented out; Omarchy's own key back)"
      (( purge )) && echo "    and its settings and cache (~/.config/${DIR[$k]}, ~/.cache/${DIR[$k]})"
    done
    [[ -f $BINDINGS ]] && echo "  (bindings.lua is backed up first)"
    (( purge )) || echo "  Settings and caches are kept (--purge deletes them)."
    if (( ! yes )); then
      if [[ -t 0 ]]; then read -r -p "Go ahead? [y/N] " ok; [[ $ok == [yY]* ]] || { echo "nothing changed"; exit 1; }
      else echo "run again with --yes to do it"; exit 2; fi
    fi
    ids=()
    for k in "${comps[@]}"; do ids+=("${DIR[$k]}"); done
    if [[ -f $BINDINGS ]] && grep -q -E "$(IFS='|'; echo "${ids[*]}")" "$BINDINGS"; then
      cp -p "$BINDINGS" "$BINDINGS.before-glitch-remove-$(date +%Y%m%d-%H%M%S)"
      # comment out the components' binds, and the hl.unbind of each key they
      # took over (so Omarchy's own bind for it works again)
      python3 - "$BINDINGS" "${ids[@]}" <<'PY'
import re, sys
path, ids = sys.argv[1], sys.argv[2:]
lines = open(path).read().split("\n")
key = lambda l: (re.search(r'(?:o\.bind|hl\.unbind|o\.rebind)\(\s*"([^"]+)"', l) or [None, None])[1]
taken = set()
for i, l in enumerate(lines):
    if not l.lstrip().startswith("--") and any(x in l for x in ids):
        if key(l):
            taken.add(key(l))
        lines[i] = "-- (Glitch removed) " + l
# a key is only given back when nothing still binds it
still = {key(l) for l in lines if not l.lstrip().startswith("--") and l.lstrip().startswith(("o.bind", "o.rebind"))}
for i, l in enumerate(lines):
    if not l.lstrip().startswith("--") and l.lstrip().startswith("hl.unbind") and key(l) in taken - still:
        lines[i] = "-- (Glitch removed) " + l
open(path, "w").write("\n".join(lines))
PY
      hyprctl reload >/dev/null 2>&1 || true
      echo "keys: commented out in $BINDINGS"
    fi
    for k in "${comps[@]}"; do
      omarchy plugin disable "${DIR[$k]}" >/dev/null 2>&1 || true
      rm -rf -- "${PLUGINS:?}/${DIR[$k]}"
      (( purge )) && rm -rf -- "${HOME:?}/.config/${DIR[$k]}" "${HOME:?}/.cache/${DIR[$k]}"
      echo "removed ${DIR[$k]}"
    done
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
    ;;
  -h | --help | help)
    sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    keys=0
    comps=()
    for a in "$@"; do
      case $a in
        --keys) keys=1 ;;
        all) comps+=("${ORDER[@]}") ;;
        *) comps+=("$(component "$a")") ;;
      esac
    done
    (( ${#comps[@]} )) || comps=("${ORDER[@]}")
    mapfile -t comps < <(printf '%s\n' "${comps[@]}" | awk '!seen[$0]++')
    doctor | grep -E "MISSING|^Something" || true
    ids=()
    for k in "${comps[@]}"; do install_one "$k"; ids+=("${DIR[$k]}"); done
    enable_all "${ids[@]}"
    (( keys )) && bind_keys "${comps[@]}"
    echo "done. restart the shell if a view doesn't show its latest changes: omarchy restart shell"
    ;;
esac
