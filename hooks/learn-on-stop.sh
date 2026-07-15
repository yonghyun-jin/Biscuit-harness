#!/bin/sh
# Stop hook — before the session ends, intervene ONCE and ask the model to
# record non-obvious rules/episodes from this session.
#
# Rules are PROJECT knowledge and live IN the project repo at
# <repo>/.claude/rules.md, committed to git — cloning the project is how
# anyone (and any machine) inherits them. Outside a git repo we fall back to
# the machine-local legacy path ~/.claude/rules/<project>.md.
# (Script filename stays learn-on-stop.sh: it is registered by absolute path
# in settings.json — renaming it silently breaks existing installs.)

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

cwd = data.get("cwd") or os.getcwd()
name = project_name(cwd)

toplevel = git_toplevel(cwd)
if toplevel:
    target = os.path.join(toplevel, ".claude", "rules.md")
    scope = "repo"
    sharing_note = (
        "This file is COMMITTED to the project repo and read by everyone who "
        "works on this project (their sessions inject it at start). Write only "
        "knowledge that helps build THIS project; never secrets, credentials, "
        "or personal information. Do not commit it yourself — it rides along "
        "with the user's normal commits."
    )
else:
    target = os.path.join(os.path.expanduser("~/.claude/rules"), f"{name}.md")
    scope = "legacy"
    sharing_note = (
        "This directory is not a git repo, so this file is machine-local "
        "personal memory — never commit it or copy it into a repo."
    )
try:
    os.makedirs(os.path.dirname(target), exist_ok=True)
except OSError:
    sys.exit(0)

reason = (
    "Before ending this session: if it produced NON-OBVIOUS rules or episodes — gotchas, "
    "debugging insights, project quirks, corrections the user gave you, decisions "
    f"and their reasons — record them in {target}. The file has two sections; "
    "CLASSIFY each learning before writing it:\n\n"
    "1. '# Rules' — knowledge that applies to future work in this project "
    "GENERALLY: conventions, specs, policies, always/never constraints. The test: "
    "would this still apply when building a completely different feature? If yes, "
    "it is a rule. Write it as ONE distilled, dateless bullet and merge it into "
    "the existing # Rules section (fold into an existing rule if it overlaps; "
    "keep the section under ~20 bullets by consolidating). Rules span every "
    'domain — examples: "API error responses always use {code, message}" / '
    '"DB migrations run in filename date-prefix order; a wrong prefix is '
    'silently skipped" / "check a CI workflow file\'s git log before editing '
    'it" / "all UI follows the mobile spec: z-index layers + breakpoints" / '
    '"external API calls go through the shared retry wrapper".\n\n'
    "2. '# Episodes' — the record of a specific incident or debugging story. "
    "Append under # Episodes as:\n"
    "## <YYYY-MM-DD> — <specific, searchable topic>\n"
    "- <one concise bullet per learning>\n"
    "Episode headings are load-bearing: future sessions see ONLY the heading "
    "lines as an index and decide from them whether to read the entry — name the "
    'concrete system/file/symptom. Bad: "## 2026-07-14 — bug fix". Good: '
    '"## 2026-07-14 — Railway healthcheck path misconfig causes restart loop". '
    "(This heading rule applies to episodes only.)\n\n"
    "For any DECISION made this session (design choice, library pick, "
    "tradeoff, scope cut), do not record just the outcome — record WHY it was "
    "made this way, what CONSTRAINTS forced it, and what to BE CAREFUL about "
    "when touching it later. This file is the project's wiki of decision "
    "rationale and working rules: future sessions reuse it as context instead "
    "of re-deriving decisions or accidentally reversing them.\n\n"
    "If the file is new or lacks these sections, create the '# Rules' / "
    "'# Episodes' structure. Read the file first and do not duplicate what is "
    "already there. If the file has grown past ~150 lines, consolidate while "
    "you're there: merge overlapping entries, drop obsolete ones, and PROMOTE "
    "lessons that recur across episodes into # Rules. Only record non-obvious "
    "items (skip anything derivable from the code, docs, or git history); write "
    "for whoever builds this project months from now. " + sharing_note + " "
    "If this session genuinely produced nothing worth recording, write nothing "
    "and simply end."
)
try:
    from _metric import log_event
    log_event("learn-on-stop", data.get("session_id", ""), name,
              {"action": "prompted", "target": scope})
except Exception:
    pass

print(json.dumps({"decision": "block", "reason": reason}))
sys.exit(0)
PY
