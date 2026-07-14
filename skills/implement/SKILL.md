---
name: implement
description: Fetch a Linear ticket, create a branch from main, and implement the changes described in the ticket.
user_invocable: true
arguments: ticket ID or URL
---

# /implement — Linear Ticket Implementation

Takes a Linear ticket URL or identifier, creates a branch from latest main, and implements the work described in the ticket.

## Usage

```
/implement AI-248
/implement https://linear.app/ai-itin-miklos/issue/AI-248/fix-reset-eligibility-bot-session-on-close
```

## Workflow

### Step 1: Parse the ticket identifier

Extract the ticket identifier from the argument:
- If it's a URL like `https://linear.app/.../AI-248/...`, extract `AI-248`
- If it's already an identifier like `AI-248`, use it directly
- The identifier format is `AI-NNN` (letters dash numbers)

### Step 2: Fetch the ticket from Linear

Use `mcp__linear-server__get_issue` with the extracted identifier to get:
- Title
- Description (implementation details, acceptance criteria, files to change)
- `gitBranchName` (Linear's suggested branch name)
- Current status

If the ticket cannot be found, stop and tell the user.

### Step 3: Create a branch from latest main

Derive the branch name from the ticket identifier: `sean/<ticket-id-lowercase>` (e.g., `sean/ai-254`).
Do NOT use Linear's `gitBranchName` — it's too long.

Run these git commands:
```bash
git fetch origin main
git checkout -b sean/<ticket-id-lowercase> origin/main
```

If the branch already exists, ask the user whether to:
- Switch to the existing branch
- Delete and recreate it from latest main

### Step 4: Update ticket status to In Progress

Use `mcp__linear-server__save_issue` to update the ticket:
- Set `state` to `In Progress`
- Use the ticket `id` from the fetch response

### Step 5: Implement the changes

Read the ticket description carefully. It contains:
- **Goal** — what needs to happen
- **Files to Change** — where to make changes
- **Acceptance Criteria** — what "done" looks like

Then implement the changes described in the ticket. Follow these rules:
- Read each file before editing it
- Make minimal, focused changes that match the ticket scope
- Do not add unrelated improvements
- Do not add changelog entries or version bumps

### Step 6: Summary

After implementation, print:
- Ticket identifier and title
- Branch name
- List of files changed
- What was done (brief)
- Any acceptance criteria items and whether they are met
