# agents/

One `.md` file per agent definition:

```markdown
---
name: code-reviewer
description: When Claude should delegate to this agent.
tools: Read, Grep, Glob, Bash
---

System prompt for the agent.
```

`./setup` symlinks every `agents/*.md` (except this README) into
`~/.claude/agents/`, so they're auto-discovered in every project.

Edit agents here (in the harness repo), never in `~/.claude/agents/` — the
symlinks point back to this repo, and `git push` is the deployment.
