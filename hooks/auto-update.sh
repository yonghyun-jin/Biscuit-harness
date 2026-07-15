#!/bin/sh
# SessionStart hook — pull the latest harness. Throttled to once per hour.
# Silent when offline or already up to date. NOT silent when the local clone
# is behind and cannot fast-forward — staleness must never be invisible, or
# teammates drift onto old harness versions with no signal.
# After a successful update, re-runs ./setup (idempotent) so newly added
# skills/hooks are linked without any manual step.
HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$HARNESS_DIR/.last-update"

NOW=$(date +%s)
if [ -f "$STAMP" ]; then
  LAST=$(cat "$STAMP" 2>/dev/null || echo 0)
  case "$LAST" in *[!0-9]*) LAST=0 ;; esac
  [ $((NOW - LAST)) -lt 3600 ] && exit 0
fi

cd "$HARNESS_DIR" || exit 0

# No tracking branch (detached HEAD etc.) — nothing to compare against.
git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1 || { echo "$NOW" > "$STAMP"; exit 0; }

git fetch --quiet >/dev/null 2>&1
FETCH_RC=$?
# Stamp after the attempt: success and offline both wait out the hour
# (offline retry storms are worse than a stale hour).
echo "$NOW" > "$STAMP"
[ "$FETCH_RC" -ne 0 ] && exit 0

BEHIND=$(git rev-list --count 'HEAD..@{u}' 2>/dev/null || echo 0)
case "$BEHIND" in *[!0-9]*) BEHIND=0 ;; esac
[ "$BEHIND" -eq 0 ] && exit 0

if git merge --ff-only --quiet '@{u}' >/dev/null 2>&1; then
  ("$HARNESS_DIR/setup" >/dev/null 2>&1 || true)
  exit 0
fi

echo "biscuit-harness: $BEHIND commit(s) behind origin but cannot fast-forward (local edits or divergence). Tell the user to resolve it: cd $HARNESS_DIR && git status"
exit 0
