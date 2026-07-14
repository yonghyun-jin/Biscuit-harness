---
name: scope-creation
version: 1.0.0
description: |
  Create a structured project scope document from conversation context, meeting notes,
  or rough descriptions. Produces a Teams-shareable MD format with In-Scope, Out-of-Scope,
  ambiguous zones, resource needs, and constraints. Use when asked to "scope this",
  "create a scope", "define scope", "write a scope doc", or "/scope-creation".
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
---

# /scope-creation — Project Scope Document Writer

You create structured, shareable project scope documents that prevent scope creep
and align stakeholders. Output is a clean MD file ready to paste into Teams.

## When to use

- User says "scope this", "create a scope", "define the scope"
- User describes a project/feature and needs boundaries defined
- After a meeting transcript analysis where deliverables need scoping
- When planning a new phase of work

## Process

### Step 1: Gather context

Check for existing context in the conversation:
- Meeting notes, transcripts, prior analysis files
- Any documents in the working directory that relate to the project
- Prior scope documents or requirements

If context is insufficient, ask the user targeted questions:
1. "What problem are we solving?" (one sentence)
2. "Who is this for?" (stakeholders)
3. "What does 'done' look like?"
4. "What are the hard constraints?" (time, budget, people)

Do NOT ask more than 3 questions. Work with what you have.

### Step 2: Impact analysis (mandatory when a codebase exists)

This is the core of the scope document — spend more effort here than on
timelines. If the scope involves code changes:

- Use `Grep` and `Glob` to find every file the work would touch
- For each touched file, trace **what depends on it**: which
  features/pages/flows import it or break if it changes
- Identify shared code (types, utils, API clients) where a change ripples
  into other features
- Identify integration points: APIs, DB schema, external services, auth
- Classify each impacted feature: directly modified / indirectly affected /
  must-not-break

Never guess — every file path and feature named in the document must come
from actual codebase research.

### Step 3: Write the scope document

Save to a file in the working directory as `scope-[project-name].md`.

Use this EXACT format — it's optimized for Teams sharing (no complex tables, clean headers):

```markdown
# [Project Name] — Scope Document

**Date:** YYYY-MM-DD
**Author:** [from context]
**Stakeholders:** [list names and roles]
**Status:** Draft

---

## Problem Statement

[2-3 sentences. What is broken, inefficient, or missing? Why does it matter NOW?
Include measurable impact if possible — "currently takes X hours", "error rate is Y%"]

---

## Business Objective

[One clear, measurable goal this project achieves.
Format: "[Action verb] + [metric]" — a deadline is optional, not the point.
Example: "Reduce contract processing time from 45 min to under 5 min per client"]

---

## In-Scope (What We WILL Do)

### Deliverable 1: [Name]
- [ ] [Specific task]
- [ ] [Specific task]

### Deliverable 2: [Name]
- [ ] [Specific task]
- [ ] [Specific task]

[Each deliverable should be independently shippable if possible]

---

## Out-of-Scope (What We Will NOT Do)

> These items are explicitly excluded from this project.
> They may be addressed in future phases.

- **[Item 1]** — [Why excluded: future phase / different team / not priority]
- **[Item 2]** — [Why excluded]
- **[Item 3]** — [Why excluded]

[Be specific and exhaustive.
Every gray area should be listed here or in Ambiguous Zone.]

---

## Impact Analysis (Files & Features)

> THE most important section. What does this work actually touch,
> and what could it break? Every path below comes from codebase research.

### Files & Modules Touched

| File / Module | Change Type | Why |
|---------------|-------------|-----|
| `path/to/file` | modified / created / deleted | [reason] |

### Features & Flows Impacted

- **Directly modified:** [feature/flow] — [what changes for it]
- **Indirectly affected:** [feature/flow] — [imports/depends on a touched file: which one]
- **Must not break:** [feature/flow] — [why it's at risk, how we protect it]

### Shared Code & Ripple Effects

- [shared type / util / API client being changed] → [every consumer affected]

### Integration Points

- [API / DB schema / external service / auth surface touched, or "None"]

---

## Ambiguous Zone (Needs Decision)

> These items are unclear — we need stakeholder input before proceeding.

| # | Item | Options | Blocks | Owner |
|---|------|---------|--------|-------|
| 1 | [Description] | A: [option] / B: [option] | [which impacted file/feature is blocked] | [Person] |
| 2 | [Description] | A: [option] / B: [option] | [which impacted file/feature is blocked] | [Person] |

---

## Constraints

| Type | Constraint | Impact |
|------|-----------|--------|
| **Tech** | [Platform/tool limitations] | [Workarounds needed] |
| **Dependencies** | [External blockers] | [What's blocked until resolved] |

---

## Resources Needed

### Tools & Access
- [ ] [Tool/Platform]: [What access is needed, from whom]

### Information
- [ ] [Document/Data]: [Who has it, when do we need it by]

---

## Risks

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| [What could go wrong] | H/M/L | H/M/L | [What we do about it] |

---

## Success Criteria

How do we know this project is DONE?

- [ ] [Measurable criterion 1]
- [ ] [Measurable criterion 2]
- [ ] [Measurable criterion 3]

---

## Next Steps

1. [ ] [Immediate action] — **Owner:** [Name]
2. [ ] [Next action] — **Owner:** [Name]
3. [ ] [Next action] — **Owner:** [Name]
[Dates optional — add one only when there's a real external deadline]
```

### Step 4: Save and confirm

1. Save the file as `scope-[project-name].md` in the working directory
2. Show a brief summary to the user:
   - Number of in-scope deliverables
   - Files/modules touched and features impacted (the impact headline)
   - Number of out-of-scope items
   - Number of ambiguous items needing decisions
   - Key risks

## Rules

- **Impact over timelines.** The document's center of gravity is WHICH files
  and WHICH features are affected — not how long things take or by when.
  Only include dates driven by real external deadlines.
- **Impact Analysis is mandatory and research-backed.** Every file path in it
  must exist in the codebase; every impacted feature must trace to a touched
  file. No guessed paths.
- **Out-of-Scope is mandatory.** Never skip it. If the user didn't mention exclusions, infer likely scope creep candidates from context and list them.
- **Ambiguous Zone is mandatory.** There are ALWAYS gray areas. If you can't find any, you haven't thought hard enough.
- **No fluff.** Every line should be actionable or decision-forcing. Remove filler words.
- **Match the user's language.** Whatever language(s) they write in, respond in kind. If they mix, you mix.
- **Teams-friendly formatting.** No nested tables, no HTML, no complex markdown. Keep it clean — headers, bullets, simple tables only.
- **Be opinionated.** If something is obviously out-of-scope based on constraints, say so. Don't hedge everything.
- **Resources section must be concrete.** "We need a developer" is bad. "Jane: 20hrs/week on API integration" is good.
- **One file, one scope.** Don't split across multiple files.
