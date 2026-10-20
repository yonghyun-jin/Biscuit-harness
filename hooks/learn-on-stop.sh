#!/bin/sh
# Stop hook — RETIRED in learn loop v4 (2026-10-20). Capture now happens only at
# SessionEnd (learn-extract.sh). This stub exists for one release so machines
# whose settings.json still names it never print "command not found" on every
# turn; `setup` removes the registration, and the file is deleted next release.
cat >/dev/null
exit 0
