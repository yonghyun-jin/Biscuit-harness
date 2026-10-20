# Transcript reader shared by the learn loop (learn-extract.sh) and the
# metrics hook (metrics-on-end.sh).
#
# Claude Code transcripts (~/.claude/projects/<cwd>/<session>.jsonl) are one
# JSON object per line. Since CLI 2.1.300 they also record every request's
# system prompt, tools and attachments, so a short session is already several
# MB. Everything here streams the file once, pre-filters lines by a cheap
# substring test BEFORE json.loads, and never keeps the raw file in memory.
#
# Two consumers:
#   build_digest(path)   → compact plain text of the conversation for the
#                          headless extractor (bounded, tail-weighted,
#                          secrets scrubbed, no raw tool output)
#   session_stats(path)  → one metrics record (usage deduplicated by
#                          message.id — the transcript writes one line PER
#                          CONTENT BLOCK, each repeating the same usage)
import json
import os
import re

# Lines worth parsing. Everything else (api-request-blob, attachment, mode,
# file-history-*, ...) is skipped by substring before json.loads.
def _pats(*types):
    # Claude Code writes compact JSON; accept the spaced form too so fixtures
    # and other writers are not silently skipped by the prefilter.
    return tuple(p for t in types for p in (f'"type":"{t}"'.encode(), f'"type": "{t}"'.encode()))


_WANT = _pats("user", "assistant", "ai-title", "cost-state", "system")
_WANT_META = _pats("attachment")

_SYSTEM_REMINDER = re.compile(r"<system-reminder>.*?</system-reminder>", re.S)
_LOCAL_CMD = re.compile(r"<local-command-(stdout|caveat)>.*?</local-command-\1>", re.S)

# Secret shapes. Conservative: better a false [REDACTED] in a learning note
# than a key in a committed rules file.
_SECRETS = [
    re.compile(r"sk_(live|test)_[A-Za-z0-9]{8,}"),
    re.compile(r"sk-ant-[A-Za-z0-9_-]{8,}"),
    re.compile(r"\bAKIA[0-9A-Z]{12,}\b"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----.*?(-----END [A-Z ]*PRIVATE KEY-----|$)", re.S),
    re.compile(r"\b[A-Za-z][A-Za-z0-9+.-]*://[^\s/:@]+:[^\s/@]+@"),  # scheme://user:pass@
    re.compile(r"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b"),  # JWT
    re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}"),
    re.compile(r"\b[A-Za-z0-9]{3}8Q~[A-Za-z0-9._~-]{20,}"),  # Entra client secret shape
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{20,}\b"),
    re.compile(r"\bAIza[0-9A-Za-z_-]{30,}\b"),
    re.compile(r"(?i)\b(password|passwd|secret|token|api[_-]?key)\s*[=:]\s*['\"]?[A-Za-z0-9+/=_~.-]{12,}"),
]


def scrub_secrets(text):
    """Return (text, count) with credential-shaped substrings replaced."""
    n = 0
    for rx in _SECRETS:
        text, k = rx.subn("[REDACTED]", text)
        n += k
    return text, n


def _blocks(content):
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    if isinstance(content, list):
        return [b for b in content if isinstance(b, dict)]
    return []


def _text_of(block):
    t = block.get("text")
    if isinstance(t, str):
        return t
    c = block.get("content")
    if isinstance(c, str):
        return c
    if isinstance(c, list):
        return "\n".join(x.get("text", "") for x in c if isinstance(x, dict))
    return ""


def iter_records(path, want=_WANT):
    """Yield (line_no, obj) for lines whose raw bytes contain one of `want`."""
    with open(path, "rb") as f:
        for i, raw in enumerate(f):
            if not any(w in raw for w in want):
                continue
            try:
                yield i, json.loads(raw)
            except Exception:
                continue


def is_typed_prompt(o):
    """A real human prompt (not a hook injection, tool result or system turn)."""
    if o.get("type") != "user" or o.get("isMeta") or o.get("isSidechain"):
        return False
    if o.get("isCompactSummary"):
        return False
    ps = o.get("promptSource")
    if ps is not None:
        return ps == "typed"
    # Older CLIs have no promptSource: a non-meta string message is a prompt.
    m = o.get("message") or {}
    c = m.get("content")
    if isinstance(c, str):
        return bool(c.strip()) and not c.startswith("<")
    return any(b.get("type") == "text" for b in _blocks(c)) and not any(
        b.get("type") == "tool_result" for b in _blocks(c))


