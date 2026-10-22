---
name: repo-remote-control
description: <What it does and when to use it. This sentence is all Claude sees when deciding whether to load the skill, so lead with the trigger — "Use when the user wants to ...">
allowed-tools:
  - Bash
  - Read
---

# repo-remote-control

Wraps `bin/repo-remote-control.sh`, which does the work. Do not reimplement its steps by
hand — behaviour must stay identical between runs.

```bash
"$HOME/.claude/skills/repo-remote-control/bin/repo-remote-control.sh" [options]
```

## <What to do>

1. ...

## <The part that is easy to get wrong>

<The trap. Every skill worth writing has one — the thing that looks like a
simplification and quietly breaks something. Say what the symptom looks like so
it is recognisable months later.>
