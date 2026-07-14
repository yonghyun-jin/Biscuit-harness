#!/bin/sh
# SessionStart hook — the READ path of the learning loop.
# The learnings file (~/.claude/learnings/<repo>.md, written by
# learn-on-stop.sh) has two tiers, injected differently:
#   # Rules    → injected IN FULL every session (standing knowledge that
#                applies to all work — no relevance matching needed)
#   # Episodes → only "## " heading lines as an index, plus a standing
#                instruction to Read the matching entry before related work
# Small files are injected whole — an index would cost more than it saves.
# Files without section headers are treated as all-episodes (legacy format).
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


def count_tiers(t):
    rules_n = 0
    in_rules = False
    for ln in t.splitlines():
        if ln.strip() == "# Rules":
            in_rules = True
            continue
        if in_rules and ln.startswith("# ") and not ln.startswith("## "):
            in_rules = False
        if in_rules and ln.lstrip().startswith("- "):
            rules_n += 1
    return rules_n, sum(1 for ln in t.splitlines() if ln.startswith("## "))


def log_injection(t):
    try:
        from _metric import log_event
        r, e = count_tiers(t)
        log_event("learn-recall", data.get("session_id", ""), name,
                  {"rules_count": r, "episodes_count": e})
    except Exception:
        pass


# Small file: inject it whole — an index would cost more than it saves.
FULL_TEXT_MAX = 1500
if len(text) <= FULL_TEXT_MAX:
    log_injection(text)
    print(
        f'<personal-learnings project="{name}" source="{path}">\n'
        "Your accumulated learnings from past sessions in this project "
        "(personal, machine-local — never commit or share this content):\n\n"
        f"{text}\n"
        "</personal-learnings>"
    )
    sys.exit(0)

# Large file: two-tier injection.
# Rules = everything between a "# Rules" line and the next level-1 header.
lines = text.splitlines()
rules, in_rules = [], False
for ln in lines:
    if ln.strip() == "# Rules":
        in_rules = True
        continue
    if in_rules and ln.startswith("# ") and not ln.startswith("## "):
        in_rules = False
    if in_rules:
        rules.append(ln)
rules_text = "\n".join(rules).strip()

headings = [ln for ln in lines if ln.startswith("## ")]
index = "\n".join(f"- {h[3:].strip()}" for h in headings)

if not rules_text and not headings:
    sys.exit(0)
log_injection(text)

parts = []
if rules_text:
    parts.append(
        "STANDING RULES for this project — these apply to ALL work this "
        "session, whatever the task:\n\n" + rules_text
    )
if headings:
    parts.append(
        "Index of past episode learnings. BEFORE starting any work related "
        f"to one of these topics, Read {path} and apply the matching "
        "entry:\n\n" + index
    )

body = "\n\n".join(parts)
print(
    f'<personal-learnings project="{name}" source="{path}">\n'
    f"{body}\n\n"
    "This content is personal machine-local memory — never commit or share it.\n"
    "</personal-learnings>"
)
PY
