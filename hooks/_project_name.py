# Shared helpers for the learning loop hooks.
# Used by learn-extract.sh (write path), learn-recall.sh (read path),
# metrics-on-end.sh and bin/migrate-legacy-rules — all MUST agree so a
# directory always maps to the same rules store.
#
# project_name: most stable first — origin remote repo name (same across
#   machines and folder renames) → git toplevel folder name → cwd basename.
# git_toplevel: repo root (of the CURRENT worktree), "" outside a repo.
# git_main_root: root of the MAIN worktree (via --git-common-dir) so linked
#   worktrees share one review queue; equals git_toplevel for plain repos.
# rules_root: where this cwd's rules.md and rules-pending/ live:
#   git repo   → <toplevel>/.claude/rules.md, <main>/.claude/rules-pending/
#   otherwise  → ~/.claude/learn-rules/<basename>-<hash8>/{rules.md,rules-pending/}
#   NEVER under ~/.claude/rules/ — Claude Code loads every file there into
#   every project on the machine (that collision was the v3 cost bug).
import hashlib
import os
import re
import shutil
import subprocess

LEARN_ROOT = os.path.expanduser("~/.claude/learn-rules")
QUEUE_DIR = os.path.expanduser("~/.claude/learn-queue")  # extraction ledger
MAX_RETRIES = 2       # runner crashes only; usage limits defer, config errors are terminal
TERMINAL_PAUSE = 3    # consecutive terminal failures that pause a store (setup re-arms)
UNCLAIMED_DIR = os.path.join(LEARN_ROOT, "_unclaimed")
LEGACY_RULES_DIR = os.path.expanduser("~/.claude/rules")  # native, global — read-only for us
NATIVE_RULES_FILE = "biscuit-rules.md"  # <repo>/.claude/rules/<this> = native opt-in


def _git(cwd, *args):
    try:
        r = subprocess.run(
            ["git", "-C", cwd, *args],
            capture_output=True, text=True, timeout=5,
        )
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""


def git_toplevel(cwd):
    return _git(cwd, "rev-parse", "--show-toplevel")


def git_main_root(cwd):
    """Root of the main worktree ('' outside a repo). Linked worktrees of one
    repo all resolve to the same path, so pending fragments are shared."""
    common = _git(cwd, "rev-parse", "--git-common-dir")
    if not common:
        return ""
    if not os.path.isabs(common):
        common = os.path.join(cwd, common)
    common = os.path.normpath(common)
    if os.path.basename(common) == ".git":
        return os.path.dirname(common)
    return git_toplevel(cwd)  # bare/odd layouts: fall back to this worktree


def project_name(cwd):
    name = ""
    origin = _git(cwd, "remote", "get-url", "origin")
    if origin:
        name = os.path.basename(origin.rstrip("/"))
        if name.endswith(".git"):
            name = name[:-4]
    if not name:
        top = git_toplevel(cwd)
        name = os.path.basename(top) if top else ""
    return name or os.path.basename(cwd.rstrip("/")) or "misc"


def safe_name(name, limit=40):
    s = re.sub(r"[^A-Za-z0-9._-]+", "-", name or "").strip("-.")
    return (s or "misc")[:limit]


def store_dir(path):
    """Machine-local store for a NON-git directory: readable basename plus a
    short hash of the real path (no collisions between same-named folders)."""
    real = os.path.realpath(path)
    h = hashlib.sha1(real.encode("utf-8", "replace")).hexdigest()[:8]
    base = safe_name(os.path.basename(real.rstrip("/")) or "root")
    return os.path.join(LEARN_ROOT, f"{base}-{h}")


def rules_root(cwd):
    """Return a dict describing where this cwd's rules live.
    keys: scope ('repo'|'local'), toplevel, root, rules, pending, native."""
    top = git_toplevel(cwd)
    if top:
        main = git_main_root(cwd) or top
        return {
            "scope": "repo",
            "toplevel": top,
            "root": os.path.join(top, ".claude"),
            "rules": os.path.join(top, ".claude", "rules.md"),
            "pending": os.path.join(main, ".claude", "rules-pending"),
            "native": os.path.join(top, ".claude", "rules", NATIVE_RULES_FILE),
        }
    root = store_dir(cwd)
    return {
        "scope": "local",
        "toplevel": "",
        "root": root,
        "rules": os.path.join(root, "rules.md"),
        "pending": os.path.join(root, "rules-pending"),
        # Claude Code loads <cwd>/.claude/rules/*.md natively for any folder,
        # git or not — the same opt-in works here (no hook size cap).
        "native": _native_for(cwd),
    }


