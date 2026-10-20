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

- skills — `/implement`, `/ticket`, `/scope-creation`, `/orchestrate`, `/eli5`
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

Then open a Claude Code session and just work. Nothing runs during your
session. When it ends, a detached extractor (one headless `claude -p` call,
pinned Haiku, no tools, `--safe-mode` so it loads none of your global
context — about $0.002 per session) distills the session's non-obvious
learnings into `.claude/rules-pending/`; the next session start reviews those
candidates with you, merges the keepers into `.claude/rules.md` (the project's
accumulated rules — commit it with your normal commits), and every session
starts with that file injected. Folders that are not git repos get the same
loop with a machine-local store under `~/.claude/learn-rules/`.

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
| Rules loop | end one session; a fragment appears in `.claude/rules-pending/`, the next session reviews it into `.claude/rules.md` and injects it from then on |
| Loop health | `~/.claude/skills/biscuit-harness/setup --check` (registered hooks, binary, flag probe) and `bin/learn-test` (offline scenario tests; `--live` adds one real extraction) |
| Type hook | edit a `.ts` file in a repo with a tsconfig — errors feed back automatically |
| Impact | `~/.claude/skills/biscuit-harness/bin/harness-stats` |

Updates are automatic from here: every session start pulls the latest
(1h throttle) and re-links anything new. No further action ever.

## Scope — what this provides, and what it never will

Provided (the engine):

- **Distribution** — clone once + `setup`; from then on `git push` here deploys
  to every machine (auto-update with staleness warnings, idempotent setup)
- **Memory loop** — per-project `.claude/rules.md`: one cheap background
  extraction at session end (never during it), human-supervised merge at next
  session start, injected every session within Claude Code's hook-output cap,
  committed with the project; machine-local stores for non-git folders
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
  learn-extract.sh       SessionEnd + background runner — the WRITE path of the
                         rules loop. The hook only claims a per-session job in
                         the ledger (~/.claude/learn-queue/<session>.json) and
                         spawns a detached runner (no git, no parsing: the
                         SessionEnd budget is 1.5 s). The runner waits for the
                         transcript to settle, slices a bounded digest in Python
                         (prompts, replies, tool one-liners, failed results;
                         secrets scrubbed; no raw tool output), and makes ONE
                         `claude -p --safe-mode --tools "" --model claude-haiku-5-5`
                         call (~3K tokens of fixed context instead of ~136K; the
                         working flag set is probed once per binary version and
                         cached). Candidates land in <store>/rules-pending/
                         (self-gitignored); rules.md is never written directly.
                         Also the catch-up sweep (crash guarantee, one at a time,
                         bounded), delta re-extraction of sessions resumed after
                         extraction, usage-limit backoff (no retry burned),
                         terminal-error pausing (3 strikes; `setup` re-arms),
                         and `--probe` / `--dry-run <transcript>`.
  learn-extract-prompt.md  the extractor's system prompt: Rules-vs-Episodes
                         criteria, user-stated-only (no rules derived from web
                         or tool content), confidence tags (low is dropped),
                         strict output contract
  learn-on-stop.sh       RETIRED (v4): exit-0 stub kept one release so old
                         settings entries stay harmless; `setup` removes them
  learn-recall.sh        SessionStart — the READ path plus the review loop,
                         per source: fork → nothing; compact → rules + index
                         only; startup/resume/clear → (1) claims pending
                         fragments (two sessions never review the same file)
                         and instructs the session to review them after the
                         user's first request; (2) warns about permanently
                         failed or paused extraction; (3) on startup only,
                         fires the catch-up sweep; (4) injects # Rules in full
                         plus the # Episodes heading index, assembled in code
                         under 9,500 bytes (Claude Code replaces hook output
                         over 10,000 chars with a 2 KB preview): the index is
                         always whole, rules are cut at a bullet boundary with
                         an explicit "Read the file" pointer; (5) asks for
                         consolidation at ≥24 bullets or >7,000 bytes.
  metrics-on-end.sh      SessionEnd: parses the session transcript into one metrics
                         line (duration, prompts, API calls, tool calls/errors,
                         tokens deduplicated by message id incl. cache writes,
                         first-turn prompt size, bytes of user-level rules Claude
                         Code loaded, cost) tagged with the harness version.
                         Human sessions only — headless runs are skipped
  _digest.py             shared transcript reader: bounded digest for the
                         extractor, deduplicated session stats, secret scrub
  _project_name.py       project name + rules_root(cwd): where a folder's
                         rules.md / rules-pending/ live (repo or local store)
bin/
  team-init              plants the required|optional marker in a project repo
  harness-stats          impact report over the local metrics (see Metrics below)
  learn-test             scenario tests for the learn loop under a throwaway
                         HOME (crash/retry, usage-limit backoff, terminal pause,
                         duplicate claims, resume delta, sweep lock, Korean
                         40 KB recall budget, review claiming, metrics dedupe);
                         `--live` adds one real extraction (~$0.002)
  migrate-legacy-rules   moves pre-v4 memory files out of ~/.claude/rules/
                         (which Claude Code loads into EVERY project) into
                         per-folder stores; dry run by default, `--apply` moves
```

## Rules (project-shared, committed)

Rules live **in the project repo** at `.claude/rules.md` and are meant to be
committed: session start injects them, sessions add new ones through the
capture loop below, and anyone who clones the project inherits everything
learned so far. The file has two tiers: `# Rules` (standing conventions and
decision rationale — injected in full) and `# Episodes` (incident records —
injected as a heading index). Write only project-building knowledge there —
never secrets or personal data. Metrics are the opposite: local-only, never
committed (a per-session jsonl in git would be pure merge-conflict noise).

