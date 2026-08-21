# Rules evaluation harness — design

**Status:** design proposal, nothing implemented.
**Retirement condition:** delete this file when P2 ships; the decisions that
survive move to `.claude/rules.md`, the roadmap items to `TODO.md`. Per the
single-source-of-truth rule, design docs are deleted rather than archived —
git history is the archive. A stale design doc that outlives its decisions is
how `HARNESS-DESIGN.md` ended up asserting reversed conclusions.

---

## 1. The problem

Rule candidates arrive in `.claude/rules-pending/`, and the next session's
review card merges or discards each one. That decision is currently made on
judgment alone: nobody has ever measured whether a merged rule changes what
the model does.

Three consequences:

- **Merge/discard is unfalsifiable.** A rule that does nothing and a rule that
  helps look identical at review time.
- **The ceremony runs every session** whether or not there is anything worth
  deciding, which is exactly the "loop that reads as a chore gets ignored and
  rots" failure mode the ceremony rule warns about.
- **`rules.md` can only grow.** Nothing can count as evidence against a rule,
  so nothing is ever removed except under consolidation pressure at 24 bullets.

`harness-stats` cannot close this gap. It is *observational*: it reports that
friction was 3.7% during months when rules existed. It cannot attribute that
to the rules. The missing instrument is a *controlled* one — same task, run
with and without the rule.

