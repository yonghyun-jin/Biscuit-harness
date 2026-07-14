#!/bin/sh
# SessionStart hook — pull the latest harness. Throttled to once per hour,
# silent on any failure (offline, detached HEAD, etc.) so it never blocks a session.
HARNESS_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$HARNESS_DIR/.last-update"

NOW=$(date +%s)
if [ -f "$STAMP" ]; then
  LAST=$(cat "$STAMP" 2>/dev/null || echo 0)
  case "$LAST" in *[!0-9]*) LAST=0 ;; esac
  [ $((NOW - LAST)) -lt 3600 ] && exit 0
fi
echo "$NOW" > "$STAMP"

(cd "$HARNESS_DIR" && git pull --ff-only --quiet) >/dev/null 2>&1 || true
exit 0
