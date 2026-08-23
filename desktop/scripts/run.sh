#!/usr/bin/env bash
# Launch the built desktop app (or run it against a dev server with --dev).
#
# Usage:
#   desktop/scripts/run.sh              # build if missing, then `open` the app
#   desktop/scripts/run.sh --force      # rebuild first, then open
#   desktop/scripts/run.sh --console    # run the shell binary in the foreground
#                                       # (server + webview logs on this terminal)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_BUNDLE="$(cd "$SCRIPT_DIR/.." && pwd)/dist/DeepSeek Harness.app"

MODE="open"
for arg in "$@"; do
  case "$arg" in
    --force)  MODE="force" ;;
    --console) MODE="console" ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

if [[ ! -d "$APP_BUNDLE" || "$MODE" == "force" ]]; then
  "$SCRIPT_DIR/build.sh"
fi

if [[ "$MODE" == "console" ]]; then
  exec "$APP_BUNDLE/Contents/MacOS/dsh-desktop"
fi

open "$APP_BUNDLE"
