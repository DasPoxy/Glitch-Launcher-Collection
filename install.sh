#!/bin/bash
# Glitch-Launcher-Collection's installer: put any of its plugins (or all of
# them) into Omarchy's shell, update them, or take them out again.
#
#   ./install.sh [all | globe | theme | background | overview ...] [--keys]
#   ./install.sh update            pull the latest, refresh what's installed
#   ./install.sh remove COMPONENT ...
#   ./install.sh list
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
  rsync -a --delete --exclude .git "$REPO/$id/" "$PLUGINS/$id/"
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

installed() {                    # components installed right now
  local k
  for k in "${ORDER[@]}"; do [[ -d $PLUGINS/${DIR[$k]} ]] && echo "$k"; done
}

need rsync; need jq; need omarchy

cmd=${1:-all}
case $cmd in
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
    (( $# )) || die "remove which? (globe, theme, background, overview or all)"
    [[ $1 == all ]] && set -- "${ORDER[@]}"
    for c in "$@"; do
      k=$(component "$c")
      omarchy plugin disable "${DIR[$k]}" >/dev/null 2>&1 || true
      rm -rf -- "${PLUGINS:?}/${DIR[$k]}"
      echo "removed ${DIR[$k]} (its key, if bound, is still in $BINDINGS)"
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
    ids=()
    for k in "${comps[@]}"; do install_one "$k"; ids+=("${DIR[$k]}"); done
    enable_all "${ids[@]}"
    (( keys )) && bind_keys "${comps[@]}"
    echo "done. restart the shell if a view doesn't show its latest changes: omarchy restart shell"
    ;;
esac
