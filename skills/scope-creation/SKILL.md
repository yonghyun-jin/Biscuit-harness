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

### Step 2: Research (if codebase exists)

If the scope involves code changes:
- Use `Grep` and `Glob` to find relevant files
- Understand current architecture
- Identify integration points and dependencies

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
Format: "[Action verb] + [metric] + by [when]"
Example: "Reduce contract processing time from 45 min to under 5 min per client by Q3 2026"]

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

[This is THE most important section. Be specific and exhaustive.
Every gray area should be listed here or in Ambiguous Zone.]

---

## Ambiguous Zone (Needs Decision)

> These items are unclear — we need stakeholder input before proceeding.

| # | Item | Options | Decision Needed By | Owner |
|---|------|---------|-------------------|-------|
| 1 | [Description] | A: [option] / B: [option] | [Date] | [Person] |
| 2 | [Description] | A: [option] / B: [option] | [Date] | [Person] |

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

1. [ ] [Immediate action] — **Owner:** [Name] — **By:** [Date]
2. [ ] [Next action] — **Owner:** [Name] — **By:** [Date]
3. [ ] [Next action] — **Owner:** [Name] — **By:** [Date]
```

### Step 4: Save and confirm

1. Save the file as `scope-[project-name].md` in the working directory
2. Show a brief summary to the user:
   - Number of in-scope deliverables
   - Number of out-of-scope items
   - Number of ambiguous items needing decisions
   - Key risks

## Rules

- **Out-of-Scope is mandatory.** Never skip it. If the user didn't mention exclusions, infer likely scope creep candidates from context and list them.
- **Ambiguous Zone is mandatory.** There are ALWAYS gray areas. If you can't find any, you haven't thought hard enough.
- **No fluff.** Every line should be actionable or decision-forcing. Remove filler words.
- **Korean + English is OK.** Match the user's language. If they mix, you mix.
- **Teams-friendly formatting.** No nested tables, no HTML, no complex markdown. Keep it clean — headers, bullets, simple tables only.
- **Be opinionated.** If something is obviously out-of-scope based on constraints, say so. Don't hedge everything.
- **Resources section must be concrete.** "We need a developer" is bad. "Sean: 20hrs/week on API integration" is good.
- **One file, one scope.** Don't split across multiple files.
