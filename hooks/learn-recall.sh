#!/bin/sh
# SessionStart hook — the READ path of the rules loop.
# The rules file (written by learn-on-stop.sh) lives IN the project repo
# at <repo>/.claude/rules.md (committed — clone = inherit). Outside a git
# repo, falls back to the legacy machine-local ~/.claude/rules/<project>.md.
# (Script filename stays learn-recall.sh: it is registered by absolute path
# in settings.json — renaming it silently breaks existing installs.)
# Two tiers, injected differently:
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
from _project_name import project_name, git_toplevel

try:
    data = json.loads(os.environ.get("BH_HOOK_INPUT") or "{}")
except Exception:
    sys.exit(0)

cwd = data.get("cwd") or os.getcwd()
name = project_name(cwd)

toplevel = git_toplevel(cwd)
repo_path = os.path.join(toplevel, ".claude", "rules.md") if toplevel else ""
legacy_path = os.path.join(os.path.expanduser("~/.claude/rules"), f"{name}.md")

migrate_note = ""
if repo_path and os.path.isfile(repo_path):
    path, scope = repo_path, "repo"
elif os.path.isfile(legacy_path):
    path, scope = legacy_path, "legacy"
    if toplevel:
        migrate_note = (
            f"\nNOTE: these rules still live at the legacy machine-local "
            f"path. Migrate them: move the content to {repo_path} (create the "
            f"file), delete {legacy_path}, and let the user commit it — from "
            f"then on the whole team inherits them via git."
        )
else:
    sys.exit(0)

try:
    text = open(path).read().strip()
except OSError:
    sys.exit(0)
if not text:
    sys.exit(0)

if scope == "repo":
    sharing_line = (
        "Project rules and episode records accumulated across sessions, "
        "shared with everyone on this project via the repo:"
    )
    footer = ""
else:
    sharing_line = (
        "Your accumulated rules from past sessions in this project "
        "(personal, machine-local):"
    )
    footer = migrate_note


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
                  {"rules_count": r, "episodes_count": e, "source": scope})
    except Exception:
        pass


# Small file: inject it whole — an index would cost more than it saves.
FULL_TEXT_MAX = 1500
if len(text) <= FULL_TEXT_MAX:
    log_injection(text)
    print(
        f'<project-rules project="{name}" source="{path}">\n'
        f"{sharing_line}\n\n"
        f"{text}\n"
        f"{footer}"
        "</project-rules>"
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

parts = [sharing_line]
if rules_text:
    parts.append(
        "STANDING RULES for this project — these apply to ALL work this "
        "session, whatever the task:\n\n" + rules_text
    )
if headings:
    parts.append(
        "Index of past episode records. BEFORE starting any work related "
        f"to one of these topics, Read {path} and apply the matching "
        "entry:\n\n" + index
    )

body = "\n\n".join(parts)
print(
    f'<project-rules project="{name}" source="{path}">\n'
    f"{body}\n"
    f"{footer}"
    "</project-rules>"
)
PY
