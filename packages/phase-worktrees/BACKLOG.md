# phase-worktrees — backlog

Started 21 Aug 2026 from a session that created the phase 2 worktree for
`hugoboss-flutter-runner`. Skill version at the time: 1.0.0.

---

## 1. Default the worktree root to `${project_root}/.worktrees` — **OPEN**

**Session: 21 Aug 2026**, creating a worktree for phase 2 of
`hugoboss-flutter-runner` (`.planning/phases/02-action-restrictions-task-locking`).

`WT_ROOT` currently defaults to `<repo-parent>/<repo-name>-worktrees`, chosen so
that git never sees the worktrees. On this machine the Bash sandbox only permits
writes inside the repo working directory, so both steps that touch the sibling
directory fail:

    mkdir: cannot create directory
      '/mnt/sda/Development/oi/native/hugoboss-flutter-runner-worktrees':
      Read-only file system

and, once that directory had been created with the Write tool instead:

    fatal: could not create leading directories of
      '.../hugoboss-flutter-runner-worktrees/p2-.../.git':
      Read-only file system

The skill is therefore unusable from a sandboxed session at its default setting.
`--root .worktrees` works and was what the session fell back to.

Make `${project_root}/.worktrees` the default.

Two things the change has to carry with it:

- **Ignore the root.** The script appends `.claude/` to `.git/info/exclude` and
  nothing else. With the root inside the repo, `git status` in the main checkout
  lists the whole worktree as untracked. The session added `.worktrees/` to
  `info/exclude` by hand. The script should do it, in the same place and the same
  way it does `.claude/`.
- **Say what it costs.** SKILL.md's stated reason for the current location is
  "outside the repo so git never sees them". Replace that line rather than
  leaving it contradicting the code.

Open question, not settled by this session: GSD's `/gsd:execute-phase` creates
subagent worktrees under `<worktree>/.claude/worktrees/`. With the phase worktree
inside the repo, those nest two levels deep in the working directory. Untested
whether the sandbox's read-only remount of `.claude/skills`, `.claude/hooks` and
`.claude/commands` in the main checkout extends to a nested `.claude/` and blocks
them.
