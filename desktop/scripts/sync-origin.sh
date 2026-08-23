#!/usr/bin/env bash
# Sync the `desktop-app` branch with the upstream default branch.
#
# The branch tracks upstream `master` (origin/master) so harness improvements
# keep flowing into the desktop work. Everything this branch owns lives under
# `desktop/`, so a rebase almost never conflicts.
#
# Usage:
#   desktop/scripts/sync-origin.sh            # fetch + rebase onto origin/master
#   desktop/scripts/sync-origin.sh --check    # report drift only, change nothing
#   desktop/scripts/sync-origin.sh --merge    # merge instead of rebase
#   desktop/scripts/sync-origin.sh --continue # continue an interrupted rebase after resolving conflicts
set -euo pipefail

BRANCH="desktop-app"
UPSTREAM_BRANCH="master"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$REPO_ROOT"

MODE="sync"
for arg in "$@"; do
  case "$arg" in
    --check)   MODE="check" ;;
    --merge)   MODE="merge" ;;
    --continue) MODE="continue" ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "unknown option: $arg (see header of this file)" >&2; exit 2 ;;
  esac
done

if [[ "$(git branch --show-current)" != "$BRANCH" ]]; then
  echo "error: this script must run on branch '$BRANCH' (currently on '$(git branch --show-current)')." >&2
  echo "       switch first:  git switch $BRANCH" >&2
  exit 1
fi

if [[ "$MODE" == "continue" ]]; then
  echo "==> continuing rebase"
  git rebase --continue
  echo "==> rebase finished on $BRANCH"
  exit $?
fi

echo "==> fetching origin"
git fetch origin --prune

BEHIND="$(git rev-list --count "$BRANCH..origin/$UPSTREAM_BRANCH")"
AHEAD="$(git rev-list --count "origin/$UPSTREAM_BRANCH..$BRANCH")"

echo "==> drift: $BEHIND commit(s) behind origin/$UPSTREAM_BRANCH, $AHEAD ahead (branch-only commits)"

if [[ "$MODE" == "check" ]]; then
  if [[ "$BEHIND" -gt 0 ]]; then
    echo "OUT OF DATE: run desktop/scripts/sync-origin.sh"
    git log --oneline "$BRANCH..origin/$UPSTREAM_BRANCH" | head -20
    exit 1
  fi
  echo "UP TO DATE with origin/$UPSTREAM_BRANCH"
  exit 0
fi

if [[ "$BEHIND" -eq 0 ]]; then
  echo "==> already up to date, nothing to do"
  exit 0
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "error: working tree is dirty; commit or stash before syncing." >&2
  git status --short >&2
  exit 1
fi

echo "==> integrating origin/$UPSTREAM_BRANCH ($([[ "$MODE" == "merge" ]] && echo merge || echo rebase))"
if [[ "$MODE" == "merge" ]]; then
  git merge "origin/$UPSTREAM_BRANCH"
else
  if ! git rebase "origin/$UPSTREAM_BRANCH"; then
    echo "" >&2
    echo "rebase stopped on conflicts. Resolve them, stage the files, then run:" >&2
    echo "  desktop/scripts/sync-origin.sh --continue" >&2
    echo "(or abort with: git rebase --abort)" >&2
    exit 1
  fi
fi

echo ""
echo "==> done: $BRANCH is now on top of origin/$UPSTREAM_BRANCH"
echo "    next: desktop/scripts/build.sh   (rebuild before running the app)"
