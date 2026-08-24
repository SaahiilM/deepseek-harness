# Agent session log — 2026-08-24 (afternoon)

## 16:18 — client artifact model mapped + fresh rebuild shipped
Symptom: built `apps/web/dist` lacked drawer/safe-area markers; feared stale UI for phone.
Truth: dist is only the static SHELL. Mobile UX ships as runtime-fetched module bundles
served by the host at `/plugins/@deepseek-ai/<pkg>/client.js?rev=<hash>`, sourced from each
package's `lib/client.js` (tsdown via root `pnpm run build`; digest in
`.dsh-build/client-build-environment.json`, patterns in scripts/client-build-environment.ts).
The old libs predated the drawer/picker commits → rebuilt (16:03) and relaunched.
Verified over HTTP on the live server: ui-layout bundle has drawer-open/drawerSessionGuard/
shell.overlay; ui-conversation bundle has safe-area inset.
Gotcha: the app's owned server died during the rebuild window (cause unproven — lib swap
under a live tsx process or manual quit); don't trust marker checks against a server whose
checkout was just rebuilt underneath it. Relaunch after rebuilding.
