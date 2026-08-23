#!/usr/bin/env bash
# Optional: install a LaunchAgent that keeps `desktop-app` synced with
# origin/master once a day (and on login), so the branch never drifts far.
#
# Behavior of the agent:
#   - runs desktop/scripts/sync-origin.sh (rebase) only when the working tree
#     is clean and no interactive rebase is in progress
#   - appends outcomes to desktop/agent-memory/sync-log.md
#
# Usage:
#   desktop/scripts/install-sync-timer.sh           # install + start
#   desktop/scripts/install-sync-timer.sh --remove  # uninstall
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LABEL="ai.deepseek.harness.desktop-sync"
PLIST_PATH="$HOME/Library/LaunchAgents/$LABEL.plist"
SYNC_LOG="$REPO_ROOT/desktop/agent-memory/sync-log.md"

if [[ "${1:-}" == "--remove" ]]; then
  if launchctl bootout "gui/$(id -u)/$LABEL" >/dev/null 2>&1; then echo "stopped running agent"; fi
  rm -f "$PLIST_PATH"
  echo "removed $PLIST_PATH"
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/zsh</string>
        <string>-c</string>
        <string>cd '$REPO_ROOT' &amp;&amp;
[[ -z "\$(git status --porcelain)" ]] &amp;&amp; [[ ! -d .git/rebase-merge ]] &amp;&amp; [[ ! -d .git/rebase-apply ]] || exit 0;
desktop/scripts/sync-origin.sh &gt;&gt; '$SYNC_LOG' 2&gt;&amp;1 &amp;&amp;
printf '\n[%s] auto-sync ok\n' "\$(date '+%F %T')" &gt;&gt; '$SYNC_LOG' ||
printf '\n[%s] auto-sync FAILED (see above)\n' "\$(date '+%F %T')" &gt;&gt; '$SYNC_LOG'</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key><integer>9</integer>
        <key>Minute</key><integer>0</integer>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>StandardErrorPath</key>
    <string>/tmp/dsh-desktop-sync.err</string>
</dict>
</plist>
EOF

launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" 2>/dev/null \
  || launchctl load "$PLIST_PATH"

echo "installed $PLIST_PATH"
echo "schedule: daily at 09:00 and at login; outcomes append to:"
echo "  $SYNC_LOG"
echo "remove with: desktop/scripts/install-sync-timer.sh --remove"
