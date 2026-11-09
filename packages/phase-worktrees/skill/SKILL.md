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
4. Worktrees go in `<repo>/.worktrees/` unless `--root` says otherwise: a
   sandboxed session can only write inside its own repo, so a directory beside
   the repo fails with "Read-only file system". The script adds
   `/.worktrees/` to `.git/info/exclude` so the main checkout's `git status`
   stays clean.
5. Relay the launch lines the script prints. Each phase needs its own terminal
   and its own `claude` session.

## Removing

```bash
"$HOME/.claude/skills/phase-worktrees/bin/phase-worktrees.sh" --remove 1 2 4 6
```

Refuses any worktree holding uncommitted changes. `--force` overrides that and
discards them, so confirm with the user before adding it. Branches are always
kept — removing a worktree never deletes work that was committed.

## `.claude` in each worktree: a symlink, or a copy when `.claude/` is tracked

The script links each worktree's `.claude` to the main checkout's, so a
permission approved in one phase session holds in every phase and in the main
checkout. If the repo tracks anything under `.claude/` in git, it makes a real
`.claude/` directory instead and copies `settings.json` and
`settings.local.json` into it: the worktree's checkout already holds the
tracked files, and a symlink in their place shows every one as deleted.

Until 9 Nov 2026 the script always copied, on the belief that a symlink put
`.claude/worktrees` outside the session's writable area, so GSD's agent
worktrees failed and a wave ran one plan at a time. Two identical probes, one
copied and one symlinked, both ran two 60-second plans in parallel (see
`BACKLOG.md` item 2). Claude Code creates agent worktrees itself, outside the
Bash sandbox, and puts them in the main checkout's `.claude/worktrees/` either
way — that location is normal, not a symptom.

`--remove` unlinks the symlink and leaves the main checkout's `.claude` alone;
`git worktree remove` does not follow it, with or without `--force`.

If a wave does run one plan at a time, check `workflow.use_worktrees` and
`parallelization.enabled` in `.planning/config.json`, and whether the plans
share files: GSD runs plans that touch the same files one after another.

## What else the script sets up

- Branch per phase, derived from the phase directory name:
  `01-new-settings-page-abc-123` becomes
  `unit/ABC-123-new-settings-page-phase`. Phases with no ticket id in the
  directory name fall back to `gsd/phase-<n>-<slug>`.
- `.claude` linked to the main checkout's, or copied when `.claude/` is
  tracked — see above.
- Worktrees at `<repo>/.worktrees/p<n>-<slug>`, inside the repo so a sandboxed
  session can create them, with `/.worktrees/` in `.git/info/exclude` so git
  status in the main checkout does not list them.
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
