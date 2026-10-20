#!/bin/sh
# SessionEnd hook + background runner — the WRITE path of the rules loop (v4).
#
# Modes (dispatched on $1):
#   (none)      SessionEnd hook: payload on stdin. Claim this session's ledger
#               job and spawn a detached runner. No git calls, no parsing:
#               the SessionEnd budget is 1.5 s by default. This is only the
#               FAST PATH — SessionEnd may never fire (crash, kill); the sweep
#               is the delivery guarantee.
#   --run <session> <cwd> <transcript> [<since_line>]
#               One extraction. Python slices a bounded digest of the
#               transcript (no LLM), then ONE headless call:
#                 claude -p --safe-mode --tools "" --model <pinned> ...
#               --safe-mode keeps the child from loading hooks, CLAUDE.md,
#               skills, MCP servers or ~/.claude/rules (measured: ~3K tokens
#               of context instead of ~136K). The result lands in
#               <rules_root>/rules-pending/<session>.md for the next session's
#               human-supervised review. Never touches rules.md.
#   --sweep <cwd> <transcript_dir> <exclude_basename>
#               Catch-up: extract every transcript in the dir whose job never
#               completed (at-least-once), re-extract the tail of sessions
#               that grew after extraction (resume), retry deferred jobs after
#               backoff. One sweep at a time (lock), bounded per sweep.
#   --probe     Resolve the claude binary + working flag set and print them.
#   --dry-run <transcript> [<cwd>]   Digest stats + the exact argv, no call.
#
# Ledger: ~/.claude/learn-queue/<session>.json — O_EXCL claim, states:
#   running | done | failed (retry ≤2) | deferred (usage limit / network:
#   backoff, no retry count) | terminal (bad flag/model/budget: no retry,
#   store auto-pauses after 3) | skipped (non-human, disabled, paused).
# Env: BH_LEARN_DISABLE=1 (off), BH_LEARN_INCLUDE_HEADLESS=1 (also extract
# `claude -p` sessions), BH_LEARN_MODEL / BH_LEARN_BUDGET_USD (overrides),
# BH_LEARN_EXTRACT=1 (marks the extractor's own process — recursion guard),
# BH_LEARN_NO_SPAWN=1 (run synchronously; tests), BH_LEARN_FAKE_ERROR (tests).

HOOK_DIR="$(cd "$(dirname "$0")" && pwd)"

# Recursion guard: never schedule extraction from inside the extractor.
[ -n "$BH_LEARN_EXTRACT" ] && exit 0

if [ -z "$1" ]; then
  # The heredoc below occupies stdin, so hand the hook payload to python via env.
  BH_HOOK_INPUT=$(cat)
  export BH_HOOK_INPUT
fi

exec python3 - "$HOOK_DIR" "$@" <<'PY'
import glob, json, os, re, shutil, subprocess, sys, tempfile, time

HOOK_DIR = sys.argv[1]
ARGS = sys.argv[2:]
sys.path.insert(0, HOOK_DIR)
from _project_name import project_name, rules_root, safe_name, store_key
import _digest

QUEUE_DIR = os.path.expanduser("~/.claude/learn-queue")
SCRIPT = os.path.join(HOOK_DIR, "learn-extract.sh")
PROMPT_FILE = os.path.join(HOOK_DIR, "learn-extract-prompt.md")
MODEL = os.environ.get("BH_LEARN_MODEL") or "claude-haiku-5-5"  # pinned: the 'haiku' alias drifts
BUDGET_USD = os.environ.get("BH_LEARN_BUDGET_USD") or "0.10"
MAX_RETRIES = 2          # runner crashes only
STALE_SECS = 600         # a "running" job untouched this long is a dead runner
LIVE_SECS = 7200         # sweep: a transcript touched this recently may be live
BACKOFF_SECS = 3600      # after a usage-limit / network error
DELTA_LINES = 50         # re-extract a done session whose transcript grew this much
MIN_PROMPTS = 1          # typed human prompts below this = trivial
MIN_DIGEST_CHARS = 1500
DIGEST_MAX_CHARS = 200_000
RULES_MAX_CHARS = 40_000
SWEEP_MAX_RUNS = 5
TERMINAL_PAUSE = 3       # consecutive terminal failures that pause a store
CALL_TIMEOUT = 300
PRUNE_DAYS = 30


