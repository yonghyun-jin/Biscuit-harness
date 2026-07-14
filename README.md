# biscuit-harness

A central, git-distributed Claude Code harness: skills, agents, hooks, and
guardrails in one repo. Install once per machine; after that, every `git push`
to this repo is a deployment — teammates pick up the latest automatically at
session start.

## Install (personal)

Paste this into Claude Code:

```
Install biscuit-harness: run
git clone --single-branch --depth 1 https://github.com/yonghyun-jin/Biscuit-harness.git ~/.claude/skills/biscuit-harness && ~/.claude/skills/biscuit-harness/setup
then add a "biscuit-harness" section to my global CLAUDE.md listing the available skills.
```

Or by hand:

```sh
git clone --single-branch --depth 1 \
  https://github.com/yonghyun-jin/Biscuit-harness.git ~/.claude/skills/biscuit-harness
~/.claude/skills/biscuit-harness/setup
```

`setup` is idempotent — re-run it any time (e.g. after new agents/skills are added).

## Team mode

Inside a project repo, plant a marker that nags (or blocks) anyone whose
machine doesn't have the harness:

```sh
~/.claude/skills/biscuit-harness/setup --team
~/.claude/skills/biscuit-harness/bin/team-init required   # or: optional
git add .claude/ && git commit -m "require biscuit-harness for AI-assisted work"
```

The marker is a single SessionStart hook committed to the project's
`.claude/settings.json`. No harness code is vendored into the project.

- `required` — Claude is instructed to stop and have the user install first
- `optional` — a one-line install suggestion at session start

## How it works

```
git clone → ~/.claude/skills/biscuit-harness    install location = scan location
./setup   → agents & skills symlinked, hooks registered by path
git pull  → everything updates in place (no copies, no drift)
```

| Piece  | Where Claude Code looks        | How it's wired                          |
|--------|--------------------------------|-----------------------------------------|
| Skills | `~/.claude/skills/<name>/`     | symlink → `skills/<name>/` in this repo |
| Agents | `~/.claude/agents/*.md`        | symlink → `agents/*.md` in this repo    |
| Hooks  | `~/.claude/settings.json`      | registered by absolute path into this repo |

Auto-update: `setup` registers `hooks/auto-update.sh` as a SessionStart hook.
It runs `git pull --ff-only` at most once per hour and fails silently when
offline. Because the hook script itself lives in this repo, improvements to
the update logic also ship via `git pull`.

**Never edit harness files under `~/.claude/` directly** — the symlinks point
back into this repo. Change things here and push.

## What's inside

```
setup                    installer (symlinks + settings.json registration)
skills/                  custom skills (SKILL.md format) — see skills/README.md
agents/                  agent definitions — see agents/README.md
hooks/
  auto-update.sh         SessionStart: git pull, 1h throttle, silent fail
  check-types.sh         PostToolUse: tsc --noEmit on the edited file's package
  check-type-dup.sh      PostToolUse: flags inline domain types in apps/ when the
                         monorepo has packages/ (reuse packages/shared instead)
  learn-on-stop.sh       Stop: before the session ends, has the model record
                         non-obvious learnings to ~/.claude/learnings/<project>.md,
                         classified as Rules (generally applicable) or Episodes
                         (incident records) — personal, machine-local, never shared
  learn-recall.sh        SessionStart: injects Rules in full (standing knowledge,
                         no matching needed) + an index of Episode headings with an
                         instruction to Read the matching entry before related work
bin/
  team-init              plants the required|optional marker in a project repo
```

`setup` also adds guardrail deny rules to `~/.claude/settings.json`
(`git push --force`, `rm -rf /`, `rm -rf ~`). Remove them from the `deny`
list if they get in your way.

## Updating (maintainer)

Commit and push to this repo. That's the whole deployment — every machine
pulls at next session start.
