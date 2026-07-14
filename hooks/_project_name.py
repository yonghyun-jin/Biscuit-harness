# Shared helper: resolve a stable project name for learnings files.
# Used by learn-on-stop.sh (write path) and learn-recall.sh (read path) —
# both MUST agree so a project always maps to the same learnings file.
#
# Most stable first: origin remote repo name (same across machines and
# folder renames) → git toplevel folder name → cwd basename.
import os
import subprocess


def project_name(cwd):
    def git(*args):
        try:
            r = subprocess.run(
                ["git", "-C", cwd, *args],
                capture_output=True, text=True, timeout=5,
            )
            return r.stdout.strip() if r.returncode == 0 else ""
        except Exception:
            return ""

    name = ""
    origin = git("remote", "get-url", "origin")
    if origin:
        name = os.path.basename(origin.rstrip("/"))
        if name.endswith(".git"):
            name = name[:-4]
    if not name:
        top = git("rev-parse", "--show-toplevel")
        name = os.path.basename(top) if top else ""
    return name or os.path.basename(cwd.rstrip("/")) or "misc"
