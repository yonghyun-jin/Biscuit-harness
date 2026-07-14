#!/bin/sh
# SessionEnd hook — append one metrics line per session to
# ~/.claude/metrics/sessions.jsonl. Pure transcript parsing, no LLM, silent
# on any failure. Personal machine-local data — never committed or shared.
HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"

# The heredoc below occupies stdin, so hand the hook payload to python via env.
BH_HOOK_INPUT=$(cat)
export BH_HOOK_INPUT

python3 - "$HOOK_DIR" <<'PY'
import json, os, sys
from datetime import datetime, timezone

sys.path.insert(0, sys.argv[1])
from _project_name import project_name
from _metric import append_line, harness_version

try:
    data = json.loads(os.environ.get("BH_HOOK_INPUT") or "{}")
except Exception:
    sys.exit(0)

transcript = data.get("transcript_path") or ""
cwd = data.get("cwd") or os.getcwd()
try:
    f = open(transcript)
except OSError:
    sys.exit(0)

HARNESS_SKILLS = {"implement", "ticket", "scope-creation"}
first_ts = last_ts = None
user_msgs = asst_msgs = tool_calls = tool_errors = 0
in_tok = out_tok = cache_tok = skill_uses = 0

with f:
    for line in f:
        try:
            d = json.loads(line)
        except Exception:
            continue
        ts = d.get("timestamp")
        if ts:
            first_ts = first_ts or ts
            last_ts = ts
        t = d.get("type")
        msg = d.get("message") or {}
        content = msg.get("content")
        if t == "assistant":
            asst_msgs += 1
            usage = msg.get("usage") or {}
            in_tok += usage.get("input_tokens") or 0
            out_tok += usage.get("output_tokens") or 0
            cache_tok += usage.get("cache_read_input_tokens") or 0
            if isinstance(content, list):
                for b in content:
                    if isinstance(b, dict) and b.get("type") == "tool_use":
                        tool_calls += 1
                        if (b.get("name") == "Skill"
                                and (b.get("input") or {}).get("skill") in HARNESS_SKILLS):
                            skill_uses += 1
        elif t == "user":
            has_text = isinstance(content, str) and bool(content.strip())
            has_tool_result = False
            if isinstance(content, list):
                for b in content:
                    if isinstance(b, dict):
                        if b.get("type") == "text" and (b.get("text") or "").strip():
                            has_text = True
                        elif b.get("type") == "tool_result":
                            has_tool_result = True
                            if b.get("is_error"):
                                tool_errors += 1
            if has_text and not has_tool_result and not d.get("isMeta"):
                user_msgs += 1

def parse_iso(ts):
    try:
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    except Exception:
        return None

duration_s = 0
a, b = parse_iso(first_ts or ""), parse_iso(last_ts or "")
if a and b:
    duration_s = max(0, int((b - a).total_seconds()))

append_line("sessions.jsonl", {
    "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "session_id": data.get("session_id", ""),
    "project": project_name(cwd),
    "harness_version": harness_version(),
    "end_reason": data.get("reason", ""),
    "duration_s": duration_s,
    "user_msgs": user_msgs,
    "asst_msgs": asst_msgs,
    "tool_calls": tool_calls,
    "tool_errors": tool_errors,
    "input_tokens": in_tok,
    "output_tokens": out_tok,
    "cache_read_tokens": cache_tok,
    "harness_skill_uses": skill_uses,
})
PY
exit 0