def _tool_summary(block):
    name = block.get("name") or "?"
    inp = block.get("input") or {}
    if not isinstance(inp, dict):
        return f"[tool {name}]"
    if name in ("Bash",):
        return f"[tool {name}] {str(inp.get('command', ''))[:200]}"
    if name in ("Edit", "Write", "MultiEdit", "Read", "NotebookEdit"):
        return f"[tool {name}] {inp.get('file_path', '')}"
    if name in ("Grep", "Glob"):
        return f"[tool {name}] {str(inp.get('pattern', ''))[:120]}"
    if name == "Skill":
        return f"[tool {name}] {inp.get('skill', '')}"
    if name == "Agent":
        return f"[tool {name}] {str(inp.get('description', ''))[:120]}"
    return f"[tool {name}]"


def build_digest(path, max_chars=200_000, since_line=0, keep_tail=12,
                 user_cap=4_000, old_assistant_cap=500, error_cap=300):
    """Compact conversation text for the extractor.

    Keeps: typed user prompts, assistant text, tool-call one-liners, failed
    tool results (truncated). Drops: thinking, successful tool output,
    attachments, system reminders. Tail-weighted when over budget: user
    prompts survive longest (corrections live there), old assistant text is
    cut first. Returns (text, info)."""
    items = []  # (kind, text)
    info = {"source_bytes": 0, "source_lines": 0, "typed_prompts": 0,
            "assistant_msgs": 0, "tool_calls": 0, "tool_errors": 0,
            "ai_title": "", "truncated": False, "scrubbed": 0,
            "since_line": since_line, "last_line": 0, "cwd": "", "version": ""}
    try:
        info["source_bytes"] = os.path.getsize(path)
    except OSError:
        pass
    seen_assistant = set()
    last_line = -1
    for i, o in iter_records(path):
        last_line = i
        t = o.get("type")
        if t == "ai-title":
            info["ai_title"] = str(o.get("aiTitle") or "")[:120]
            continue
        if i < since_line:
            continue
        if not info["cwd"] and o.get("cwd"):
            info["cwd"] = o["cwd"]
            info["version"] = str(o.get("version") or "")
        if o.get("isSidechain"):
            continue
        m = o.get("message") or {}
        if t == "user":
            if is_typed_prompt(o):
                txt = "\n".join(_text_of(b) for b in _blocks(m.get("content"))
                                if b.get("type") == "text").strip()
                txt = _SYSTEM_REMINDER.sub("", txt)
                txt = _LOCAL_CMD.sub("", txt).strip()
                if txt:
                    info["typed_prompts"] += 1
                    items.append(("user", txt))
                continue
            for b in _blocks(m.get("content")):
                if b.get("type") == "tool_result" and b.get("is_error"):
                    info["tool_errors"] += 1
                    items.append(("error", _text_of(b)[:error_cap]))
        elif t == "assistant":
            mid = m.get("id")
            key = (mid, o.get("apiBlockIndex"), o.get("uuid"))
            if key in seen_assistant:
                continue
            seen_assistant.add(key)
            if mid and mid not in {k[0] for k in seen_assistant if k[0] != mid}:
                pass
            for b in _blocks(m.get("content")):
                bt = b.get("type")
                if bt == "text":
                    txt = _text_of(b).strip()
                    if txt:
                        items.append(("assistant", txt))
                elif bt == "tool_use":
                    info["tool_calls"] += 1
                    items.append(("tool", _tool_summary(b)))
    info["assistant_msgs"] = len({k[0] for k in seen_assistant if k[0]})
    info["source_lines"] = last_line + 1
    info["last_line"] = last_line + 1

    # --- budget ---
    def total():
        return sum(len(x[1]) for x in items) + 12 * len(items)

    if total() > max_chars:
        info["truncated"] = True
        items = [(k, (v[:user_cap] + " […]") if k == "user" and len(v) > user_cap else v)
                 for k, v in items]
    if total() > max_chars:
        # cut old assistant text; the last keep_tail assistant items stay whole
        idx = [n for n, (k, _) in enumerate(items) if k == "assistant"]
        for n in idx[:-keep_tail] if keep_tail else idx:
            k, v = items[n]
            if len(v) > old_assistant_cap:
                items[n] = (k, v[:old_assistant_cap] + " […]")
    if total() > max_chars:
        # drop oldest non-user items until it fits
        n = 0
        while total() > max_chars and n < len(items):
            if items[n][0] != "user":
                items.pop(n)
            else:
                n += 1
    if total() > max_chars:
        # last resort: drop oldest user items, keep the newest
        while total() > max_chars and len(items) > 1:
            items.pop(0)
        items.insert(0, ("note", "[… earlier conversation omitted for size …]"))

    lines = []
    for k, v in items:
        tag = {"user": "[user]", "assistant": "[assistant]", "error": "[tool error]",
               "tool": "", "note": ""}[k]
        lines.append(f"{tag} {v}".strip() if tag else v)
    text = "\n\n".join(lines)
    text, info["scrubbed"] = scrub_secrets(text)
    info["digest_chars"] = len(text)
    return text, info


