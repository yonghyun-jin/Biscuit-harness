#!/bin/sh
# SessionEnd hook — append one metrics line per HUMAN session to
# ~/.claude/metrics/sessions.jsonl. Pure transcript parsing (shared reader in
# _digest.py: usage deduplicated by message.id, cheap substring prefilter), no
# LLM, silent on any failure. Personal machine-local data — never committed.
# Skips the harness's own headless extractor and other `claude -p` runs so the
# numbers describe the person's sessions, not the machinery.
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"

[ -n "$BH_LEARN_EXTRACT" ] && exit 0

# The heredoc below occupies stdin, so hand the hook payload to python via env.
BH_HOOK_INPUT=$(cat)
export BH_HOOK_INPUT

python3 - "$HOOK_DIR" <<'PY'
import json, os, sys
from datetime import datetime, timezone

sys.path.insert(0, sys.argv[1])
from _project_name import project_name
from _metric import append_line, harness_version
import _digest

try:
    data = json.loads(os.environ.get("BH_HOOK_INPUT") or "{}")
except Exception:
    sys.exit(0)

transcript = data.get("transcript_path") or ""
cwd = data.get("cwd") or os.getcwd()
if not transcript or not os.path.isfile(transcript):
    sys.exit(0)

# Harness skills = whatever the repo ships (skills/<name>/SKILL.md).
skills_dir = os.path.join(os.path.dirname(sys.argv[1]), "skills")
try:
    HARNESS_SKILLS = {
        d for d in os.listdir(skills_dir)
        if os.path.isfile(os.path.join(skills_dir, d, "SKILL.md"))
    }
except OSError:
    HARNESS_SKILLS = set()

try:
    st = _digest.session_stats(transcript, HARNESS_SKILLS)
except Exception:
    sys.exit(0)

# Human sessions only: started from the CLI with at least one typed prompt.
if (st["entrypoint"] and st["entrypoint"] != "cli") or st["user_msgs"] == 0:
    sys.exit(0)


def parse_iso(ts):
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except Exception:
        return None


duration_s = 0
a, b = parse_iso(st["first_ts"] or ""), parse_iso(st["last_ts"] or "")
if a and b:
    duration_s = max(0, int((b - a).total_seconds()))

append_line("sessions.jsonl", {
    "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "session_id": data.get("session_id", ""),
    "project": project_name(cwd),
    "harness_version": harness_version(),
    "claude_version": st["version"],
    "end_reason": data.get("reason", ""),
    "duration_s": duration_s,
    "user_msgs": st["user_msgs"],
    "asst_msgs": st["api_calls"],
    "api_calls": st["api_calls"],
    "tool_calls": st["tool_calls"],
    "tool_errors": st["tool_errors"],
    "input_tokens": st["input_tokens"],
    "cache_creation_tokens": st["cache_creation_tokens"],
    "cache_read_tokens": st["cache_read_tokens"],
    "output_tokens": st["output_tokens"],
    "first_turn_prompt_tokens": st["first_turn_prompt_tokens"],
    "instructions_user_bytes": st["instructions_user_bytes"],
    "instructions_project_bytes": st["instructions_project_bytes"],
    "cost_usd": st["cost_usd"],
    "models": st["models"],
    "stop_hook_blocks": st["stop_hook_blocks"],
    "transcript_bytes": st["bytes"],
    "harness_skill_uses": st["harness_skill_uses"],
})
PY
exit 0
