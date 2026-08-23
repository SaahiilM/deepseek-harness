#!/usr/bin/env bash
# Append a timestamped entry to today's agent-memory session file.
#
# Usage:
#   desktop/scripts/log-session.sh "<summary>"          # one-line Did: entry
#   echo "multi
#   line body" | desktop/scripts/log-session.sh         # read entry from stdin
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SESSIONS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/agent-memory/sessions"
mkdir -p "$SESSIONS_DIR"

TODAY="$(date +%F)"
FILE="$SESSIONS_DIR/$TODAY.md"
NOW="$(date +%H:%M)"

entry=""
if [[ $# -gt 0 ]]; then
  entry="$*"
else
  entry="$(cat)"
fi

[[ -n "$entry" ]] || { echo "error: empty entry" >&2; exit 2; }

if [[ ! -f "$FILE" ]]; then
  printf '# Agent session log — %s\n' "$TODAY" > "$FILE"
fi

printf '\n## %s — note\n%s\n' "$NOW" "$entry" >> "$FILE"
echo "logged to agent-memory/sessions/$TODAY.md"
