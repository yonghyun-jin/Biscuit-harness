---
name: ticket
version: 1.0.0
description: |
  Transform rough ideas or ugly Linear tickets into well-structured implementation
  tickets with goal, acceptance criteria, output, blast radius, files modified,
  problem description, and minimal-change strategy. Use when asked to "write a ticket",
  "clean up this ticket", "make a Linear ticket", "plan this task", or when given
  raw text that should become a structured ticket. Also use when the user pastes a
  Linear ticket URL and asks to improve it.
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
  - AskUserQuestion
  - mcp__linear-server__get_issue
  - mcp__linear-server__save_issue
  - mcp__linear-server__list_issues
  - mcp__linear-server__get_team
  - mcp__linear-server__list_teams
  - mcp__linear-server__list_issue_labels
  - mcp__linear-server__list_issue_statuses
---

# /ticket — Structured Implementation Ticket Writer

You transform rough ideas, messy notes, or ugly Linear tickets into beautiful,
actionable implementation tickets.

## Input modes

1. **Linear ticket ID/URL** — Fetch the existing ticket, analyze it, rewrite it
2. **Raw text in chat** — User describes what they want, you structure it
3. **Multiple items** — User lists several things, you create a ticket for each

## Process

### Step 1: Understand the request

If the user gave a Linear ticket ID (e.g., `AI-42`), fetch it with `mcp__linear-server__get_issue`.
If the user gave raw text, parse it for intent.

### Step 2: Research the codebase

Before writing the ticket, **always research the codebase** to ground the ticket in reality:

- Use `Grep` and `Glob` to find relevant files
- Use `Read` to understand current implementations
- Identify exactly which files need to change
- Understand the current architecture around the change area
- Look for related tests, types, and dependencies

### Step 3: Write the structured ticket

Output the ticket in this exact format (use markdown):

```markdown
## Problem Description
[What is broken, missing, or needs improvement. Be specific — include current behavior vs desired behavior if applicable.]

## Goal
[One clear sentence: what does "done" look like?]

## Acceptance Criteria
- [ ] [Specific, testable criterion 1]
- [ ] [Specific, testable criterion 2]
- [ ] [...]
[Each criterion should be independently verifiable. No vague items like "works correctly".]

## Output
[What artifact(s) does this produce? New component? API endpoint? DB migration? Updated page?]

## Blast Radius & Impact
- **Files modified:** [List each file path that will change]
- **Files created:** [List any new files, or "None"]
- **Files deleted:** [List any removed files, or "None"]
- **Dependencies affected:** [Other packages/modules that import from changed files]
- **Risk level:** [Low / Medium / High] — [one-line justification]
- **Rollback strategy:** [How to undo if something goes wrong]

## Minimal Change Strategy
[Explain why this is the smallest set of changes to achieve the goal. Call out what you are NOT changing and why.]

## Implementation Plan
1. [Step 1 — specific action in specific file]
2. [Step 2 — ...]
3. [...]
[Ordered steps. Each step should reference a specific file or command.]

## Testing
- [ ] [How to verify criterion 1]
- [ ] [How to verify criterion 2]
- [ ] [...]
```

### Step 4: Update Linear (if applicable)

If the user wants to push back to Linear, use `mcp__linear-server__save_issue` to update
the ticket description with the structured content.

**Ask the user** before updating Linear: "Want me to push this back to Linear?"

## Rules

- **Always research the codebase first.** Never guess at file paths or architecture.
- **Be specific.** "Update the component" is bad. "Update `apps/web/components/voice-agent/VoiceToggle.tsx` to add a mute button" is good.
- **Minimal changes.** Default to the smallest change that achieves the goal. Call out scope creep.
- **No invented requirements.** Only include what the user asked for. Don't add "nice to have" items.
- **File paths must be real.** Every file listed in Blast Radius must exist (or be a clearly-marked new file).
- **Risk assessment must be honest.** Don't default to "Low" — think about what could actually break.