def _native_for(cwd):
    d = os.path.join(cwd, ".claude", "rules")
    if os.path.realpath(d) == os.path.realpath(LEGACY_RULES_DIR):
        return ""  # cwd is $HOME: that directory is the global one we must never use
    return os.path.join(d, NATIVE_RULES_FILE)


def legacy_rules_path(cwd):
    """v3 location (~/.claude/rules/<project>.md). Only ever READ, to nudge
    migration; the harness never writes there again."""
    return os.path.join(LEGACY_RULES_DIR, f"{project_name(cwd)}.md")


_SHAPE = re.compile(r"^(# Rules\b|# Episodes\b|## \d{4}-\d\d-\d\d\s)", re.M)


def looks_like_harness_rules(text):
    """Does this text have the harness's rules-file shape?"""
    return bool(_SHAPE.search(text or ""))


def store_key(rr):
    """Per-store key for state files (terminal-failure counter etc.): the
    folder's name plus a hash of the review queue's real location, so two
    repos (or two same-named folders) never share state."""
    base = rr.get("toplevel") or rr["root"]
    anchor = os.path.dirname(rr["pending"])
    h = hashlib.sha1(os.path.realpath(anchor).encode("utf-8", "replace")).hexdigest()[:8]
    return safe_name(os.path.basename(base.rstrip("/")) or "root") + "-" + h



def adopt_v3_queue(rr):
    """v3 kept one review queue per worktree (<toplevel>/.claude/rules-pending/);
    v4 keeps one per repo, in the main worktree. In a linked worktree, move the
    fragments an old private queue still holds into the shared queue (else
    they would never be reviewed) and remove the old queue once nothing but
    its own .gitignore is left. Returns the number of fragments moved."""
    if rr.get("scope") != "repo" or not rr.get("toplevel"):
        return 0
    old = os.path.join(rr["toplevel"], ".claude", "rules-pending")
    new = rr["pending"]
    if not os.path.isdir(old) or os.path.realpath(old) == os.path.realpath(new):
        return 0
    try:
        names = sorted(os.listdir(old))
    except OSError:
        return 0
    moved = 0
    for f in names:
        if f == ".gitignore":
            continue
        # a claim left by a session that never finished: re-queue under its original name
        orig = f.split("~", 2)[2] if f.startswith(".reviewing~") and f.count("~") >= 2 else f
        if not orig.endswith(".md") or orig.startswith("."):
            continue
        try:
            os.makedirs(new, exist_ok=True)
            gi = os.path.join(new, ".gitignore")
            if not os.path.exists(gi):
                with open(gi, "w") as fh:
                    fh.write("*\n")
            dst = os.path.join(new, orig)
            n = 1
            while os.path.exists(dst):
                n += 1
                dst = os.path.join(new, f"{orig[:-3]}-wt{n}.md")
            src = os.path.join(old, f)
            try:
                os.replace(src, dst)
            except OSError:
                shutil.move(src, dst)
            moved += 1
        except OSError:
            continue
    try:
        left = os.listdir(old)
        if left == [".gitignore"] and open(os.path.join(old, ".gitignore")).read().strip() == "*":
            os.remove(os.path.join(old, ".gitignore"))
            left = []
        if not left:
            os.rmdir(old)
    except OSError:
        pass
    return moved


def rules_gitignored(rr):
    """'' when this repo's rules.md can travel through git; otherwise the
    .gitignore pattern that excludes it. An explicit `rules.md` pattern is a
    deliberate choice and also returns '' (this harness repo keeps its own
    rules.md machine-local that way)."""
    if rr.get("scope") != "repo" or not rr.get("toplevel"):
        return ""
    out = _git(rr["toplevel"], "check-ignore", "-v", "--", ".claude/rules.md")
    if not out:
        return ""  # not ignored (or already tracked)
    pat = out.split("\t", 1)[0].split(":", 2)[-1].strip()  # <source>:<line>:<pattern>\t<path>
    if "rules.md" in pat:
        return ""
    return pat or out


def terminal_counter_path(rr):
    return os.path.join(QUEUE_DIR, f".terminal-{store_key(rr)}")


def ledger_status_counts():
    """{status: count} over the extraction ledger (probe caches excluded)."""
    import json
    counts = {}
    try:
        names = os.listdir(QUEUE_DIR)
    except OSError:
        return counts
    for f in names:
        if not f.endswith(".json") or f.startswith("caps-"):
            continue
        try:
            with open(os.path.join(QUEUE_DIR, f)) as fh:
                st = json.load(fh).get("status")
        except Exception:
            continue
        counts[st] = counts.get(st, 0) + 1
    return counts
