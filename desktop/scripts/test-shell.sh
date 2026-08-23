#!/usr/bin/env bash
# Unit tests for the shell's pure logic — the parts whose behavior can be
# asserted without a GUI: wire decoding, lifecycle page rendering, log tail
# bookkeeping, node version parsing, repo-marker detection.
#
# The app's own entry point (AppMain.swift) is excluded — a second @main would
# collide — and the tests provide theirs as Tests/main.swift, whose top-level
# statements run. AppKit links fine in a CLI binary; nothing AppKit-backed is
# instantiated.
#
# Usage: desktop/scripts/test-shell.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCES_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/shell/Sources"
TESTS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/shell/Tests"
OUT="$(mktemp -t dsh-shell-tests)"
trap 'rm -f "$OUT"' EXIT

echo "==> compiling shell tests"
xcrun swiftc -O \
  -sdk "$(xcrun --show-sdk-path)" \
  $(ls "$SOURCES_DIR"/*.swift | grep -v '/AppMain\.swift$') \
  "$TESTS_DIR/main.swift" \
  -framework AppKit -framework WebKit -framework Network -framework UserNotifications \
  -o "$OUT"

echo "==> running"
"$OUT"
