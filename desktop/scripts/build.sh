#!/usr/bin/env bash
# Build "DeepSeek Harness.app" — the native macOS desktop shell.
#
# Steps:
#   1. verify toolchain (node, pnpm, swiftc)
#   2. install workspace deps (unless SKIP_INSTALL=1)
#   3. build the harness (tsc + tsdown + web dist via `pnpm run build`)
#      — skipped with --shell-only
#   4. compile the Swift shell as a universal binary (arm64 + x86_64)
#   5. assemble desktop/dist/DeepSeek Harness.app and ad-hoc codesign it
#
# Usage:
#   desktop/scripts/build.sh                 # full build
#   desktop/scripts/build.sh --shell-only    # only recompile the Swift shell
#   desktop/scripts/build.sh --open          # and launch when done
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DESKTOP_DIR="$REPO_ROOT/desktop"
APP_NAME="DeepSeek Harness"
DIST_DIR="$DESKTOP_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"

SHELL_ONLY=0; DO_OPEN=0
for arg in "$@"; do
  case "$arg" in
    --shell-only) SHELL_ONLY=1 ;;
    --open) DO_OPEN=1 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

cd "$REPO_ROOT"

fail() { echo "error: $*" >&2; exit 1; }

command -v node  >/dev/null || fail "node not found on PATH (need Node ^22.19 || >=24)"
command -v pnpm  >/dev/null || fail "pnpm not found on PATH"
command -v swiftc >/dev/null || fail "swiftc not found (install Xcode command line tools: xcode-select --install)"

echo "==> toolchain: $(node --version), pnpm $(pnpm --version), $(swiftc --version | head -1)"

if [[ "$SHELL_ONLY" -eq 0 ]]; then
  if [[ "${SKIP_INSTALL:-0}" != "1" ]]; then
    echo "==> pnpm install"
    pnpm install
  else
    echo "==> SKIP_INSTALL=1, skipping pnpm install"
  fi

  echo "==> building harness (tsc + tsdown + web frontend)"
  pnpm run build

  [[ -f "$REPO_ROOT/apps/web/dist/index.html" ]] || fail "apps/web/dist/index.html missing after build"
fi

echo "==> compiling Swift shell (universal: arm64 + x86_64)"
mkdir -p "$DIST_DIR"
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"

# One module per responsibility under Sources/ — the glob keeps new files
# from needing build-script edits.
SOURCES=("$DESKTOP_DIR"/shell/Sources/*.swift)
[[ ${#SOURCES[@]} -gt 0 ]] || fail "no Swift sources found in desktop/shell/Sources/"
FRAMEWORKS=(-framework AppKit -framework WebKit -framework Network -framework UserNotifications)

# swiftc accepts one -target per invocation, so each architecture is compiled
# separately and merged with lipo. Both slices come from the same universal SDK.
ARM_BIN="$DIST_DIR/.dsh-desktop-arm64"
X86_BIN="$DIST_DIR/.dsh-desktop-x86_64"
xcrun swiftc -O -parse-as-library \
  -sdk "$(xcrun --show-sdk-path)" -target 'arm64-apple-macos13.0' \
  "${SOURCES[@]}" "${FRAMEWORKS[@]}" -o "$ARM_BIN"
xcrun swiftc -O -parse-as-library \
  -sdk "$(xcrun --show-sdk-path)" -target 'x86_64-apple-macos13.0' \
  "${SOURCES[@]}" "${FRAMEWORKS[@]}" -o "$X86_BIN"
lipo -create "$ARM_BIN" "$X86_BIN" -output "$APP_BUNDLE/Contents/MacOS/dsh-desktop"
rm -f "$ARM_BIN" "$X86_BIN"

echo "==> assembling bundle"
cp "$DESKTOP_DIR/shell/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
printf 'APPL????' > "$APP_BUNDLE/Contents/PkgInfo"

"$SCRIPT_DIR/make-icon.sh" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

echo "==> codesign (ad-hoc)"
codesign --force --sign - "$APP_BUNDLE" >/dev/null

echo "==> verifying architectures"
lipo -info "$APP_BUNDLE/Contents/MacOS/dsh-desktop"

echo ""
echo "built: $APP_BUNDLE"
if [[ "$DO_OPEN" -eq 1 ]]; then
  open "$APP_BUNDLE"
fi