def first_cwd(path, max_lines=400):
    """The cwd recorded on the first user/assistant line (directory names in
    ~/.claude/projects are lossy, the transcript's own field is not)."""
    for i, o in iter_records(path, want=_pats("user", "assistant")):
        if o.get("cwd"):
            return o["cwd"]
        if i > max_lines:
            break
    return ""


def is_human_transcript(path, max_lines=4000):
    """Human = started from the CLI and has at least one typed prompt. The
    harness's own extractor and the user's `claude -p` scripts are not."""
    typed = 0
    entry = None
    for i, o in iter_records(path, want=_pats("user")):
        if entry is None and o.get("entrypoint"):
            entry = o["entrypoint"]
        if is_typed_prompt(o):
            typed += 1
            if typed >= 1 and entry is not None:
                break
        if i > max_lines and typed:
            break
    if entry is not None and entry != "cli":
        return False
    return typed >= 1


def session_stats(path, harness_skills=()):
    """One metrics record. Usage deduplicated by message.id; first-turn
    prompt size and natively loaded instruction bytes recorded so the
    global-rules cost can be tracked over time."""
    st = {"user_msgs": 0, "api_calls": 0, "tool_calls": 0, "tool_errors": 0,
          "input_tokens": 0, "cache_creation_tokens": 0, "cache_read_tokens": 0,
          "output_tokens": 0, "first_turn_prompt_tokens": 0, "models": {},
          "cost_usd": None, "instructions_user_bytes": 0,
          "instructions_project_bytes": 0, "harness_skill_uses": 0,
          "first_ts": None, "last_ts": None, "entrypoint": "", "version": "",
          "ai_title": "", "lines": 0, "bytes": 0, "stop_hook_blocks": 0}
    try:
        st["bytes"] = os.path.getsize(path)
    except OSError:
        pass
    seen = set()
    for i, o in iter_records(path, want=_WANT + _WANT_META):
        st["lines"] = i + 1
        t = o.get("type")
        ts = o.get("timestamp")
        if ts:
            st["first_ts"] = st["first_ts"] or ts
            st["last_ts"] = ts
        if t == "ai-title":
            st["ai_title"] = str(o.get("aiTitle") or "")[:120]
        elif t == "cost-state":
            try:
                st["cost_usd"] = float(o.get("totalCostUSD"))
            except Exception:
                pass
        elif t == "attachment":
            a = o.get("attachment") or {}
            if a.get("type") == "instructions" and not st["instructions_user_bytes"]:
                for fdesc in a.get("files") or []:
                    if not isinstance(fdesc, dict):
                        continue
                    n = len(str(fdesc.get("content") or "").encode("utf-8", "replace"))
                    p = str(fdesc.get("path") or "")
                    if p.startswith(os.path.expanduser("~/.claude/")) or fdesc.get("type") == "User":
                        st["instructions_user_bytes"] += n
                    else:
                        st["instructions_project_bytes"] += n
        elif t == "system":
            if o.get("subtype") == "stop_hook_summary" and o.get("preventedContinuation"):
                st["stop_hook_blocks"] += 1
        elif t == "user":
            if not st["entrypoint"] and o.get("entrypoint"):
                st["entrypoint"] = o["entrypoint"]
                st["version"] = str(o.get("version") or "")
            if is_typed_prompt(o):
                st["user_msgs"] += 1
            else:
                for b in _blocks((o.get("message") or {}).get("content")):
                    if b.get("type") == "tool_result" and b.get("is_error"):
                        st["tool_errors"] += 1
        elif t == "assistant":
            m = o.get("message") or {}
            mid = m.get("id")
            for b in _blocks(m.get("content")):
                if b.get("type") == "tool_use":
                    st["tool_calls"] += 1
                    if b.get("name") == "Skill" and (b.get("input") or {}).get("skill") in harness_skills:
                        st["harness_skill_uses"] += 1
            if not mid or mid in seen or m.get("model") == "<synthetic>":
                continue
            seen.add(mid)
            u = m.get("usage") or {}
            inp = u.get("input_tokens") or 0
            cw = u.get("cache_creation_input_tokens") or 0
            cr = u.get("cache_read_input_tokens") or 0
            st["api_calls"] += 1
            st["input_tokens"] += inp
            st["cache_creation_tokens"] += cw
            st["cache_read_tokens"] += cr
            st["output_tokens"] += u.get("output_tokens") or 0
            if st["api_calls"] == 1:
                st["first_turn_prompt_tokens"] = inp + cw + cr
            mdl = str(m.get("model") or "?")
            st["models"][mdl] = st["models"].get(mdl, 0) + 1
    return st
