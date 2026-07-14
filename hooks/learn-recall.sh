#!/bin/sh
# SessionStart hook — the READ path of the learning loop.
# Injects an INDEX (the "## " heading lines) of this project's personal
# learnings (~/.claude/learnings/<repo>.md, written by learn-on-stop.sh) into
# the new session's context, plus a standing instruction to Read the relevant
# section before starting related work. Small files are injected whole —
# an index would cost more than it saves.
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"

# The heredoc below occupies stdin, so hand the hook payload to python via env.
BH_HOOK_INPUT=$(cat)
export BH_HOOK_INPUT

python3 - "$HOOK_DIR" <<'PY'
import json, os, sys

sys.path.insert(0, sys.argv[1])
from _project_name import project_name

try:
    data = json.loads(os.environ.get("BH_HOOK_INPUT") or "{}")
except Exception:
    sys.exit(0)

cwd = data.get("cwd") or os.getcwd()
name = project_name(cwd)
path = os.path.join(os.path.expanduser("~/.claude/learnings"), f"{name}.md")
if not os.path.isfile(path):
    sys.exit(0)

try:
    text = open(path).read().strip()
except OSError:
    sys.exit(0)
if not text:
    sys.exit(0)

# Small file: inject it whole — an index would cost more than it saves.
FULL_TEXT_MAX = 1500
if len(text) <= FULL_TEXT_MAX:
    print(
        f'<personal-learnings project="{name}" source="{path}">\n'
        "Your accumulated learnings from past sessions in this project "
        "(personal, machine-local — never commit or share this content):\n\n"
        f"{text}\n"
        "</personal-learnings>"
    )
    sys.exit(0)

# Large file: inject only the index (heading lines). The model reads the
# full entry on demand, at the moment a related request actually arrives.
headings = [ln for ln in text.splitlines() if ln.startswith("## ")]
if not headings:
    sys.exit(0)
index = "\n".join(f"- {h[3:].strip()}" for h in headings)

print(
    f'<personal-learnings-index project="{name}" source="{path}">\n'
    "Index of your learnings from past sessions in this project. "
    f"BEFORE starting any work related to one of these topics, Read {path} "
    "and apply the matching entry. This content is personal machine-local "
    "memory — never commit or share it.\n\n"
    f"{index}\n"
    "</personal-learnings-index>"
)
PY
