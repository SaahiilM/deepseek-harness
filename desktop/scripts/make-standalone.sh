#!/usr/bin/env bash
# make-standalone.sh — package a self-contained DeepSeek Harness.app.
#
# Copies the built shell bundle and embeds a repository snapshot plus a
# matching node binary into Contents/Resources/runtime, so the result runs on
# machines without this checkout or any installed Node. The snapshot keeps the
# source-launch contract (node --import tsx/esm apps/cli/src/bin.ts web), so no
# extra build products are required beyond what `pnpm install` provides.
#
# Usage: desktop/scripts/make-standalone.sh [--skip-shell-build]
# Output: desktop/dist/DeepSeek Harness Standalone.app

set -euo pipefail

DESKTOP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$DESKTOP_DIR/dist"
REPO_ROOT="$(cd "$DESKTOP_DIR/.." && pwd)"
STAGE_APP="$DIST_DIR/DeepSeek Harness Standalone.app"
RUNTIME_DIRNAME="runtime"
NODE_DIR_IN_RUNTIME=".node-bin"

if [[ "${1:-}" != "--skip-shell-build" ]]; then
  echo "==> building base bundle"
  bash "$DESKTOP_DIR/scripts/build.sh" --shell-only
fi

BASE_APP="$DIST_DIR/DeepSeek Harness.app"
[[ -d "$BASE_APP" ]] || { echo "base bundle missing: $BASE_APP" >&2; exit 1; }

echo "==> locating an engines-compatible node for embedding"
NODE_SRC="$(bash "$DESKTOP_DIR/scripts/pick-node.sh")"

echo "==> staging bundle copy"
rm -rf "$STAGE_APP"
cp -R "$BASE_APP" "$STAGE_APP"

echo "==> embedding repository snapshot (this copies ~1.4 GB; be patient)"
mkdir -p "$STAGE_APP/Contents/Resources/$RUNTIME_DIRNAME"
rsync -a \
  --exclude '/.git' \
  --exclude '/desktop' \
  --exclude '/research' \
  --exclude '/coverage' \
  --exclude '/website/node_modules' \
  --exclude '*.tsbuildinfo' \
  --exclude '.DS_Store' \
  "$REPO_ROOT/" "$STAGE_APP/Contents/Resources/$RUNTIME_DIRNAME/"

echo "==> embedding node binary ($("$NODE_SRC" --version))"
mkdir -p "$STAGE_APP/Contents/Resources/$RUNTIME_DIRNAME/$NODE_DIR_IN_RUNTIME"
cp "$NODE_SRC" "$STAGE_APP/Contents/Resources/$RUNTIME_DIRNAME/$NODE_DIR_IN_RUNTIME/node"
chmod +x "$STAGE_APP/Contents/Resources/$RUNTIME_DIRNAME/$NODE_DIR_IN_RUNTIME/node"

echo "==> labeling and re-signing (ad-hoc)"
plutil -replace CFBundleName -string "DeepSeek Harness Standalone" "$STAGE_APP/Contents/Info.plist"
codesign --force --deep -s - "$STAGE_APP"

SIZE="$(du -sh "$STAGE_APP" | cut -f1)"
echo "built: $STAGE_APP ($SIZE embedded runtime included)"
