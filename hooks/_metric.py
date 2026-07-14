# Shared metric logger for harness hooks — the observability layer.
#
# Two files under ~/.claude/metrics/ (personal, machine-local, never committed):
#   hook-events.jsonl  one line per meaningful hook firing (impact attribution)
#   sessions.jsonl     one line per session (written by metrics-on-end.sh)
#
# Schema is strict: required common fields at the top level, hook-specific
# payload ONLY inside "data". Never add free-form top-level fields.
#
# Performance contract: logging must never slow a hook down. Everything here
# is a single O_APPEND write wrapped in try/except — total cost well under a
# millisecond — and every failure is silent.
#
# Rotation: when a file exceeds MAX_BYTES it is renamed to <name>.1.jsonl
# (one level, previous .1 is overwritten) so metrics can never grow unbounded.
#
# Also runnable as a CLI by shell hooks:
#   BH_HOOK_INPUT='<hook payload json>' python3 _metric.py <hook-name> '<data json>'
import json
import os
import subprocess
import sys
from datetime import datetime, timezone

METRICS_DIR = os.path.expanduser("~/.claude/metrics")
MAX_BYTES = 5 * 1024 * 1024

_version_cache = None


def harness_version():
    global _version_cache
    if _version_cache is None:
        try:
            root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
            r = subprocess.run(
                ["git", "-C", root, "rev-parse", "--short", "HEAD"],
                capture_output=True, text=True, timeout=5,
            )
            _version_cache = r.stdout.strip() if r.returncode == 0 else "unknown"
        except Exception:
            _version_cache = "unknown"
    return _version_cache or "unknown"


def _rotate(path):
    try:
        if os.path.getsize(path) > MAX_BYTES:
            os.replace(path, path[: -len(".jsonl")] + ".1.jsonl")
    except OSError:
        pass


def append_line(filename, record):
    try:
        os.makedirs(METRICS_DIR, exist_ok=True)
        path = os.path.join(METRICS_DIR, filename)
        _rotate(path)
        with open(path, "a") as f:
            f.write(json.dumps(record, separators=(",", ":")) + "\n")
    except Exception:
        pass


def log_event(hook, session_id, project, data):
    append_line("hook-events.jsonl", {
        "ts": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "hook": hook,
        "project": project,
        "session_id": session_id or "",
        "harness_version": harness_version(),
        "data": data if isinstance(data, dict) else {},
    })


if __name__ == "__main__":
    try:
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
        from _project_name import project_name

        payload = {}
        try:
            payload = json.loads(os.environ.get("BH_HOOK_INPUT") or "{}")
        except Exception:
            pass
        data = {}
        if len(sys.argv) > 2:
            try:
                data = json.loads(sys.argv[2])
            except Exception:
                pass
        cwd = payload.get("cwd") or os.getcwd()
        log_event(sys.argv[1], payload.get("session_id", ""), project_name(cwd), data)
    except Exception:
        pass
    sys.exit(0)
