# Shared helpers for the learning loop hooks.
# Used by learn-on-stop.sh (write path) and learn-recall.sh (read path) —
# both MUST agree so a project always maps to the same learnings file.
#
# project_name: most stable first — origin remote repo name (same across
# machines and folder renames) → git toplevel folder name → cwd basename.
# git_toplevel: repo root for the in-repo learnings file, "" outside a repo.
import os
import subprocess


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
