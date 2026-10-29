# repo-remote-control-server

Runs one Claude Remote Control server per repo on an always-on Linux box, as
systemd user services, so any repo there can be opened from claude.ai or the
Claude app without SSHing in.

`claude remote-control` only opens sessions in the directory it was started
in, so reaching twenty repos means twenty servers. Each one has to survive
reboots, be trusted in `~/.claude.json`, and be restarted when `claude`
updates, without ending sessions someone is in the middle of. Its URL changes
on every restart and is buried in a redrawing status screen, and the app
names environments after the folder, so two repos called `web` look the same.

It builds on [`repo-remote-control-session`](../repo-remote-control-session/),
which has to be installed first: `rrcd` sources its `rrc` for finding the
repo, trust, the lock and reading the output. One-off sessions are that
package's `rrc session`.

Part of [claude-skills](https://github.com/lenny1882/claude-skills), which holds several packages
that are each versioned, released and installed on their own.

## What you actually see

On the box, over SSH or from the orchestrator Claude session through the
skill:

    $ rrcd clone shop client_acme
    /home/james/repos/client_acme/shop
    https://claude.ai/code?environment=env_01RC4TRVy72Uh3ogRs7kFsSG

    $ rrcd list
    /home/james/repos/client_acme/shop
      active, enabled, sessions 1/32
      https://claude.ai/code?environment=env_01RC4TRVy72Uh3ogRs7kFsSG

Open the URL and start a session: it gets its own git worktree, starts with no
branch, and is told to create one named `<type>/<KEY>-<description>` before it
changes anything. Committing before that is blocked.

When `claude` updates, idle servers restart on their own. If a server has
sessions open, the orchestrator asks you which to restart.

`rrc session <dir>`, from `repo-remote-control-session`, opens one session
instead of a server.

`rrcd remove`, `rrcd restart-all`, `rrcd disable` and `rrcd teardown` are yours
to run: they stay inside Claude's sandbox, so Claude's calls to them fail.

## Install

Install `repo-remote-control-session` first; the install fails without its
`rrc` on `PATH`. Needs `curl`, `tar` and `jq`. From the newest release:

    v=$(curl -fsSL https://raw.githubusercontent.com/lenny1882/claude-skills/versions/versions.txt | awk '$1=="repo-remote-control-server" {print $2}')
    curl -fsSL "https://github.com/lenny1882/claude-skills/releases/download/repo-remote-control-server-v$v/repo-remote-control-server.tar.gz" | tar -xz
    cd repo-remote-control-server && ./install.sh

These lines never change between versions: `versions.txt` names the newest
stable release, and only once its tarball is uploaded. To pin a version,
download `.../releases/download/repo-remote-control-server-vX.Y.Z/repo-remote-control-server.tar.gz` instead.

Or from a clone of the whole repo:

    git clone https://github.com/lenny1882/claude-skills && cd claude-skills/packages/repo-remote-control-server
    ./install.sh              # install
    ./install.sh --link       # or symlink, so edits in the checkout are live
    ./install.sh --dry-run    # show the settings change, write nothing
    ./install.sh --yes        # no prompts

Re-running the installer is safe and is how you upgrade. It merges into
`settings.json` rather than replacing it, backs the file up first, and only ever
touches its own entries. If Claude Code is already running, `/hooks` forces a
settings reload.

The entries are the two hooks and six `sandbox.excludedCommands` entries:
`rrcd start *`, `rrcd clone *`, `rrcd list`, `rrcd url *`, `rrcd restart *`
and `rrcd stop *`, added next to whatever is there. The rest of `sandbox` is
left as it is.

Run the installer in your own terminal or with `!` in Claude Code. Claude's own
Bash tool can't: its sandbox blocks writes to `~/.claude/skills`,
`~/.local/bin` and `settings.json`.

## Update

    ./update.sh            check, ask, upgrade, reinstall
    ./update.sh --check    report what is available and stop

Reads this package's line in `versions.txt`, so pre-releases, and releases of
the other packages in the repo, are never offered. Works from a downloaded
tarball as well as a clone — no git needed.

## Uninstall

    ./uninstall.sh                 ask before editing settings.json
    ./uninstall.sh --keep-settings leave settings.json alone
    ./uninstall.sh --keep-state    keep the package's state for a later reinstall

Uninstalling also takes its entries out of `sandbox.excludedCommands`, unless
`--keep-settings` is given.

Coming from `repo-remote-control` 1.1.0, which this package and
`repo-remote-control-session` replace: run that version's
`./uninstall.sh --keep-state` first (it stops every server itself), then install both new packages, then
move `~/.claude/skills/repo-remote-control/state/repos`, `logs` and `config`
into `~/.claude/skills/repo-remote-control-server/state/` and start each
server again with `rrcd start <dir>`. The unit names have not changed. Only
the old uninstaller knows the old names.

## How it works

- `rrcd start` finds the repo root, sets
  `projects["<root>"].hasTrustDialogAccepted` in `~/.claude.json` (backed up,
  written through a temp file and `mv`), writes the repo's flags to
  `state/repos/<instance>.env`, and starts `rrc-server@<instance>.service`, the
  instance being the root escaped with `systemd-escape --path`. The unit runs
  `claude remote-control --spawn worktree` with those flags and writes its
  output to `state/logs/<instance>.log`, emptied at every start. `rrcd` reads
  the environment URL and the "Capacity: N/32" session count from there.
- The unit templates live in the skill and are linked into
  `~/.config/systemd/user` by the first `rrcd start`, which also enables
  `rrc-update.path`. That watches `~/.local/bin` and
  `~/.local/share/claude/versions` and runs
  `rrcd on-update`, which compares each server's `/proc/<pid>/exe` with what
  `~/.local/bin/claude` points at.
- Two hooks, registered in `settings.json` by their path in the skill, act only
  in `.claude/worktrees/bridge-*`: `SessionStart` detaches the worktree and
  deletes the generated `worktree-bridge-*` branch; a `PreToolUse` guard on
  Bash blocks `git commit` on a detached HEAD. The guard sees only Bash, so a
  commit made another way gets past it.
- The first `rrcd start` also turns linger on (`loginctl enable-linger`), so
  the user's systemd instance, and every server in it, starts at boot and
  keeps running after logout. That applies to all of the user's enabled
  units, not only these. If it can't, it says to run the command yourself.
- `rrcd clone <slug>` needs `CLONE_BASE` in `state/config`, for example
  `CLONE_BASE="git@ssh.bitbucket.org:<workspace>/"`; there is no built-in
  host. `ORCHESTRATOR_TMUX` there names the pane for `[rrcd]` messages,
  `orchestrator:0` by default, and `REPOS_ROOT` the clone root, `~/repos`.
- Everything `rrcd` writes is in the skill's `state/`, which reinstalls keep.

It relies on Claude Code behaviour checked in Docker (`test/docker/confirm.sh`,
results in `DESIGN.md`), any of which an update could change:

- The output format: the `https://claude.ai/code?environment=env_…` line, the
  `Capacity: N/32` line, and the "Workspace not trusted" and "already served"
  errors. If the format changes, `rrcd start` waits two minutes and fails with
  "no URL", and `rrcd list` shows no URL or session count. Servers
  with no count are never restarted by the watcher.
- A server started just after another one in the same folder stopped is
  refused for about 70 seconds and exits. `Restart=always` retries it.
- After about 10 minutes without a network, a server exits with status 0.
  `Restart=always` starts it again; with `Restart=on-failure`, as in 1.0.0,
  it stayed down until the next reboot or `rrcd start`.
- A server killed by a reboot leaves its sessions' worktrees locked to its
  dead PID. `rrcd tidy` runs before every server start: it releases those
  locks, removes the worktrees with no uncommitted changes or commits of
  their own, and keeps the rest. `state/logs/tidy.log` says what it did.
- `SessionStart` runs in a server session's worktree before its first command.
  If that stops, sessions keep their generated branch, and the guard never
  fires because HEAD is never detached.
- `rrcd` must run outside Claude's sandbox, which blocks the user bus,
  `~/.config/systemd/user` and `~/.claude.json`. Each exclusion matches only a
  call that is that command and nothing else: chained with `;` or `&&`,
  redirected, run after a `cd` or by its full path, the call stays sandboxed
  and fails with "Read-only file system".

## Before uninstalling

    rrcd teardown

stops and disables every server and the update watcher, and unlinks
the units. `uninstall.sh` runs it first, before removing anything, and stops
with nothing removed if it fails, so the units never keep running a deleted
skill.

## Tests

    ./test/run-tests.sh

Redirects `HOME` and `CLAUDE_DIR` into a temp directory, so your real config is
never touched. `./test/run-tests.sh` at the repo root runs every package's.
They run anywhere: your own terminal, `!`, or Claude's own Bash tool.

The Docker checks, `test/docker/confirm.sh` and `test/docker/integration.sh`,
say where to run them at the top of each script, and refuse to start in the
wrong place.

## Releasing

`/release repo-remote-control-server` at the repo root — bump `packages/repo-remote-control-server/VERSION` on `main`,
move `release/repo-remote-control-server-vX.x` onto it, tag `repo-remote-control-server-vX.Y.Z` there. The tag is what
publishes it. The release carries what `PAYLOAD` lists, and nothing else in
this directory.