# ---------------------------------------------------------------- utilities

def now():
    return int(time.time())


def sanitize(s):
    return re.sub(r"[^A-Za-z0-9._-]", "_", s or "")


def qpath(session):
    return os.path.join(QUEUE_DIR, f"{session}.json")


def read_rec(session):
    try:
        with open(qpath(session)) as f:
            rec = json.load(f)
        return rec if isinstance(rec, dict) else {}
    except Exception:
        return {}


def write_rec(session, rec):
    try:
        os.makedirs(QUEUE_DIR, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=QUEUE_DIR, suffix=".tmp")
        with os.fdopen(fd, "w") as f:
            json.dump(rec, f)
        os.replace(tmp, qpath(session))
    except OSError:
        pass


def finish(session, status, **extra):
    rec = read_rec(session)
    rec["status"] = status
    rec["ts"] = now()
    rec.update(extra)
    write_rec(session, rec)


def log(project, session, data):
    try:
        from _metric import log_event
        log_event("learn-extract", session, project, data)
    except Exception:
        pass



def paused(rr):
    try:
        with open(os.path.join(QUEUE_DIR, f".terminal-{store_key(rr)}")) as f:
            return int(f.read().strip() or 0) >= TERMINAL_PAUSE
    except Exception:
        return False


def bump_terminal(rr, reset=False):
    p = os.path.join(QUEUE_DIR, f".terminal-{store_key(rr)}")
    try:
        if reset:
            if os.path.exists(p):
                os.remove(p)
            return
        n = 0
        try:
            with open(p) as f:
                n = int(f.read().strip() or 0)
        except Exception:
            pass
        with open(p, "w") as f:
            f.write(str(n + 1))
    except OSError:
        pass


def in_backoff():
    try:
        return now() - os.path.getmtime(os.path.join(QUEUE_DIR, ".backoff")) < BACKOFF_SECS
    except OSError:
        return False


def set_backoff():
    try:
        os.makedirs(QUEUE_DIR, exist_ok=True)
        with open(os.path.join(QUEUE_DIR, ".backoff"), "w") as f:
            f.write(str(now()))
    except OSError:
        pass