### Where a folder's rules live

| Working directory | rules.md | review queue (rules-pending/) |
|---|---|---|
| git repo (any worktree) | `<worktree>/.claude/rules.md` — committed, shared through git | `<main worktree>/.claude/rules-pending/` — one queue for all worktrees of the repo |
| not a git repo | `~/.claude/learn-rules/<folder>-<hash8>/rules.md` — machine-local | `…/rules-pending/` in the same store |

Never `~/.claude/rules/`: Claude Code loads every file in that directory into
**every** project on the machine. Pre-v4 harness versions wrote there; run
`bin/migrate-legacy-rules` once to move such files into per-folder stores
(`setup` prints a notice while any remain).

Worktrees share rules.md the way they share any committed file — through
commits, merges and rebases, not live; only the review queue is shared live.
Different projects never see each other's rules.

**Native opt-in for large rule sets.** The hook injection is capped at 9,500
bytes. A folder with more standing rules than that can move its `# Rules` tier
into `<folder>/.claude/rules/biscuit-rules.md`, which Claude Code loads itself
(no cap, same priority as CLAUDE.md, also visible to subagents); the hook then
injects only the episode index and the review ceremony, and the review merges
new rules into that file. Episodes stay in `rules.md`.

### How rules get captured (the background learn loop)

```
session ends ─SessionEnd (1.5 s)─▶ ledger claim ─▶ detached runner
     │                                   settle → Python digest → ONE call:
     │                                   claude -p --safe-mode --tools "" (haiku)
     │                                        │ proposes candidates (~$0.002)
next session ─SessionStart─▶ catch-up sweep   ▼
     │        (startup only; crash guarantee)  <store>/rules-pending/<session>.md
     └─▶ review injected: claim fragments, merge keepers into rules.md,
         delete fragments, report merged/discarded on one review card
```

Properties, in order of importance:

- **Nothing runs during a session.** No per-turn hook exists any more (the v3
  Stop hook blocked the turn to make the model write notes; retired in v4).
- **One cheap call per session end.** The extractor never loads your global
  context, hooks, skills or MCP servers (`--safe-mode`), has no tools, uses a
  pinned model id, a dollar cap and an effort of `low`; its real cost and token
  usage are recorded in the ledger and metrics.
- **SessionEnd is only the fast path — the sweep is the guarantee.** Kill the
  terminal mid-session and the next startup in that folder still captures it
  (oldest first, bounded, one sweep at a time, within Claude Code's 30-day
  transcript retention; a folder you never reopen is not swept).
- **Resumed sessions are re-extracted as a delta** (only the new transcript
  lines), so already-reviewed items are not resubmitted.
- **Failures are classified.** Usage limits and network errors defer the job
  with an hour's backoff and burn no retry; configuration errors are terminal
  and pause the folder after three in a row (`setup` re-arms); only runner
  crashes count toward the two retries. Permanent failures and pauses are
  surfaced at session start, never invisible.
- **The extractor can only propose.** `rules.md` is written exclusively during
  the next session's human-visible review. `rules-pending/` gitignores itself,
  so unreviewed machine output can never be committed. Credential-shaped
  strings are redacted before the model sees the digest and again before a
  fragment is written; candidates phrased as instructions to an agent are
  always escalated, never auto-merged.
- **Review feels like code review, not maintenance.** Your first request is
  handled first; the whole ceremony is one numbered card at the end of that
  reply (`drop 2` reverts a merge). Fragments are claimed by the reviewing
  session, so two sessions never review the same file. Non-git stores keep a
  `.bak` of rules.md from before each review.
- **Human sessions only.** The harness's own headless runs and your `claude -p`
  scripts are neither extracted nor counted in metrics
  (`BH_LEARN_INCLUDE_HEADLESS=1` to include them; `BH_LEARN_DISABLE=1` or
  `{"learn": false}` in `.claude/harness.json` to switch the loop off).

Division of labor, no overlap: `CLAUDE.md` is the human-curated static guide
(what the project is, how to run it); `.claude/rules.md` is the
model-accumulated dynamic knowledge. Don't `@import` rules.md from CLAUDE.md —
the hook already injects it, an import would double it. `AGENTS.md` (the
cross-tool instructions standard) is only needed if the team uses non-Claude
tools; symlink it to CLAUDE.md in that case.

### Testing and measuring the loop

- `bin/learn-test` runs the failure scenarios offline under a throwaway HOME
  (crash → retry → exhausted → warning; usage limit → deferred + backoff;
  bad flag → terminal → pause → `setup` re-arm; duplicate claims; resume
  delta; sweep lock and crash pickup; a 40 KB Korean store under the 9,500-byte
  budget; review claiming across concurrent sessions; metrics dedupe; secret
  scrub). `--live` adds one real extraction of a synthetic transcript with a
  planted rule. Run it in the terminal after changing a hook; the deterministic
  part can run in CI, the live part needs a logged-in `claude`.
- `setup --check` prints the registered hooks, clone state, the binary the
  extractor resolved (`CLAUDE_CODE_EXECPATH`, then the newest installed
  version, then PATH) and the cached flag probe with its context size.
- `bin/harness-stats --since 30` is the long-term view: extractor yield and
  cost per run, and per session the first-turn prompt size and the bytes of
  user-level rules Claude Code loaded (`rulesKB` — the global-rules tax, 0
  after migration). Inside Claude Code, `/context` lists what was loaded and
  `/usage` shows the prompt-cache footprint.

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
