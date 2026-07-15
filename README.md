# biscuit-harness

A central, git-distributed Claude Code harness: skills, agents, hooks, and
guardrails in one repo. Install once per machine; after that, every `git push`
to this repo is a deployment — teammates pick up the latest automatically at
session start.

The point: whatever project you open — especially small ones — the builder
starts from a working baseline instead of from scratch. Download it and go;
customize in your own space (see Scope below).

## Getting started — zero to a working baseline

### Step 1 — install on your machine (once, ~1 minute)

Paste this into any Claude Code session:

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

That is the whole install. It wires up, machine-wide:

- skills — `/implement`, `/ticket`, `/scope-creation`, `/orchestrate`
- agents — researcher / spec / builder / verifier / reviewer
- hooks — rules loop, type-check feedback, metrics, auto-update
- baseline deny rules — force-push, `rm -rf /` and friends (added once;
  remove any and it stays removed)

`setup` is idempotent — re-run it any time. Never edit files under
`~/.claude/` directly; they are symlinks into the clone.

### Step 2 — use it in your repo (new or existing)

**There is nothing to install per project** — the harness is machine-global.

```sh
cd your-project
git init          # only if the directory is brand new — the rules loop needs a repo
```

Then open a Claude Code session and just work. At the first session's end the
model writes `.claude/rules.md` (the project's accumulated rules — commit it
with your normal commits); every later session starts with it injected.

Optional, per repo:

- **Team marker** — nag (or block) teammates whose machine lacks the harness:

  ```sh
  ~/.claude/skills/biscuit-harness/bin/team-init required   # or: optional
  git add .claude/ && git commit -m "require biscuit-harness for AI-assisted work"
  ```

  The marker is one SessionStart hook committed to the project's
  `.claude/settings.json` — no harness code is vendored into the project.
  `required` = Claude stops and asks the user to install first;
  `optional` = a one-line suggestion at session start.

- **Inline-type guardrail** (TS monorepo with apps/ + packages/): create
  `.claude/harness.json` with `{"check-type-dup": true}`

- **`CLAUDE.md`** — human-curated project facts (how to run, conventions);
  the built-in `/init` writes a starter

### Step 3 — check it's working

| Check | How |
|---|---|
| Installed | `ls ~/.claude/skills/biscuit-harness` |
| Skills live | type `/orchestrate` (or `/implement`) in a session — it's offered |
| Rules loop | end one session; `.claude/rules.md` appears, next session injects it |
| Type hook | edit a `.ts` file in a repo with a tsconfig — errors feed back automatically |
| Impact | `~/.claude/skills/biscuit-harness/bin/harness-stats` |

Updates are automatic from here: every session start pulls the latest
(1h throttle) and re-links anything new. No further action ever.

## Scope — what this provides, and what it never will

Provided (the engine):

- **Distribution** — clone once + `setup`; from then on `git push` here deploys
  to every machine (auto-update with staleness warnings, idempotent setup)
- **Memory loop** — per-project `.claude/rules.md`, auto-captured at session
  end, auto-injected at session start, committed with the project
- **Instrumentation** — local metrics + `harness-stats` to measure whether the
  harness actually helps, per version
- **Baseline guardrails** — deny rules; hooks that work when the stack matches
  and stay inert when it doesn't (opt-in for team-specific conventions)
- **Generic workflows** — scope→ticket→implement, plus /orchestrate
  (research→spec→approve→build→verify→review) with five standard agents
- **Team devices** — team-init marker, `.claude/harness.json` opt-ins

NOT provided (userland — yours to own):

- Stack scaffolding or framework boilerplate
- Team- or project-specific conventions as defaults (opt-in only)
- Hosting for your custom skills/hooks — the harness gives you the extension
  contract below, not a home for customizations

**The contract: the harness only ever touches what it created.** Your hooks,
skills, agents, and settings entries are never removed, overwritten, or
re-added. Guardrail deny rules are added once at first install; delete one and
it stays deleted.

## Extending

