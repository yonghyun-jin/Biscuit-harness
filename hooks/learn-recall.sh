#!/bin/sh
# SessionStart hook — the READ path of the learning loop.
# Injects this project's personal learnings (~/.claude/learnings/<repo>.md,
# written by learn-on-stop.sh) into the new session's context.
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

# Keep context lean: entries are appended chronologically, so the tail is
# the most recent — inject at most the last ~6KB.
MAX = 6000
if len(text) > MAX:
    cut = text[-MAX:]
    nl = cut.find("\n## ")  # start at the first complete entry in the window
    text = "…(older entries truncated — full file: " + path + ")…\n" + (cut[nl + 1:] if nl != -1 else cut)

print(
    f'<personal-learnings project="{name}" source="{path}">\n'
    "Your accumulated learnings from past sessions in this project "
    "(personal, machine-local — never commit or share this content):\n\n"
    f"{text}\n"
    "</personal-learnings>"
)
PY
