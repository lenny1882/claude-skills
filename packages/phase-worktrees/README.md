# phase-worktrees

A Claude Code skill that gives each GSD phase its own git worktree and branch,
so several phases can be executed at once from separate terminals.

Part of [claude-skills](https://github.com/lenny1882/claude-skills), which holds several packages
that are each versioned, released and installed on their own.

## Install

Needs `curl`, `tar` and `jq`. From the newest release:

    v=$(curl -fsSL https://raw.githubusercontent.com/lenny1882/claude-skills/versions/versions.txt | awk '$1=="phase-worktrees" {print $2}')
    curl -fsSL "https://github.com/lenny1882/claude-skills/releases/download/phase-worktrees-v$v/phase-worktrees.tar.gz" | tar -xz
    cd phase-worktrees && ./install.sh

These lines never change between versions: `versions.txt` names the newest
stable release, and only once its tarball is uploaded. To pin a version,
download `.../releases/download/phase-worktrees-vX.Y.Z/phase-worktrees.tar.gz` instead.

Or from a clone of the whole repo:

    git clone https://github.com/lenny1882/claude-skills && cd claude-skills/packages/phase-worktrees
    ./install.sh              # install
    ./install.sh --link       # or symlink, so edits in the checkout are live
    ./install.sh --dry-run    # show the settings change, write nothing
    ./install.sh --yes        # no prompts

Re-running the installer is safe and is how you upgrade. It replaces whatever
is at `~/.claude/skills/phase-worktrees` and keeps no copy of it.

Skills need no `settings.json` entry — Claude Code reads anything under
`skills/` at startup, so restart before using it.

## Use

Ask for it in words ("give me a worktree for phases 1, 2 and 4"), or drive the
script directly:

    ~/.claude/skills/phase-worktrees/bin/phase-worktrees.sh [--base ref] [--dry-run] 1 2 4
    ~/.claude/skills/phase-worktrees/bin/phase-worktrees.sh --remove [--force] 1 2 4

Every path is derived at runtime from `git rev-parse`; nothing is hardcoded, so
it works in any GSD project. Worktrees go inside the repo, at
`<repo>/.worktrees/p<n>-<slug>`, because a sandboxed session can only write
inside its own repo; a directory beside it fails with "Read-only file system".
The script adds `/.worktrees/` to `.git/info/exclude`, so `git status` in the
main checkout does not list them. `--root` puts them elsewhere, and
`--remove` finds a phase's worktree by its branch wherever it is.
Branches come from the phase directory name — `01-new-settings-page-abc-123`
becomes `unit/ABC-123-new-settings-page-phase`, and phases without a ticket
id fall back to `gsd/phase-<n>-<slug>`.

Removing refuses while a worktree holds uncommitted changes, and never deletes a
branch. Committed work survives removal either way.

## `.claude` in each worktree

Each worktree's `.claude` is a symlink to the main checkout's, so permission
approvals carry between the phases and the main checkout. If the repo tracks
anything under `.claude/` in git, the worktree gets a real `.claude/`
directory with copies of `settings.json` and `settings.local.json` instead,
because a symlink over tracked files makes git see them as deleted.

It used to copy every time, on the belief that a symlink stopped GSD's agent
worktrees being created, so a wave ran one plan at a time. Tested on 9 Nov
2026 with two identical probes, one copied and one symlinked: both ran two
60-second plans in parallel, and both put the agent worktrees in the main
checkout's `.claude/worktrees/`, which is where Claude Code always puts them.
Removing a worktree unlinks the symlink and leaves the main checkout's
`.claude` alone.

## Also worth knowing

- **`git.branching_strategy` must stay `none`** in `.planning/config.json`. Set
  to `phase` or `milestone`, execute-phase runs `git switch` inside the worktree,
  which throws the isolation away and fails outright when the branch is already
  checked out elsewhere.
- **Worktrees isolate the filesystem, not the merge.** Before starting, read the
  `files_modified` frontmatter of every plan in the chosen phases and look for a
  file two phases both touch. Regenerated code and shared test fixtures conflict
  worst.
- `.planning/STATE.md` and `.planning/ROADMAP.md` are marked skip-worktree in
  each worktree, so phase commits never carry shared milestone bookkeeping. The
  main checkout stays the source of truth.
- Gitignored config such as `.env` is deliberately not copied.
- One local dev stack at a time if the project binds fixed ports.

## Update

    ./update.sh            check, ask, upgrade, reinstall
    ./update.sh --check    report what is available and stop

Reads this package's line in `versions.txt`, so pre-releases, and releases of
the other packages in the repo, are never offered. Works from a downloaded
tarball as well as a clone — no git needed.

## Uninstall

    ./uninstall.sh                 ask before editing settings.json
    ./uninstall.sh --keep-settings leave settings.json alone

## Tests

    ./test/run-tests.sh

Redirects `HOME` and `CLAUDE_DIR` into a temp directory, so your real config is
never touched. `./test/run-tests.sh` at the repo root runs every package's.

Builds a throwaway GSD-shaped repo in a temp directory and runs a real create
and remove cycle against it: the symlinked `.claude` and the copy for a repo
that tracks `.claude/`, and that removal leaves the main checkout's `.claude`
alone.

## Releasing

`/release phase-worktrees` at the repo root — bump `packages/phase-worktrees/VERSION` on `main`,
move `release/phase-worktrees-vX.x` onto it, tag `phase-worktrees-vX.Y.Z` there. The tag is what
publishes it. The release carries what `PAYLOAD` lists, and nothing else in
this directory.
