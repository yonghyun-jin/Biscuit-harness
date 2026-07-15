#!/bin/sh
# PostToolUse hook (Edit|Write|MultiEdit) — flag new domain interface/type
# declarations written inline under apps/ in a monorepo that has a packages/
# dir. Nudges Claude to reuse or relocate the type to packages/shared.
#
# OPT-IN per project: the apps/+packages/shared layout is one team's
# convention, not universal — the hook is inert unless the project has a
# .claude/harness.json containing {"check-type-dup": true}.
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"

# The heredoc below occupies stdin, so hand the hook payload to python via env.
BH_HOOK_INPUT=$(cat)
export BH_HOOK_INPUT

python3 - "$HOOK_DIR" <<'PY'
import json, os, re, sys

sys.path.insert(0, sys.argv[1])

try:
    data = json.loads(os.environ.get("BH_HOOK_INPUT") or "{}")
except Exception:
    sys.exit(0)

ti = data.get("tool_input", {})
path = ti.get("file_path", "") or ""
if "/apps/" not in path or not path.endswith((".ts", ".tsx")):
    sys.exit(0)


def opted_in(start_dir):
    d = start_dir
    while d and d != "/":
        cfg = os.path.join(d, ".claude", "harness.json")
        if os.path.isfile(cfg):
            try:
                with open(cfg) as f:
                    return json.load(f).get("check-type-dup") is True
            except Exception:
                return False
        d = os.path.dirname(d)
    return False


if not opted_in(os.path.dirname(path)):
    sys.exit(0)

# Only inspect content added by this tool call, not the whole file
content = ti.get("new_string") or ti.get("content") or ""
if not content and isinstance(ti.get("edits"), list):  # MultiEdit
    content = "\n".join(e.get("new_string", "") for e in ti["edits"])

decls = re.findall(r"^\s*(?:export\s+)?(?:interface|type)\s+([A-Z]\w*)", content, re.M)
# Component-local prop/state types are conventionally fine inline
decls = [d for d in decls if not d.endswith(("Props", "State"))]
if not decls:
    sys.exit(0)

# Convention only applies to monorepos with a packages/ dir
d = os.path.dirname(path)
packages = None
while d and d != "/":
    if os.path.isdir(os.path.join(d, "packages")):
        packages = os.path.join(d, "packages")
        break
    d = os.path.dirname(d)
if not packages:
    sys.exit(0)

try:
    from _metric import log_event
    from _project_name import project_name
    log_event("check-type-dup", data.get("session_id", ""),
              project_name(data.get("cwd") or os.getcwd()), {"flagged": decls})
except Exception:
    pass

print(
    f"New type declaration(s) inline in apps/: {', '.join(decls)}. "
    f"Project convention: domain types live in packages/shared, not inline in apps/. "
    f"Check {packages} for an existing type to reuse; if none exists, declare it in "
    f"packages/shared and import it here.",
    file=sys.stderr,
)
sys.exit(2)
PY
