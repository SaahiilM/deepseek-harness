#!/usr/bin/env bash
# Generate AppIcon.icns from shell/Tools/make-icon.swift (cached by input hash).
# Usage: make-icon.sh <output.icns>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT="$1"
GENERATOR="$SCRIPT_DIR/../shell/Tools/make-icon.swift"
CACHE="/tmp/dsh-desktop-icon-$(shasum -a 256 "$GENERATOR" | cut -d' ' -f1).icns"

if [[ -f "$CACHE" ]]; then
  cp "$CACHE" "$OUTPUT"
  exit 0
fi

swift "$GENERATOR" "$OUTPUT"
cp "$OUTPUT" "$CACHE"
