# Agent Memory

Durable, per-session notes written **by agents, for agents** working on the
`desktop-app` branch. Project-level decisions live in
[`../PROJECT_MEMORY.md`](../PROJECT_MEMORY.md); this directory records *what was
actually done, observed, and learned per session*, so a later session (or a fresh
agent with no conversation context) can reconstruct the work.

## Protocol

1. **Before working**: read `../PROJECT_MEMORY.md`, then the newest entries here.
2. **While working**: prefer running `desktop/scripts/log-session.sh "<summary>"`
   after each meaningful unit — it appends a timestamped entry for today.
3. **Entry format** (one file per day, `sessions/YYYY-MM-DD.md`):

   ```markdown
   ## HH:MM — <short title>
   - Did: …
   - Learned: …            (non-obvious facts: commands that failed, timings, quirks)
   - Decided: …            (only if it changes PROJECT_MEMORY.md too)
   - Next: …               (concrete hand-off to the next session)
   ```

4. **Never delete or rewrite past entries**; append corrections as new entries.
5. Keep entries factual and short. Reasoning transcripts do not belong here.

## Index

- `sessions/2026-08-23.md` — branch bootstrap, memory scaffold, shell v1.