| You want | Put it | Notes |
|---|---|---|
| Personal skill | `~/.claude/skills/<name>/` | sibling of the harness dir; never touched |
| Personal agent | `~/.claude/agents/<name>.md` | setup only symlinks its own files |
| Personal hook | `~/.claude/settings.json` | setup only appends its own entries |
| Project skill | `<repo>/.claude/skills/<name>/` | committed, project-scoped |
| Project hook/permissions | `<repo>/.claude/settings.json` | committed |
| Harness feature opt-in | `<repo>/.claude/harness.json` | e.g. `{"check-type-dup": true}` |
| Team-wide custom set | **fork this repo**, add to `skills/` etc. | your fork inherits the whole deployment engine: push = team deploy |

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
At most once per hour it fetches and fast-forwards, then re-runs `setup` so
new skills/hooks link automatically. Offline and up-to-date are silent; being
behind without a possible fast-forward prints a one-line warning. Because the
hook script itself lives in this repo, improvements to the update logic also
ship via `git pull`.

**Never edit harness files under `~/.claude/` directly** — the symlinks point
back into this repo. Change things here and push.

## What's inside

```
setup                    installer (symlinks + settings.json registration)
skills/                  custom skills (SKILL.md format) — see skills/README.md
agents/                  agent definitions — see agents/README.md
hooks/
  auto-update.sh         SessionStart: git fetch + ff merge, 1h throttle. Silent
                         when offline/up-to-date; warns in one line when the clone
                         is behind but cannot fast-forward (staleness is never
                         invisible). Re-runs ./setup after a successful update so
                         new skills/hooks link automatically.
  check-types.sh         PostToolUse: tsc --noEmit on the edited file's package
  check-type-dup.sh      PostToolUse: flags inline domain types in apps/ —
                         OPT-IN per project via .claude/harness.json
                         {"check-type-dup": true}; inert everywhere else
  learn-on-stop.sh       Stop: before the session ends, has the model record
                         non-obvious rules/episodes to <repo>/.claude/rules.md
                         (COMMITTED — the project's shared memory), classified as
                         Rules (generally applicable) or Episodes (incident
                         records). Outside a git repo: falls back to the
                         machine-local ~/.claude/rules/<project>.md
  learn-recall.sh        SessionStart: injects Rules in full (standing knowledge,
                         no matching needed) + an index of Episode headings with an
                         instruction to Read the matching entry before related work.
                         Reads the repo file; nudges migration if only a legacy
                         machine-local file exists
  metrics-on-end.sh      SessionEnd: parses the session transcript into one metrics
                         line (duration, messages, tool calls/errors, tokens, harness
                         skill uses) tagged with the harness version
bin/
  team-init              plants the required|optional marker in a project repo
  harness-stats          impact report over the local metrics (see Metrics below)
```

## Rules (project-shared, committed)

Rules live **in the project repo** at `.claude/rules.md` and are meant to be
committed: session start injects them, session end appends new ones, and
anyone who clones the project inherits everything learned so far. The file has
two tiers: `# Rules` (standing conventions and decision rationale — injected
in full) and `# Episodes` (incident records — injected as a heading index).
Write only project-building knowledge there — never secrets or personal data.
Metrics are the opposite: local-only, never committed (a per-session jsonl in
git would be pure merge-conflict noise).

Division of labor, no overlap: `CLAUDE.md` is the human-curated static guide
(what the project is, how to run it); `.claude/rules.md` is the
model-accumulated dynamic knowledge. Don't `@import` rules.md from CLAUDE.md —
the hook already injects it, an import would double it. `AGENTS.md` (the
cross-tool instructions standard) is only needed if the team uses non-Claude
tools; symlink it to CLAUDE.md in that case.

## Metrics (personal, local — never transmitted)

Hooks log what they catch to `~/.claude/metrics/` on your machine only:
`hook-events.jsonl` (one line per meaningful hook firing — e.g. type errors
caught pre-build) and `sessions.jsonl` (one line per session, tagged with the
harness version). Files rotate at 5MB. Nothing is sent anywhere; each person
owns their own data.

```sh
~/.claude/skills/biscuit-harness/bin/harness-stats            # full report
~/.claude/skills/biscuit-harness/bin/harness-stats --since 30 # last 30 days
```

The report shows attribution ("what did the harness catch") and the trend by
version — `friction` (tool errors / tool calls) drifting down across versions
means the harness is working.

`setup` also adds guardrail deny rules to `~/.claude/settings.json`
(`git push --force`, `rm -rf /`, `rm -rf ~`). Remove them from the `deny`
list if they get in your way.

## Updating (maintainer)

Commit and push to this repo. That's the whole deployment — every machine
pulls at next session start.
