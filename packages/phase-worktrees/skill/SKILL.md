---
name: phase-worktrees
description: Create one git worktree per GSD phase so several phases can be executed in parallel, each on its own branch in its own Claude session. Use when the user wants to run planned phases concurrently, asks for a worktree per phase, or asks to tear those worktrees down afterwards. Works in any GSD project — all paths are derived from the repo at runtime.
allowed-tools:
  - Bash
  - Read
  - AskUserQuestion
---

# Phase worktrees

Wraps `bin/phase-worktrees.sh`, which does all the work. Do not reimplement its
steps by hand — behaviour must stay identical between runs.

```bash
"$HOME/.claude/skills/phase-worktrees/bin/phase-worktrees.sh" [options] <phase>...
```

## Creating

1. Work out which phases the user means. If they named them ("1, 2, 4 and 6"),
   use those. If they said "all planned phases" or similar, read
   `.planning/ROADMAP.md` and `.planning/phases/` and propose a list — phases
   with plans on disk and no completion marker — then confirm with
   AskUserQuestion before creating anything.
2. Check the base branch. The script defaults to the current branch, which is
   normally right, but say which branch it will be so the user can object.
   Override with `--base <ref>`.
3. Run with `--dry-run` first when creating more than two worktrees, show the
   user the derived branch names, then run for real.
4. Relay the launch lines the script prints. Each phase needs its own terminal
   and its own `claude` session.

## Removing

```bash
"$HOME/.claude/skills/phase-worktrees/bin/phase-worktrees.sh" --remove 1 2 4 6
```

Refuses any worktree holding uncommitted changes. `--force` overrides that and
discards them, so confirm with the user before adding it. Branches are always
kept — removing a worktree never deletes work that was committed.

## Why the script copies `.claude/` instead of symlinking it

This is the part that is easy to get wrong and expensive to debug.

GSD's `/gsd:execute-phase` runs the plans in a wave as parallel subagents with
`isolation="worktree"`, and Claude Code creates those subagent worktrees under
`<project>/.claude/worktrees/`. If the phase worktree's `.claude` is a symlink
back to the main checkout, that path resolves outside the session's writable
area and the subagent worktrees fail to create — the session falls back to
running one plan at a time, and can fork from the main checkout's HEAD rather
than the phase branch.

So the script creates a real `.claude` directory in each worktree and copies
`settings.json` and `settings.local.json` into it. The cost is that permission
approvals no longer carry between worktrees. That is the correct trade.

If a user reports "worktree isolation doesn't work in this sandbox" or agent
worktrees appearing under the main checkout, check for a symlinked `.claude`
first.

## What else the script sets up

- Branch per phase, derived from the phase directory name:
  `01-non-product-requests-hbd20-1786` becomes
  `unit/HBD20-1786-non-product-requests-phase`. Phases with no ticket id in the
  directory name fall back to `gsd/phase-<n>-<slug>`.
- Worktrees at `<repo-parent>/<repo-name>-worktrees/p<n>-<slug>`, outside the
  repo so git never sees them.
- Symlinks to gitignored build directories that exist in the main checkout —
  `vendor`, `node_modules`, `.venv`, `target`, `build` — so they are shared
  rather than duplicated.
- `.planning/STATE.md` and `.planning/ROADMAP.md` marked skip-worktree in each
  worktree. Both are single-writer files that every phase would otherwise
  rewrite, so this keeps them out of phase commits entirely. The main checkout
  stays the source of truth; reconcile milestone state there when phases land.
- `.claude/` appended once to the shared `info/exclude`.

Gitignored config files such as `.env` are deliberately not copied. Mention
this if the project needs one to run locally.

## Worth telling the user up front

- **Check for overlapping files before starting.** Worktrees isolate the
  filesystem, not the merge. Read the `files_modified` frontmatter of every
  plan in the chosen phases and report any file two phases both touch —
  regenerated code and shared test fixtures conflict worst.
- **`git.branching_strategy` must stay `none`** in `.planning/config.json`.
  Set to `phase` or `milestone`, execute-phase runs `git switch` inside the
  worktree, which discards the isolation and fails outright when the branch is
  already checked out elsewhere.
- **One local dev stack at a time** if the project binds fixed ports.
