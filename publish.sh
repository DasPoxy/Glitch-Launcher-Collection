#!/bin/bash
# Publish each component as a repository of its own (github.com/DasPoxy/<id>),
# the one `omarchy plugin add` and the plugin marketplace install from: its
# folder here becomes that repository's root, history and all (git subtree
# split), so this collection stays the one place they're made.
#
#   ./publish.sh                    all four
#   ./publish.sh theme overview     or some (globe, theme, background, overview)
#   ./publish.sh --dry-run ...      split them and say what would be pushed
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
OWNER=${GLITCH_OWNER:-DasPoxy}
declare -A DIR=([globe]=glitch-globe-launcher [theme]=glitch-theme-selector [background]=glitch-background-selector [overview]=glitch-overview)
ORDER=(globe theme background overview)

die() { echo "publish.sh: $*" >&2; exit 1; }

dry=0; comps=()
for a in "$@"; do
  case $a in
    --dry-run) dry=1 ;;
    all) comps+=("${ORDER[@]}") ;;
    *)
      c=${a,,}; found=""
      for k in "${ORDER[@]}"; do [[ $c == "$k" || $c == "${DIR[$k]}" ]] && found=$k; done
      [[ -n $found ]] || die "no component '$a' (globe, theme, background, overview or all)"
      comps+=("$found")
      ;;
  esac
done
(( ${#comps[@]} )) || comps=("${ORDER[@]}")

cd "$REPO"
[[ -z $(git status --porcelain) ]] || die "commit your changes first: only what's committed is published"
for k in "${comps[@]}"; do
  id=${DIR[$k]}
  # each one carries its own copy of the shared easter eggs
  cmp -s eggs.js "$id/eggs.js" || die "$id/eggs.js differs from eggs.js: copy it in and commit"
  sha=$(git subtree split -q -P "$id" HEAD)
  url="https://github.com/$OWNER/$id.git"
  if (( dry )); then
    echo "$id: would push ${sha:0:12} to $url (main)"
  else
    git push "$url" "$sha:refs/heads/main"
    echo "$id: published ${sha:0:12}"
  fi
done
