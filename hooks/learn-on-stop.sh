#!/bin/sh
# Stop hook — before the session ends, intervene ONCE and ask the model to
# record non-obvious learnings from this session.
#
# The hook script is distributed by the harness (code), but the learnings are
# personal data: they go to ~/.claude/learnings/<project>.md on THIS machine
# only — never into any repo, never shared with the team.

# The heredoc below occupies stdin, so hand the hook payload to python via env.
BH_HOOK_INPUT=$(cat)
export BH_HOOK_INPUT

python3 - <<'PY'
import json, os, subprocess, sys

try:
    data = json.loads(os.environ.get("BH_HOOK_INPUT") or "{}")
except Exception:
    sys.exit(0)

# We already intervened once this session — let it end now (no loops).
if data.get("stop_hook_active"):
    sys.exit(0)

# Trivial sessions have nothing worth recording — skip short transcripts.
transcript = data.get("transcript_path") or ""
try:
    with open(transcript) as f:
        if sum(1 for _ in f) < 20:
            sys.exit(0)
except OSError:
    pass  # can't read it — fail open and still ask

# Project name: git repo name if inside one, else the cwd basename.
cwd = data.get("cwd") or os.getcwd()
name = ""
try:
    r = subprocess.run(
        ["git", "-C", cwd, "rev-parse", "--show-toplevel"],
        capture_output=True, text=True, timeout=5,
    )
    if r.returncode == 0:
        name = os.path.basename(r.stdout.strip())
except Exception:
    pass
name = name or os.path.basename(cwd.rstrip("/")) or "misc"

target = os.path.join(os.path.expanduser("~/.claude/learnings"), f"{name}.md")
try:
    os.makedirs(os.path.dirname(target), exist_ok=True)
except OSError:
    sys.exit(0)

reason = (
    "Before ending this session: if it produced NON-OBVIOUS learnings — gotchas, "
    "debugging insights, project quirks, corrections the user gave you, decisions "
    f"and their reasons — append them to {target} in this format:\n\n"
    "## <YYYY-MM-DD> — <one-line session topic>\n"
    "- <one concise bullet per learning>\n\n"
    "Rules: only non-obvious items (skip anything derivable from the code, docs, or "
    "git history); write for your future self months from now; read the file first "
    "and do not duplicate entries that are already there. This file is the user's "
    "personal machine-local memory — never commit it or copy it into a repo. "
    "If this session genuinely produced nothing worth recording, write nothing and "
    "simply end."
)
print(json.dumps({"decision": "block", "reason": reason}))
sys.exit(0)
PY