class Lock:
    """O_EXCL lock file with stale detection. wait=0 → non-blocking."""
    def __init__(self, name, wait=0, stale=STALE_SECS):
        self.path = os.path.join(QUEUE_DIR, name)
        self.wait, self.stale, self.held = wait, stale, False

    def __enter__(self):
        os.makedirs(QUEUE_DIR, exist_ok=True)
        deadline = time.time() + self.wait
        while True:
            try:
                fd = os.open(self.path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
                os.write(fd, str(os.getpid()).encode())
                os.close(fd)
                self.held = True
                return self
            except FileExistsError:
                try:
                    if time.time() - os.path.getmtime(self.path) > self.stale:
                        os.remove(self.path)
                        continue
                except OSError:
                    continue
                if time.time() >= deadline:
                    return self
                time.sleep(2)
            except OSError:
                return self

    def __exit__(self, *a):
        if self.held:
            try:
                os.remove(self.path)
            except OSError:
                pass


def count_lines(path):
    try:
        with open(path, "rb") as f:
            return sum(1 for _ in f)
    except OSError:
        return -1


def settle(path, stable=3, max_wait=10):
    """Wait until the transcript stops growing (it is written asynchronously
    and may lag the hook). Returns the final line count."""
    last, since, start = None, time.time(), time.time()
    while time.time() - start < max_wait:
        try:
            st = os.stat(path)
            cur = (st.st_size, int(st.st_mtime))
        except OSError:
            return -1
        if cur != last:
            last, since = cur, time.time()
        elif time.time() - since >= stable:
            break
        time.sleep(0.5)
    return count_lines(path)


# ------------------------------------------------------------- claim logic

def claim(session, transcript=None):
    """Claim the ledger job. Returns (ok, since_line, delta_n).
    A done job is re-claimed only as a DELTA when its transcript grew by
    DELTA_LINES since extraction (sessions resumed after SessionEnd)."""
    os.makedirs(QUEUE_DIR, exist_ok=True)
    fresh = {"status": "running", "ts": now(), "retries": 0, "deltas": 0}
    try:
        with open(qpath(session), "x") as f:
            json.dump(fresh, f)
        return True, 0, 0
    except FileExistsError:
        pass
    except OSError:
        return False, 0, 0
    old = read_rec(session)
    status = old.get("status")
    retries = int(old.get("retries") or 0)
    t = now()
    if status == "running" and t - int(old.get("ts") or 0) < STALE_SECS:
        return False, 0, 0
    if status in ("terminal", "skipped"):
        return False, 0, 0
    if status == "paused":
        old.update({"status": "running", "ts": t})
        write_rec(session, old)
        return True, int(old.get("since_line") or 0), int(old.get("deltas") or 0)
    if status == "done":
        done_lines = int(old.get("lines_at_extract") or 0)
        cur = count_lines(transcript) if transcript else -1
        if not transcript or cur < 0 or cur - done_lines < DELTA_LINES:
            return False, 0, 0
        deltas = int(old.get("deltas") or 0) + 1
        old.update({"status": "running", "ts": t, "deltas": deltas, "retries": 0})
        write_rec(session, old)
        return True, done_lines, deltas
    if status == "deferred":
        if t - int(old.get("ts") or 0) < BACKOFF_SECS:
            return False, 0, 0
        old.update({"status": "running", "ts": t})
        write_rec(session, old)
        return True, int(old.get("since_line") or 0), int(old.get("deltas") or 0)
    if status in ("failed", "running"):
        if retries >= MAX_RETRIES:
            return False, 0, 0
        old.update({"status": "running", "ts": t, "retries": retries + 1})
        write_rec(session, old)
        return True, int(old.get("since_line") or 0), int(old.get("deltas") or 0)
    old.update({"status": "running", "ts": t})
    write_rec(session, old)
    return True, 0, 0


# -------------------------------------------------- claude binary and flags

def _semver(p):
    try:
        return tuple(int(x) for x in os.path.basename(p).split(".")[:3])
    except Exception:
        return (0, 0, 0)


def resolve_bin():
    cands = [os.environ.get("BH_CLAUDE_BIN"), os.environ.get("CLAUDE_CODE_EXECPATH")]
    vers = glob.glob(os.path.expanduser("~/.local/share/claude/versions/*"))
    cands += sorted(vers, key=_semver, reverse=True)
    cands.append(shutil.which("claude"))
    for c in cands:
        if c and os.path.isfile(c) and os.access(c, os.X_OK):
            return c
    return ""


def child_env():
    env = {k: v for k, v in os.environ.items()
           if not (k.startswith("CLAUDE_CODE_") or k in ("CLAUDECODE", "CLAUDE_PID",
                                                           "CLAUDE_EFFORT", "BH_HOOK_INPUT"))}
    env["BH_LEARN_EXTRACT"] = "1"
    return env


def bin_version(b):
    try:
        r = subprocess.run([b, "--version"], capture_output=True, text=True,
                           timeout=20, env=child_env())
        m = re.search(r"(\d+\.\d+\.\d+)", r.stdout or "")
        return m.group(1) if m else "unknown"
    except Exception:
        return "unknown"


BASE_FLAGS = ["-p", "--model", MODEL, "--tools", "", "--max-turns", "3",
              "--max-budget-usd", BUDGET_USD, "--no-session-persistence",
              "--disable-slash-commands", "--output-format", "json"]
LADDER = [
    ("safe-mode+effort", ["--safe-mode", "--effort", "low"]),
    ("safe-mode", ["--safe-mode"]),
    ("disable-hooks", ["--settings", '{"disableAllHooks":true}']),
]


def call_claude(b, flags, system_prompt, prompt, timeout=CALL_TIMEOUT):
    argv = [b] + BASE_FLAGS + flags + ["--system-prompt", system_prompt]
    try:
        r = subprocess.run(argv, input=prompt, capture_output=True, text=True,
                           timeout=timeout, cwd=tempfile.gettempdir(), env=child_env())
    except subprocess.TimeoutExpired:
        return 124, None, "timeout"
    except Exception as e:
        return 1, None, str(e)[:300]
    obj = None
    try:
        obj = json.loads(r.stdout)
    except Exception:
        pass
    err = (r.stderr or "").strip()
    if not err and isinstance(obj, dict) and (obj.get("is_error") or r.returncode != 0):
        # headless errors often arrive only in the JSON result text
        err = str(obj.get("result") or obj.get("error") or obj.get("subtype") or "")
    return r.returncode, obj, err[:600]


def classify(rc, obj, err):
    """ok | deferred (try later, no retry burned) | terminal (config) | failed (retry)"""
    if obj and obj.get("subtype") == "success" and not obj.get("is_error") and rc == 0:
        return "ok"
    text = (err or "") + " " + (json.dumps(obj)[:2000] if obj else "")
    low = text.lower()
    if any(s in low for s in ("usage limit", "rate limit", "rate_limit", "429", "529",
                              "overloaded", "econnreset", "enotfound", "etimedout",
                              "network", "fetch failed", "not logged in", "/login",
                              "authentication", "unauthorized")):
        return "deferred"
    if any(s in low for s in ("unknown option", "unrecognized", "invalid model",
                              "not_found_error", "model not found", "max_budget",
                              "invalid argument", "error_max_turns", "too long",
                              "prompt is too long", "invalid_request")):
        return "terminal"
    return "failed"


def caps_path(version):
    return os.path.join(QUEUE_DIR, f"caps-{sanitize(version)}.json")


def resolve_flags(b, version, force=False):
    """Working flag set for this binary, found once by a ~2 KB probe call and
    cached per version. Also records whether --safe-mode really isolated the
    child from the global context (baseline tokens)."""
    if not force:
        try:
            with open(caps_path(version)) as f:
                caps = json.load(f)
            if caps.get("ladder") and isinstance(caps.get("flags"), list):
                return caps
        except Exception:
            pass
    probe_prompt = "Reply with exactly the single word OK and nothing else.\n" + ("x " * 900)
    sysp = "You are a probe. Reply with the single word OK."
    result = {"version": version, "ts": now(), "ladder": "", "flags": [], "ok": False}
    for name, flags in LADDER:
        rc, obj, err = call_claude(b, flags, sysp, probe_prompt, timeout=120)
        kind = classify(rc, obj, err)
        if kind == "ok":
            u = obj.get("usage") or {}
            ctx = (u.get("input_tokens") or 0) + (u.get("cache_creation_input_tokens") or 0) \
                + (u.get("cache_read_input_tokens") or 0)
            result.update({"ladder": name, "flags": flags, "ok": True, "probe_tokens": ctx,
                           "isolated": ctx < 15000, "cost_usd": obj.get("total_cost_usd")})
            break
        result.setdefault("errors", []).append({"ladder": name, "kind": kind, "err": err[:200]})
        if kind == "deferred":
            break  # not a flag problem — do not burn the ladder
    try:
        os.makedirs(QUEUE_DIR, exist_ok=True)
        with open(caps_path(version), "w") as f:
            json.dump(result, f)
    except OSError:
        pass
    return result


# ---------------------------------------------------------- the extraction

def rules_excerpt(path):
    try:
        text = open(path).read()
    except OSError:
        return "(no rules file yet — nothing counts as a duplicate)"
    if len(text) <= RULES_MAX_CHARS:
        return text
    # too big to inline whole: the # Rules section + episode headings
    lines = text.splitlines()
    out, in_rules = [], False
    for ln in lines:
        if re.match(r"^# Rules\b", ln):
            in_rules = True
        elif ln.startswith("# "):
            in_rules = False
        if in_rules or ln.startswith("## "):
            out.append(ln)
    return "\n".join(out)[:RULES_MAX_CHARS]


_CONF = re.compile(r"\s*\((?:confidence:\s*)?(high|medium|low)\)\s*$", re.I)


def parse_fragment(result):
    """Return (text, contract, dropped_low). contract: text | none | violated."""
    lines = (result or "").splitlines()
    start = None
    for i, ln in enumerate(lines):
        if re.match(r"^#\s*(Rules|Episodes)\b", ln.strip()):
            start = i
            break
    if start is None:
        stripped = (result or "").strip()
        if not stripped or stripped.upper().startswith("NOTHING"):
            return "", "none", 0
        return "", "violated", 0
    out, dropped = [], 0
    for ln in lines[start:]:
        s = ln.strip()
        if s in ("NOTHING", "```", "```markdown", "```md"):
            continue
        m = _CONF.search(ln)
        if m:
            if m.group(1).lower() == "low" and s.startswith("- "):
                dropped += 1
                continue
            ln = ln[:m.start()]
        out.append(ln.rstrip())
    text = "\n".join(out).strip()
    if not any(l.lstrip().startswith("- ") for l in text.splitlines()):
        return "", "none", dropped
    return text, "text", dropped


def run_one(session, cwd, transcript, since_line=0, delta_n=0, from_hook=False):
    """One extraction; the ledger job is already claimed by the caller."""
    if os.environ.get("BH_LEARN_DISABLE"):
        finish(session, "skipped", reason="disabled")
        return
    rr = rules_root(cwd)
    project = project_name(cwd)
    if rr["scope"] == "repo":
        try:
            with open(os.path.join(rr["toplevel"], ".claude", "harness.json")) as f:
                if json.load(f).get("learn") is False:
                    finish(session, "skipped", reason="harness.json learn:false")
                    return
        except Exception:
            pass
    if paused(rr):
        finish(session, "paused", reason="store paused after terminal failures (re-run setup)")
        log(project, session, {"action": "paused"})
        return

    lines = settle(transcript, max_wait=10 if from_hook else 30)
    if lines < 0:
        finish(session, "skipped", reason="transcript unreadable")
        log(project, session, {"action": "skipped", "reason": "no-transcript"})
        return
    if not os.environ.get("BH_LEARN_INCLUDE_HEADLESS") and not _digest.is_human_transcript(transcript):
        finish(session, "skipped", reason="non-human session")
        log(project, session, {"action": "skipped", "reason": "non-human"})
        return

    digest, info = _digest.build_digest(transcript, max_chars=DIGEST_MAX_CHARS, since_line=since_line)
    base = {"source_bytes": info["source_bytes"], "source_lines": info["source_lines"],
            "digest_chars": info["digest_chars"], "truncated": info["truncated"],
            "scrub_count": info["scrubbed"], "lines_at_extract": info["last_line"],
            "since_line": since_line, "deltas": delta_n, "typed_prompts": info["typed_prompts"]}
    if info["typed_prompts"] < MIN_PROMPTS or info["digest_chars"] < MIN_DIGEST_CHARS:
        finish(session, "done", entries=0, reason="trivial", **base)
        log(project, session, {"action": "done", "entries": 0, "reason": "trivial", **base})
        return

    pending_dir = rr["pending"]
    try:
        os.makedirs(pending_dir, exist_ok=True)
        gi = os.path.join(pending_dir, ".gitignore")
        if not os.path.exists(gi):
            with open(gi, "w") as f:
                f.write("*\n")  # unreviewed machine output must never be committed
    except OSError:
        finish(session, "failed", error="cannot create rules-pending dir", **base)
        log(project, session, {"action": "failed", "error": "pending-dir"})
        return
    try:
        with open(PROMPT_FILE) as f:
            system_prompt = f.read()
    except OSError:
        finish(session, "terminal", error="prompt template missing", **base)
        log(project, session, {"action": "terminal", "error": "no-template"})
        return

    date = time.strftime("%Y-%m-%d")
    prompt = (
        f"PROJECT: {project}\nTODAY: {date} (use it in episode headings)\n"
        f"SESSION TITLE: {info['ai_title'] or '(none)'}\n"
        + (f"NOTE: this is a continuation (delta #{delta_n}) of an already-extracted session; "
           "only the new part is included.\n" if delta_n else "")
        + f"\n=== EXISTING RULES FILE ({rr['rules']}) — never repeat what is already here ===\n"
        + rules_excerpt(rr["rules"])
        + f"\n\n=== SESSION DIGEST ({info['typed_prompts']} prompts; truncated={info['truncated']}) ===\n"
        + digest + "\n"
    )

    fake = os.environ.get("BH_LEARN_FAKE_ERROR")
    started = time.time()
    with Lock(".run.lock", wait=180):
        if in_backoff() and not fake:
            finish(session, "deferred", reason="backoff", **base)
            log(project, session, {"action": "deferred", "reason": "backoff"})
            return
        b = resolve_bin()
        if not b:
            finish(session, "terminal", error="no claude binary found", **base)
            log(project, session, {"action": "terminal", "error": "no-binary"})
            return
        version = bin_version(b)
        if fake:
            rc, obj, err = (1, None, {"429": "429 rate limit", "flag": "error: unknown option",
                                      "crash": "boom"}.get(fake, fake))
            caps = {"ladder": "fake", "flags": []}
        else:
            caps = resolve_flags(b, version)
            if not caps.get("ok"):
                errs = caps.get("errors") or []
                if errs and errs[-1].get("kind") == "deferred":
                    set_backoff()
                    finish(session, "deferred", reason="probe: " + errs[-1].get("err", "")[:120], **base)
                    log(project, session, {"action": "deferred", "reason": "probe-deferred"})
                    return
                finish(session, "terminal", error="no working flag set: " + json.dumps(errs)[:300], **base)
                bump_terminal(rr)
                log(project, session, {"action": "terminal", "error": "no-flags"})
                return
            rc, obj, err = call_claude(b, caps["flags"], system_prompt, prompt)
    secs = int(time.time() - started)
    kind = classify(rc, obj, err)
    meta = {"model": MODEL, "claude_version": version, "claude_bin": b, "ladder": caps.get("ladder"),
            "secs": secs, **base}
    if kind == "deferred":
        set_backoff()
        finish(session, "deferred", error=err[:200], **meta)
        log(project, session, {"action": "deferred", "error": err[:120], "secs": secs})
        return
    if kind == "terminal":
        finish(session, "terminal", error=(err or json.dumps(obj or {}))[:200], **meta)
        bump_terminal(rr)
        log(project, session, {"action": "terminal", "error": (err or "")[:120], "secs": secs})
        return
    if kind == "failed":
        finish(session, "failed", error=(err or f"exit {rc}")[:200], **meta)
        log(project, session, {"action": "failed", "error": (err or f"exit {rc}")[:120], "secs": secs})
        return
    bump_terminal(rr, reset=True)
    usage = obj.get("usage") or {}
    meta.update({"cost_usd": obj.get("total_cost_usd"), "num_turns": obj.get("num_turns"),
                 "usage": {k: usage.get(k) for k in ("input_tokens", "cache_creation_input_tokens",
                                                     "cache_read_input_tokens", "output_tokens")}})
    text, contract, dropped = parse_fragment(obj.get("result") or "")
    text, n2 = _digest.scrub_secrets(text)
    meta["scrub_count"] += n2
    meta["dropped_low"] = dropped
    meta["contract"] = contract
    if contract != "text":
        finish(session, "done", entries=0, **meta)
        log(project, session, {"action": "done", "entries": 0, **{k: meta[k] for k in
            ("contract", "cost_usd", "secs", "claude_version", "ladder", "digest_chars")}})
        return
    entries = sum(1 for ln in text.splitlines() if ln.lstrip().startswith("- "))
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    title = info["ai_title"].replace("-->", "") if info["ai_title"] else ""
    head = (f"<!-- extracted from session {session}" + (f' ("{title}")' if title else "")
            + (f" delta #{delta_n}" if delta_n else "") + f" at {stamp} by {MODEL}; "
            f"{entries} candidate(s), {dropped} low-confidence dropped -->\n")
    name = f"{session}-d{delta_n}.md" if delta_n else f"{session}.md"
    try:
        fd, tmp = tempfile.mkstemp(dir=pending_dir, suffix=".tmp")
        with os.fdopen(fd, "w") as f:
            f.write(head + text + "\n")
        os.replace(tmp, os.path.join(pending_dir, name))  # atomic: never a half-written fragment
    except OSError as e:
        finish(session, "failed", error=str(e)[:200], **meta)
        log(project, session, {"action": "failed", "error": "write"})
        return
    finish(session, "done", entries=entries, fragment=os.path.join(pending_dir, name), **meta)
    log(project, session, {"action": "done", "entries": entries, **{k: meta[k] for k in
        ("contract", "cost_usd", "secs", "claude_version", "ladder", "digest_chars", "num_turns")}})


# ---------------------------------------------------------------- the sweep

def sweep(cwd, tdir, exclude):
    """Extract every eligible transcript in the dir that has no completed job.
    Bounded, locked, and oldest-first so a crashed session is picked up
    before it ages out of Claude Code's 30-day transcript cleanup."""
    with Lock(".sweep.lock", wait=0) as lk:
        if not lk.held:
            return
        t = now()
        # prune ledger records older than the transcript retention
        for p in glob.glob(os.path.join(QUEUE_DIR, "*.json")):
            try:
                rec = json.load(open(p))
                if rec.get("status") in ("done", "skipped") and t - int(rec.get("ts") or t) > PRUNE_DAYS * 86400:
                    os.remove(p)
            except Exception:
                continue
        try:
            names = [n for n in os.listdir(tdir) if n.endswith(".jsonl") and n != exclude]
        except OSError:
            return
        paths = [os.path.join(tdir, n) for n in names]
        paths.sort(key=lambda p: os.path.getmtime(p) if os.path.exists(p) else 0)
        runs = 0
        for path in paths:
            if runs >= SWEEP_MAX_RUNS:
                break
            try:
                if t - os.path.getmtime(path) < LIVE_SECS:
                    continue  # possibly a live session — a later sweep gets it
            except OSError:
                continue
            session = sanitize(os.path.basename(path)[: -len(".jsonl")])
            if not session:
                continue
            ok, since, dn = claim(session, path)
            if not ok:
                continue
            # the transcript's own cwd is authoritative (dir names are lossy)
            run_one(session, _digest.first_cwd(path) or cwd, path, since, dn)
            runs += 1


def spawn_detached(args):
    env = dict(os.environ)
    if os.environ.get("CLAUDE_CODE_EXECPATH") and not env.get("BH_CLAUDE_BIN"):
        env["BH_CLAUDE_BIN"] = os.environ["CLAUDE_CODE_EXECPATH"]
    env.pop("BH_HOOK_INPUT", None)
    if os.environ.get("BH_LEARN_NO_SPAWN"):
        subprocess.run([SCRIPT, *args], env=env)
        return
    try:
        subprocess.Popen([SCRIPT, *args], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         stdin=subprocess.DEVNULL, start_new_session=True, close_fds=True, env=env)
    except Exception:
        pass


# ------------------------------------------------------------ mode dispatch

if ARGS and ARGS[0] == "--run" and len(ARGS) >= 4:
    since = int(ARGS[4]) if len(ARGS) > 4 and ARGS[4].isdigit() else 0
    dn = int(ARGS[5]) if len(ARGS) > 5 and ARGS[5].isdigit() else 0
    run_one(ARGS[1], ARGS[2], ARGS[3], since, dn, from_hook=(len(ARGS) > 6 and ARGS[6] == "hook"))
    if len(ARGS) > 6 and ARGS[6] == "hook":
        # idle time right after a session ended: catch up on this folder
        sweep(ARGS[2], os.path.dirname(ARGS[3]), os.path.basename(ARGS[3]))
    sys.exit(0)

if ARGS and ARGS[0] == "--sweep" and len(ARGS) == 4:
    sweep(ARGS[1], ARGS[2], ARGS[3])
    sys.exit(0)

if ARGS and ARGS[0] == "--probe":
    b = resolve_bin()
    v = bin_version(b) if b else "unknown"
    caps = resolve_flags(b, v, force="--force" in ARGS) if b else {"ok": False, "error": "no binary"}
    print(json.dumps({"binary": b, "version": v, "model": MODEL, "budget_usd": BUDGET_USD, **caps}, indent=1))
    sys.exit(0 if caps.get("ok") else 1)

if ARGS and ARGS[0] == "--dry-run" and len(ARGS) >= 2:
    path = ARGS[1]
    if not os.path.isfile(path):
        print(json.dumps({"error": f"no such transcript: {path}"}))
        sys.exit(1)
    cwd = ARGS[2] if len(ARGS) > 2 else os.getcwd()
    digest, info = _digest.build_digest(path, max_chars=DIGEST_MAX_CHARS)
    rr = rules_root(cwd)
    b = resolve_bin()
    print(json.dumps({"transcript": path, "human": _digest.is_human_transcript(path),
                      "info": info, "rules_root": rr, "binary": b, "model": MODEL,
                      "argv": [b] + BASE_FLAGS + LADDER[0][1] + ["--system-prompt", "<file>"],
                      "prompt_chars": len(digest) + len(rules_excerpt(rr["rules"]))}, indent=1))
    if "--show" in ARGS:
        print(digest[:1500])
    sys.exit(0)

# ---- hook mode (SessionEnd): payload via BH_HOOK_INPUT; NO git, NO parsing ----
try:
    data = json.loads(os.environ.get("BH_HOOK_INPUT") or "{}")
except Exception:
    sys.exit(0)
try:
    if os.environ.get("BH_LEARN_DISABLE"):
        sys.exit(0)
    cwd = data.get("cwd") or os.getcwd()
    transcript = data.get("transcript_path") or ""
    session = sanitize(data.get("session_id") or (os.path.basename(transcript)[:-6] if transcript else ""))
    if not session:
        sys.exit(0)
    if not transcript or not os.path.exists(transcript):
        log(os.path.basename(cwd), session, {"action": "skipped", "reason": "no-transcript",
                                             "end_reason": data.get("reason")})
        sys.exit(0)
    ok, since, dn = claim(session, transcript)
    if not ok:
        sys.exit(0)
    rec = read_rec(session)
    rec["end_reason"] = data.get("reason")
    write_rec(session, rec)
    log(os.path.basename(cwd), session, {"action": "launched", "end_reason": data.get("reason"),
                                         "delta": dn})
    spawn_detached(["--run", session, cwd, transcript, str(since), str(dn), "hook"])
except SystemExit:
    raise
except Exception:
    pass
sys.exit(0)
PY
