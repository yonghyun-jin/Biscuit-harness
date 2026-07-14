---
name: implement
description: |
  Implement a ticket from the project's connected Linear workspace: fetch the
  ticket, create a branch from main, plan the work as a todo list BEFORE coding,
  then execute todo-by-todo. Linear is the system of record only — execution is
  tracked with todos (plan-first model). If no Linear is connected, the plan is
  saved to a plan/ folder in the repo instead.
user_invocable: true
arguments: ticket ID or URL — or a free-text task description when no Linear is connected
---

# /implement — Ticket Implementation (plan-first)

Takes a ticket from **whatever Linear workspace is connected to this project**,
creates a branch, turns the ticket into a todo plan, and implements it step by
step.

Two principles:

1. **Linear is for recording only.** Fetch the ticket from it, mark it
   In Progress, record the outcome at the end. Linear does not drive execution.
2. **Todos drive execution** (plan-first model): before writing any code, list
   every step as a todo (`pending`), then execute sequentially — exactly one
   `in_progress` at a time, mark `completed` before moving on. This keeps long
   implementations from drifting off the original goal.

## Usage

```
/implement ABC-123
/implement https://linear.app/<workspace>/issue/ABC-123/some-title
/implement fix the reset-eligibility bug in the bot session   ← no Linear / no ticket
```

## Workflow

### Step 1: Resolve the ticket

- URL like `https://linear.app/.../ABC-123/...` → extract `ABC-123`
- Bare identifier (`<TEAM>-<number>`, any team prefix) → use directly
- Free text → skip to Step 2b (fallback mode)

### Step 2: Fetch from the connected Linear

Use `mcp__linear-server__get_issue` with the identifier. The workspace is
whatever Linear this project/user has connected — never assume a specific team
or workspace name.

Collect: title, description (goal, acceptance criteria, files to change),
current status.

**If the Linear MCP is not connected, or the ticket cannot be found → Step 2b.**

### Step 2b: Fallback — `plan/` folder (no Linear)

If there is no connected Linear (or no ticket exists for this work):

1. Create a `plan/` folder at the repo root if it doesn't exist
2. Write `plan/<short-slug>.md` containing:
   - **Goal** — one sentence
   - **Acceptance criteria** — testable checklist
   - **Todo plan** — the same steps you will register as todos in Step 5
3. This file replaces Linear as the record: check items off as they complete,
   and finish it with the Step 7 summary

Then continue with Step 3 (use the slug where a ticket ID would be used).

### Step 3: Create a branch from latest main

Branch name: `<user>/<ticket-id-lowercase>` — derive `<user>` from
`git config user.name` (first name, lowercased). Example: `jane/abc-123`.
Do NOT use Linear's suggested `gitBranchName` — too long.

```bash
git fetch origin main
git checkout -b <user>/<ticket-id-lowercase> origin/main
```

If the branch already exists, ask the user: switch to it, or delete and
recreate from latest main.

### Step 4: Record "In Progress" in Linear

Record-keeping only: `mcp__linear-server__save_issue` → state `In Progress`.
(Fallback mode: note `Status: In Progress` at the top of the plan file.)

### Step 5: Plan the work as todos — BEFORE any code

Read the ticket description carefully, then write the full implementation plan
as a todo list using the todo tool:

- One todo per concrete step, in execution order (e.g. "Read X and Y",
  "Change A in file B", "Update tests", …)
- All start as `pending`
- Always include a final todo: **"Verify acceptance criteria"**
- In fallback mode, mirror this list as a checklist in the plan file

Do not start editing files until the todo plan is registered.

### Step 6: Execute todo-by-todo

Work through the list sequentially: mark the current todo `in_progress`, do it,
mark it `completed`, move to the next. Never have more than one `in_progress`.

Rules while implementing:
- Read each file before editing it
- Make minimal, focused changes that match the ticket scope
- Do not add unrelated improvements
- Do not add changelog entries or version bumps

### Step 7: Close the loop

After the final todo (acceptance criteria verified), print:
- Ticket identifier and title (or plan file path)
- Branch name
- Files changed
- What was done (brief)
- Each acceptance criterion and whether it is met

Then record the outcome:
- **Linear mode:** this summary is the record — leave the ticket In Progress
  (status moves to Done at merge, not at implementation)
- **Fallback mode:** check off completed items in `plan/<slug>.md` and append
  the summary
