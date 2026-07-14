# skills/

Each skill is a directory containing a `SKILL.md`:

```
skills/
└── ship/
    └── SKILL.md
```

`./setup` symlinks every `skills/<name>/` that has a `SKILL.md` into
`~/.claude/skills/<name>`, so Claude Code discovers it as `/name`.

`SKILL.md` format:

```markdown
---
name: ship
description: When to use this skill — Claude reads this to decide when to invoke it.
---

Instructions the model follows when the skill is invoked.
```

Edit skills here (in the harness repo), never in `~/.claude/skills/` — the
symlinks point back to this repo, and `git push` is the deployment.
