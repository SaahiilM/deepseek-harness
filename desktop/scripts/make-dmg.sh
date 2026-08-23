#!/usr/bin/env bash
# Package the built app into a distributable DMG.
#
# Usage:
#   desktop/scripts/make-dmg.sh               # build if needed, then dist/"DeepSeek Harness.dmg"
#   desktop/scripts/make-dmg.sh --no-build    # package whatever is in dist/
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/dist"
APP_BUNDLE="$DIST_DIR/DeepSeek Harness.app"
DMG_PATH="$DIST_DIR/DeepSeek Harness.dmg"

if [[ "${1:-}" != "--no-build" ]]; then
  "$SCRIPT_DIR/build.sh"
elif [[ ! -d "$APP_BUNDLE" ]]; then
  echo "error: $APP_BUNDLE missing; run without --no-build" >&2
  exit 1
fi

echo "==> codesigning bundle before imaging"
codesign --force --sign - "$APP_BUNDLE" >/dev/null

rm -f "$DMG_PATH"
echo "==> creating $DMG_PATH"
hdiutil create \
  -volname "DeepSeek Harness" \
  -srcfolder "$APP_BUNDLE" \
  -ov -format UDZO \
  "$DMG_PATH"

echo ""
echo "dmg: $DMG_PATH"
echo "note: ad-hoc signed; Gatekeeper warns on other machines. For distribution,"
echo "sign with a Developer ID and notarize:"
echo "  codesign --force --options runtime --sign 'Developer ID Application: …' '$APP_BUNDLE'"
echo "  xcrun notarytool submit '$DMG_PATH' --keychain-profile … ; xcrun stapler staple '$DMG_PATH'"
