# phase-worktrees — backlog

Started 21 Aug 2026 from a session that created the phase 2 worktree for
a client app project. Skill version at the time: 1.0.0.

---

## 1. Default the worktree root to `${project_root}/.worktrees` — **DONE 9 Nov 2026, raised 21 Aug 2026**

**Done 9 Nov 2026**, not yet released. The default is `<repo>/.worktrees`; a
relative `--root` is taken from the repo root. `/.worktrees/` (the root,
anchored) goes into `info/exclude` alongside `.claude/`, and only when the root
is inside the repo. `--remove` also finds a phase's worktree by its branch, so
worktrees made at the old default can still be removed. The "outside
the repo so git never sees them" line, in both `SKILL.md` and `README.md`, is
replaced with the reason for the new location.

**Session: 21 Aug 2026**, creating a worktree for phase 2 of
a client app project (`.planning/phases/02-user-permissions`).

`WT_ROOT` currently defaults to `<repo-parent>/<repo-name>-worktrees`, chosen so
that git never sees the worktrees. On this machine the Bash sandbox only permits
writes inside the repo working directory, so both steps that touch the sibling
directory fail:

    mkdir: cannot create directory
      '~/Development/client/app-worktrees':
      Read-only file system

and, once that directory had been created with the Write tool instead:

    fatal: could not create leading directories of
      '.../app-worktrees/p2-.../.git':
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

**Tested 9 Nov 2026**, from a sandboxed session (Bash tool) in
`claude-skills`:

- `git worktree add .worktrees/probe` from the main checkout worked, and so
  did `git worktree add` into `.worktrees/probe/.claude/worktrees/agent`.
- The sandbox's read-only mounts are exact paths under the session's own
  working directory (`<cwd>/.claude/skills`, `<cwd>/.claude/hooks`, parts of
  `<cwd>/.git`), read from `/proc/self/mountinfo`. A nested `.claude/skills`,
  `.claude/hooks` and `.claude/commands` in a throwaway repo inside the working
  directory were all writable.
- `<cwd>/.claude/worktrees` was writable, though `.claude` itself is listed as
  a read-only mount. That is where a session started in a phase worktree puts
  its subagent worktrees.
- `.git/info/exclude` was writable.
- With `.worktrees/` not excluded, `git status` listed it as untracked.

**Run 9 Nov 2026**: a real `/gsd:execute-phase 1` in a session started inside
`<repo>/.worktrees/p1-two-files` of a throwaway GSD project (one phase, two
plans in wave 1, `workflow.use_worktrees: true`):

- **Passed.** Both plans ran in parallel as subagents in worktrees. Each made
  its two commits on a `worktree-agent-<id>` branch, and the orchestrator
  merged both into `gsd/phase-1-two-files`, which ended 6 commits ahead of
  `main`. `main` did not move.
- **Where the subagent worktrees went:** `<repo>/.claude/worktrees/agent-<id>`,
  in the main checkout, not `<phase worktree>/.claude/worktrees/`. Claude Code
  roots them at the main checkout. The old troubleshooting note named "agent
  worktrees under the main checkout" as a symptom of a symlinked `.claude`;
  that note is corrected in `SKILL.md` and `README.md`.
- **Left behind when the session ended (exit 0):** GSD deleted both
  `worktree-agent-<id>` branches and their directories, but `git worktree
  list` still showed both as detached at `0000000` until `git worktree prune`.
  The phase worktree had `.planning/config.json` modified (GSD added
  `"_auto_chain_active": false` and a final newline) and an untracked
  `.planning/HANDOFF.json` for `/gsd:resume-work`. The main checkout was
  clean. None of this is phase-worktrees' doing, but `--remove` hits it:
  without `--force` it refuses a worktree holding those two files.
- **Not settled by it:** both the phase branch and `main` were at the same
  commit, so the run cannot show whether the agents forked from the phase
  branch or from `main`. A rerun with the phase branch one commit ahead of
  `main` would show it.
- **Also open:** the reason given for copying `.claude/` rather than
  symlinking it is that a symlink puts `.claude/worktrees` outside the
  session's writable area. This run created the agent worktrees outside the
  phase session's working directory without trouble, because Claude Code
  creates them itself, not through sandboxed Bash. The copy may no longer be
  needed for that reason; untested.
