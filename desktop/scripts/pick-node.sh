#!/usr/bin/env bash
# pick-node.sh — print the path of the newest engines-compatible node binary
# on this machine (^22.19 || >=24). Mirrors NodeLocator's scan order so the
# packaged app embeds the same runtime the checkout-backed app would use.

set -euo pipefail

ENV_KEY="DSH_DESKTOP_NODE"
MIN_MAJOR=22
MIN_MINOR=19

version_ok() {
  local v="${1#v}"
  local major="${v%%.*}"
  local rest="${v#*.}"
  local minor="${rest%%.*}"
  if (( major > 24 )); then return 0; fi
  if (( major == 24 )); then return 0; fi
  if (( major == MIN_MAJOR && minor >= MIN_MINOR )); then return 0; fi
  return 1
}

candidates=()
[[ -n "${!ENV_KEY:-}" ]] && candidates+=("${!ENV_KEY}")
# Newest nvm version first (version sort, reversed).
while IFS= read -r dir; do
  candidates+=("${dir}bin/node")
done < <(ls -d "$HOME"/.nvm/versions/node/*/ 2>/dev/null | sed 's:.*/node/::; s:/$::' | sort -rV | sed "s|^|$HOME/.nvm/versions/node/|; s|$|/|")
candidates+=(
  /opt/homebrew/bin/node
  /opt/homebrew/opt/node/bin/node
  /usr/local/opt/node/bin/node
  /usr/local/bin/node
  "$HOME/.volta/bin/node"
)

for candidate in "${candidates[@]}"; do
  [[ -x "$candidate" ]] || continue
  version="$( "$candidate" --version 2>/dev/null )" || continue
  if version_ok "$version"; then
    echo "$candidate"
    exit 0
  fi
done

echo "no node >=22.19 found; install Node or set DSH_DESKTOP_NODE" >&2
exit 1
