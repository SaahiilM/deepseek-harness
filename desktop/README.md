# DeepSeek Harness — Desktop App

A native macOS shell that turns the DeepSeek Harness web UI into a desktop
application, comparable to OpenAI's Codex app: one window, a dock icon, menus,
and an app-managed local agent server. Works on Intel and Apple Silicon.

```
desktop/
├── PROJECT_MEMORY.md          durable project memory — read this first
├── agent-memory/              per-session agent notes (append-only)
├── shell/
│   ├── Sources/               Swift sources (AppKit + WKWebView)
│   ├── Tools/make-icon.swift  icon generator
│   └── Info.plist├── scripts/
│   ├── build.sh               harness build + universal .app assembly
│   ├── run.sh                 launch the built app
│   ├── sync-origin.sh         keep this branch current with origin/master
│   ├── log-session.sh         append to agent memory
│   └── make-icon.sh           cached icns generation
└── dist/                      build output (ignored)
```

## Quick start

```sh
pnpm install                    # once, from the repo root
desktop/scripts/build.sh        # builds the harness and dist/"DeepSeek Harness.app"
open "desktop/dist/DeepSeek Harness.app"
```

Requirements: Node ^22.19 || >=24 · pnpm 11 · Xcode command line tools (`swiftc`).

## How it works

1. `build.sh` runs the normal `pnpm run build` (tsc + tsdown + web frontend),
   then compiles the Swift shell twice (arm64, x86_64) and merges with `lipo`
   into `dist/DeepSeek Harness.app` — a universal binary.
2. On launch, the shell resolves the checkout backing it (walking up from the
   executable; override with `defaults write ai.deepseek.harness.desktop
   DSHDesktopRepoPath <path>` or env `DSH_DESKTOP_REPO`), picks a free port, and
   spawns `node --import tsx/esm apps/cli/src/bin.ts web --no-open --port N`.
3. It waits for HTTP readiness, loads the UI in a `WKWebView`, and confines
   navigation to loopback — external links open in your default browser.
4. Quitting the app SIGTERMs the server. Server output lands in
   `~/Library/Application Support/DeepSeek Harness/server.log`.

## Desktop affordances (Codex/bb/t3code patterns)

- **Single instance** — launching a second copy activates the running app.
- **Session presence** — a `SessionMonitor` polls `POST /api/session.list`
  every 3s: the dock badge shows how many agents are running, and finishing an
  agent while the app is in the background posts a notification (plus a dock
  bounce when notifications are unavailable).
- **Multi-window** — File ▸ New Window (⌘N) opens another view onto the same
  local server; window frames persist across launches.
- **Native menus** — Edit roles make undo/copy/paste work inside the webview;
  View has Reload and Zoom In/Out/Actual Size; Server has Restart/Open in
  Browser/Copy URL/Reveal Log.

## Distribution

```sh
desktop/scripts/make-dmg.sh     # dist/"DeepSeek Harness.dmg"
```

The DMG is ad-hoc signed: other machines see a Gatekeeper warning until you
sign with a Developer ID and notarize (commands printed by the script).

## Staying current with upstream

The branch tracks `origin/master`; everything it owns lives in `desktop/`, so
rebases are almost always clean:

```sh
desktop/scripts/sync-origin.sh          # fetch + rebase onto origin/master
desktop/scripts/sync-origin.sh --check  # report drift only
```

## Agent memory

Agents working on this branch: read `PROJECT_MEMORY.md`, then the newest files
in `agent-memory/sessions/`, before changing anything. Log meaningful units of
work with:

```sh
desktop/scripts/log-session.sh "<what was done / learned / decided>"
```
