# Project Memory — DSH Desktop

> **What this file is.** Persistent, human- and agent-readable project memory for the
> `desktop-app` branch: the goal, the decisions already made (with reasons), and the
> current state. Every agent session working on this branch MUST read this file first
> and update it after making decisions. Session-level detail lives in
> [`agent-memory/`](agent-memory/README.md); durable decisions live here.

## Goal

Turn DeepSeek Harness into a desktop application comparable to OpenAI's Codex app:
a native-feeling macOS window hosting the full agent experience (chat, sessions,
approvals, diffs) that a user can build and launch on an Intel or Apple Silicon Mac
by running one script.

## Product shape (decided)

The DSH Web GUI at `http://127.0.0.1:3080` already provides the complete agent UX.
The Codex-like app is therefore a **native macOS shell** around that server:

1. A Swift/AppKit app (`desktop/shell/`) shows one window with a `WKWebView`.
2. On launch it picks a free port, spawns the harness web profile from this checkout
   (`node --import tsx/esm apps/cli/src/bin.ts web --no-open --port <port>`), waits
   for HTTP readiness, then loads the UI.
3. It owns the server lifecycle: logs to `~/Library/Application Support/DSH Desktop/`,
   clean shutdown on quit, error page with log tail if the server never comes up.
4. Menu items: Reload (⌘R), Open in Browser, Reveal Server Log, Quit.

## Decisions log

| # | Decision | Why | Date |
|---|----------|-----|------|
| 1 | Native Swift + WKWebView shell, **not** Electron/Tauri | `swiftc` is present on the target machine; zero new runtime dependencies; produces a small universal binary (`-arch arm64 -arch x86_64`) covering Intel and Apple Silicon | 2026-08-23 |
| 2 | All branch work lives additively under `desktop/` | Upstream `origin/master` moves fast; a single self-owned subtree means syncs almost never conflict and repo gates never see our files | 2026-08-23 |
| 3 | Shell runs the harness **from this checkout** via node + tsx | That is the sanctioned source-launch path (`pnpm dsh` does exactly this); no packaging of node_modules in v1 — see Open questions | 2026-08-23 |
| 4 | Server spawned with `--no-open` and an explicit free port picked by the shell | The shell must own which URL it loads; letting dsh open a browser would defeat the app | 2026-08-23 |
| 5 | Memory lives in `desktop/PROJECT_MEMORY.md` (this file) + `desktop/agent-memory/` (session notes), not in `.agents/notes/` | `.agents/` conventions are upstream-owned with format verification gates; keeping ours separate avoids gate failures after every sync | 2026-08-23 |
| 6 | Sync policy: rebase `desktop-app` onto `origin/master` via `desktop/scripts/sync-origin.sh` | Linear history keeps future upstream PRs trivial; `--merge` escape hatch provided | 2026-08-23 |
| 7 | Node discovery scans nvm version dirs and validates engines (^22.19 \|\| >=24) by executing `--version` | A stale `/usr/local/bin/node` (v16) silently broke the source launch; presence on disk proves nothing, only a successful run does | 2026-08-23 |
| 8 | Bootstrap uses explicit `static func main()` (not bare `@main` delegation) | `@main` on NSApplicationDelegate compiles but never installs the delegate without nib/principal-class wiring — app ran with no window and no error | 2026-08-23 |

## Current state

- [x] Branch `desktop-app` created off `master` (== origin/master).
- [x] Project memory + agent memory scaffolded (`desktop/`, this file).
- [x] Helper scripts: `sync-origin.sh`, `build.sh`, `run.sh`, `log-session.sh`, `make-icon.sh`.
- [x] Swift shell implemented (`desktop/shell/Sources/*.swift`) — universal binary.
- [x] `desktop/scripts/build.sh` produces `desktop/dist/DeepSeek Harness.app`.
- [x] `desktop/scripts/build.sh --shell-only` produced a universal .app; launched,
      served UI (HTTP 200), and quit with clean server shutdown on this machine.
- [x] `sync-origin.sh` verified (`--check` and no-op sync paths).
- [ ] Full `build.sh` path (pnpm install + pnpm run build + shell) validated end to
      end — deferred: rebuilding web dist hot-reloads the live GUI session on port
      3080; run it when that disruption is acceptable.

## How to build & run

```sh
cd deepseek-harness            # on branch desktop-app
pnpm install                   # once
desktop/scripts/build.sh       # builds harness lib+web, then dist/DeepSeek Harness.app
open "desktop/dist/DeepSeek Harness.app"
```

Requirements: Node ^22.19 || >=24, pnpm 11, Xcode command line tools (`swiftc`).
Intel Macs: the binary is universal; Node must be installed (Rosetta or native).

## Keeping up to date with origin/master

Run before starting work and before building:

```sh
desktop/scripts/sync-origin.sh          # fetch + rebase onto origin/master
desktop/scripts/sync-origin.sh --check  # only report drift, change nothing
```

## Open questions / next steps

1. **Self-contained bundle**: ship Node + the built workspace inside the .app so it
   runs on machines without this checkout (v2). Needs a size/perf budget decision.
2. Dock badge / menu-bar extra showing agent activity (Codex-like presence).
3. Native notifications when a task finishes or needs approval.
4. DMG packaging script for distribution.