This is in scope. The README already lists instrumentation as part of the
engine ("local metrics + `harness-stats` to measure whether the harness
actually helps"). This is the same category by a different method, not a new
category needing a scope exception.

## 2. Evidence from the current metrics (measured 2026-08-21)

264 session records, 2,179 hook events. What the raw data shows that the
`harness-stats` report does not:

| Finding | Detail |
|---|---|
| **Metrics are contaminated by the harness itself** | 144 of 264 session rows (55%) are the learn-extractor's own headless runs, labelled project `T` — the basename of the macOS tempdir it runs from. `BH_LEARN_EXTRACT` keeps those runs out of the *learning* loop but nothing keeps them out of `metrics-on-end.sh`. |
| **Reported friction is inflated 2.4×** | 9.0% reported vs **3.7% for human sessions**. July 3.7% → August 3.6%: flat. |
| **The extractor fails ~7 tool calls per run** | 990 tool errors / 1,600 tool calls = **61.9%**. Three faces, one cause: transcripts exceed the Read size cap (2.7MB / 2.1M tokens); `wc`/`head`/`tail` on `~/.claude/projects/` are blocked because the tempdir is the sandbox root; multi-operation Bash commands need approval that a headless `-p` run can never give. |
| **The version trend has never had two rows** | All 264 sessions stamp `c0a0984`. The `harness-stats` trend-by-version block, the whole point of the bottom table, has never produced a trend. |
| **`avg_dur` is meaningless** | Mean 322m over a distribution with median 94m and max 246h. Report medians. |
| **`check-types` is unambiguously earning its keep** | 1,760 runs, 884 real type errors caught pre-build. `check-type-dup` has flagged 0 — no project has set the opt-in. |
| **Harness skills are ~unused** | `harness_skill_uses` = 1 across 264 sessions. Either the four skills are dead weight or the counter misses slash-command invocations that don't route through the `Skill` tool. Unresolved — check before concluding. |

Two of these directly shape the design below: the extractor's error rate
(every rule this harness would grade is produced by that extractor, from a
truncated transcript) and the metrics contamination (proof that
self-instrumentation leaks into its own measurements by default, not by
accident).

## 3. Core idea: the rules.md commit *is* the experiment

When a rule is finalised and merged, the commit that adds it defines both
sides of the comparison for free:

- **Arm A** = `git show X:.claude/rules.md` — rule present
- **Arm B** = `git show X~1:.claude/rules.md` — rule absent

No synthetic file construction, no "remove bullet N" logic. Because a rules
commit usually adds one or two bullets, the contrast is naturally narrow —
which is what makes the result attributable to a specific rule rather than to
"memory in general".

Evaluating *after* merge rather than before is deliberate: a losing rule is
removed by a revert commit, and that revert is itself a durable record that
the rule was tested and failed.

### Vocabulary

| Term | Meaning here |
|---|---|
| **arm** | one side of the comparison (from clinical trials: drug arm / placebo arm) |
| **ablation** | removing one component to see whether it mattered — the standard form of this experiment in ML papers |
| **treatment / control** | Arm A / Arm B |
| **falsifiable** | there exists an observable outcome that would show the rule is wrong. *"Pass the payload via `BH_HOOK_INPUT`"* is falsifiable; *"write maintainable hooks"* is not — and unfalsifiable rules can never be discarded, only accumulated |
| **assertion** | a one-line mechanical check that a run obeyed the rule (e.g. `grep -q 'BH_HOOK_INPUT=$(cat)'`) |
| **self-fulfilling** | scoring that can only ever confirm the rule — see §6.1 |

## 4. Eval cases

A case is small enough to commit, because it stores SHAs rather than code:

```json
{
  "id": "2026-07-15-heredoc-stdin",
  "base": "<sha the task starts from>",
  "plan": "cases/<id>/plan.md",
  "reference": "<sha of the known-good diff>",
  "rule_under_test": "<slug>",
  "assertions": [
    { "cmd": "grep -q 'BH_HOOK_INPUT=\\$(cat)' hooks/new-hook.sh", "expect": 0 },
    { "cmd": "echo '{\"cwd\":\"/tmp\"}' | timeout 10 hooks/new-hook.sh", "expect": 0 }
  ]
}
```

Cases live at `<project>/.claude/eval/cases/*.json` and are committed with the
project, like rules. Run results live at `~/.claude/eval/runs/*.jsonl`,
machine-local and never committed, like metrics. The existing split holds.

**Case selection matters more than case volume.** The case for a rule should
be the session that *produced* it — the extractor already records the session
id in the fragment header. A rule tested on a task where it cannot apply
returns a guaranteed null result and burns tokens.

## 5. Scoring ladder

Cheapest first; most cases should resolve before reaching a judge.

| Tier | Signal | Cost |
|---|---|---|
| T0 gate | builds / tests / typecheck pass; stayed inside the declared change budget | free |
| T1 similarity | touched-file precision/recall vs the reference; normalised line overlap | free |
| T2 process | turns, tool errors, tokens, wall clock — **already logged by `metrics-on-end.sh`** | free |
| T3 assertion | did the run actually do what the rule mandates? | free, hand-written once |
| T4 blind judge | model compares both diffs to the reference, **arm-anonymised, order-randomised** | paid |

**T3 is the highest-value artifact here**, independent of whether the runner
ever ships. It separates two failures that are otherwise indistinguishable —
"Arm A lost because the rule was ignored" vs "Arm A lost because the rule is
bad advice" — and it doubles as a quality filter at merge time: a candidate
nobody can write an assertion for is prose, and prose belongs in Episodes or
nowhere.

## 6. Validity traps

### 6.1 Self-fulfilling reference diffs

If the reference answer came from a session that already had the rule loaded,
grading by similarity measures only *"code written with rule R resembles code
written with rule R"*. Arm A wins by construction — even if the rule is flatly
wrong. The test can confirm but never refute.

Two mitigations:

1. **Use an answer key the rule did not write** — a reference commit from
   before the rule existed, or a human-authored one.
2. **Weight signals that hold regardless of who is right.** Don't ask "does it
   resemble the reference"; ask "feed a test payload to the hook each arm
   produced — does it work?" Arm B's version hanging forever on stdin is a
   real, observable failure. Similarity is a fallback for when no such test
   exists; it must never be the primary signal.

### 6.2 The plan leaking the rule

The plan `.md` must be byte-identical across arms *and* must not restate the
rule. A plan that says "remember to pass the payload via `BH_HOOK_INPUT`" makes
both arms succeed and the rule look worthless. Automated validity check: grep
the plan for the rule's own content; if it leaks, the case is invalid.

### 6.3 Noise

Two runs of the same prompt differ enormously. n=1 per arm is a coin flip
dressed as a measurement. Budget **3–5 repeats per arm per case** and compare
distributions. This is the dominant cost driver and the reason this cannot run
per session.

Corollary for reporting: with n=5, "improved 12%" is not a result. Report
**wins / losses / ties** across cases and repeats.

### 6.4 The harness measuring itself

Eval runs must be excluded from the learn loop *and* from metrics at write
time, not filtered at read time. This is not hypothetical — §2 shows the
extractor already doing exactly this and inflating the headline metric 2.4×.
Reuse the existing marker pattern (`BH_LEARN_EXTRACT` → `BH_EVAL`).

### 6.5 Shrinking effect sizes

The stronger the base model, the more often it does the right thing without
the rule, and the smaller every measured effect becomes. Evaluate on the model
actually in use, and read a shrinking effect as partly good news rather than
as instrument failure.

## 7. Decision policy

Stated up front so results are actionable:

| Result | Action |
|---|---|
| Arm A loses | **discard** — the rule is actively harmful |
| Arm A wins | merge; keep the assertion as a permanent regression test |
| No effect, assertion-verifiable | merge — cheap, low risk |
| No effect, unverifiable | **discard** |

The last row is the ratchet. `rules.md` is not free: it costs context budget
and pushes toward the 24→14 consolidation trigger. "No measurable effect"
defaulting to discard is what keeps the file load-bearing.

## 8. Trigger architecture

The harness is machine-global (`~/.claude/skills/biscuit-harness`); what lives
per repo is only data (`rules.md`, `harness.json`, eval cases). So detection is
per-repo and execution is machine-global:

```
per repo, at session start (free, no new machinery)
  learn-recall already reads .claude/rules.md
  → also record that file's git blob SHA
  → SHA changed since last seen?  enqueue a job in ~/.claude/eval-queue/
                                  {repo path, commit X, rules diff}

machine-global, scheduled (cron/launchd)
  bin/harness-eval drains the queue:
    git worktree at X and X~1 → run both arms, N repeats → score → record
  results → ~/.claude/eval/runs/*.jsonl   (machine-local, like metrics)

next session in that repo
  review card shows the verdict, with evidence
```

Three properties:

- **This is the learn loop's shape, not a new concept.** Detect in-session,
  execute detached, ledger at `~/.claude/learn-queue/` for at-least-once
  delivery. The eval queue is the same mechanism with a different payload.
- **One runner covers every repo on the machine.** It needs no advance
  registry — it evaluates whatever repos were opened and committed to.
- **GitHub Actions is the wrong default.** It would need an API key in every
  project repo, and most are private with production-connected env files.
  Actions make sense later, only for this repo evaluating itself.

### Cadence

- **Event-driven** — `rules.md` changed → evaluate that change. This is the
  trigger that matters.
- **Periodic sweep** — monthly, or after a batch merge: re-check that older
  rules still earn their place. Weekly is likely over-engineered at ~16 rules
  and 120 real sessions; a timer nobody reads is the chore failure again.
- **Never per session.** Session start only enqueues; the card shrinks to
  "3 candidates queued".

## 9. Phasing

- **P0 — plumbing.** `bin/harness-eval` + case harvester + T0–T2 scoring, run
  against this repo's own git history. Deliverable: real cost-per-run numbers
  instead of estimates.
- **P1 — signal.** Repeats, blind judge, report.
- **P2 — loop.** Wire to the pending queue; the review card becomes
  evidence-backed; scheduled drain.
- **P3 — regression.** Periodic sweep over merged rules;
  `harness-stats --eval`.

**Prerequisite before P0:** fix the extractor (§2). Every rule this machinery
would grade is produced by a process currently failing ~7 tool calls per run
and reading a truncated head of the transcript. The fix is already on the
roadmap — pre-slice a bounded transcript tail into a file *inside* the
extractor's working directory, which removes the size cap, the sandbox block,
and the approval prompt at once.

## 10. Prior art

The design is an **ablation study** — standard experimental form in ML papers:
remove one component, hold everything else fixed, measure the delta. The
periodic sweep is **benchmark regression testing**, routine in compilers,
databases, and ML org nightly eval suites.

It also shares a skeleton with automated-research loops (propose → run a
controlled experiment → score → keep or discard, no human in the inner loop).
The difference that matters: in a training speedrun the metric is a cheap
scalar with small variance — one number, minutes, reproducible. Here a single
sample is an entire agent session, the metric is a judged code diff, variance
is enormous, and the ground truth was itself produced by an agent. Same
skeleton, orders of magnitude worse signal-to-noise per sample.

The compensations are the ones above: rule-targeted cases, narrow arms,
repeats, and deterministic assertions wherever a judge can be avoided. This
instrument detects **large effects and harmful rules**. It will not adjudicate
subtle ones, and presenting it as though it could is how noise gets merged
with a scientific-looking number attached.

## 11. Non-goals

- Not a general agent benchmark. It compares two rules files on one task.
- Not a CI gate. It never blocks a commit or a session.
- Not shared or transmitted. Results are machine-local; cross-machine
  aggregation stays the opt-in `harness-stats --export` item.

## 12. Open decisions

1. **First target repo** — this harness (cheap, self-contained, history I can
   read) or a real project like contract-autofill (realistic, but private and
   production-connected)?
2. **Run budget** — how many runs per scheduled drain? Better measured in P0
   than estimated now.
3. **Whole-file arm** — keep "all rules vs none" as a separate occasional
   health check, or drop it as unactionable?
