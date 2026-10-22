# repo-remote-control

Runs one Claude Remote Control server per repo on an always-on Linux box, as
systemd user services, so any repo there can be opened from claude.ai or the
Claude app without SSHing in.

`claude remote-control` only opens sessions in the directory it was started
in, so reaching twenty repos means twenty servers. Each one has to survive
reboots, be trusted in `~/.claude.json`, and be restarted when `claude`
updates, without ending sessions someone is in the middle of. Its URL changes
on every restart and is buried in a redrawing status screen, and the app
names environments after the folder, so two repos called `web` look the same.

Part of [claude-skills](https://github.com/lenny1882/claude-skills), which holds several packages
that are each versioned, released and installed on their own.

## What you actually see

On the box, over SSH or from the orchestrator Claude session through the
skill:

    $ rrc clone shop client_acme
    /home/james/repos/client_acme/shop
    https://claude.ai/code?environment=env_01RC4TRVy72Uh3ogRs7kFsSG

    $ rrc list
    /home/james/repos/client_acme/shop
      active, enabled, sessions 1/32
      https://claude.ai/code?environment=env_01RC4TRVy72Uh3ogRs7kFsSG

Open the URL and start a session: it gets its own git worktree, starts with no
branch, and is told to create one named `<type>/<KEY>-<description>` before it
changes anything. Committing before that is blocked.

When `claude` updates, idle servers restart on their own. If a server has
sessions open, the orchestrator asks you which to restart.

`rrc session <dir>` opens one session instead of a server. It ends when the
conversation does and never comes back at boot.

## Install

Needs `curl`, `tar` and `jq`. From the newest release:

    v=$(curl -fsSL https://raw.githubusercontent.com/lenny1882/claude-skills/versions/versions.txt | awk '$1=="repo-remote-control" {print $2}')
    curl -fsSL "https://github.com/lenny1882/claude-skills/releases/download/repo-remote-control-v$v/repo-remote-control.tar.gz" | tar -xz
    cd repo-remote-control && ./install.sh

These lines never change between versions: `versions.txt` names the newest
stable release, and only once its tarball is uploaded. To pin a version,
download `.../releases/download/repo-remote-control-vX.Y.Z/repo-remote-control.tar.gz` instead.

Or from a clone of the whole repo:

    git clone https://github.com/lenny1882/claude-skills && cd claude-skills/packages/repo-remote-control
    ./install.sh              # install
    ./install.sh --link       # or symlink, so edits in the checkout are live
    ./install.sh --dry-run    # show the settings change, write nothing
    ./install.sh --yes        # no prompts

Re-running the installer is safe and is how you upgrade. It merges into
`settings.json` rather than replacing it, backs the file up first, and only ever
touches its own entries. If Claude Code is already running, `/hooks` forces a
settings reload.

Run the installer in your own terminal or with `!` in Claude Code. Claude's own
Bash tool can't: its sandbox blocks writes to `~/.claude/skills` and
`~/.local/bin`.

## Update

    ./update.sh            check, ask, upgrade, reinstall
    ./update.sh --check    report what is available and stop

Reads this package's line in `versions.txt`, so pre-releases, and releases of
the other packages in the repo, are never offered. Works from a downloaded
tarball as well as a clone — no git needed.

## Uninstall

    ./uninstall.sh                 ask before editing settings.json
    ./uninstall.sh --keep-settings leave settings.json alone

## How it works

- `rrc start` finds the repo root, sets
  `projects["<root>"].hasTrustDialogAccepted` in `~/.claude.json` (backed up,
  written through a temp file and `mv`), writes the repo's flags to
  `state/repos/<instance>.env`, and starts `rrc-server@<instance>.service`, the
  instance being the root escaped with `systemd-escape --path`. The unit runs
  `claude remote-control --spawn worktree` with those flags and writes its
  output to `state/logs/<instance>.log`, emptied at every start. `rrc` reads
  the environment URL and the "Capacity: N/32" session count from there.
- The unit templates live in the skill and are linked into
  `~/.config/systemd/user` by the first `rrc start`, which also enables
  `rrc-update.path`. That watches `~/.local/bin` and
  `~/.local/share/claude/versions` and runs
  `rrc on-update`, which compares each server's `/proc/<pid>/exe` with what
  `~/.local/bin/claude` points at.
- Two hooks, registered in `settings.json` by their path in the skill, act only
  in `.claude/worktrees/bridge-*`: `SessionStart` detaches the worktree and
  deletes the generated `worktree-bridge-*` branch; a `PreToolUse` guard on
  Bash blocks `git commit` on a detached HEAD. The guard sees only Bash, so a
  commit made another way gets past it.
- Everything `rrc` writes is in the skill's `state/`, which reinstalls keep.

It relies on Claude Code behaviour checked in Docker (`test/docker/confirm.sh`,
results in `DESIGN.md`), any of which an update could change:

- The output format: the `https://claude.ai/code?environment=env_…` line, the
  `Capacity: N/32` line, and the "Workspace not trusted" and "already served"
  errors. If the format changes, `rrc start` waits two minutes and fails with
  "no environment URL", and `rrc list` shows no URL or session count. Servers
  with no count are never restarted by the watcher.
- A server started just after another one in the same folder stopped is
  refused for about 70 seconds and exits. `Restart=on-failure` retries it only
  if it exits with an error; `confirm.sh refused-exit` checks that, and has not
  been run yet.
- `SessionStart` runs in a server session's worktree before its first command.
  If that stops, sessions keep their generated branch, and the guard never
  fires because HEAD is never detached.
- `rrc` must run outside Claude's sandbox, which blocks the user bus,
  `~/.config/systemd/user` and `~/.claude.json`: `setup.sh` on the box lists it
  in `sandbox.excludedCommands`.

## Before uninstalling

    rrc teardown

stops and disables every server, session and the update watcher, and unlinks
the units. The kit's `uninstall.sh` does not do this yet, so without it the
units keep running a deleted skill.

## Tests

    ./test/run-tests.sh

Redirects `HOME` and `CLAUDE_DIR` into a temp directory, so your real config is
never touched. `./test/run-tests.sh` at the repo root runs every package's.
They run anywhere: your own terminal, `!`, or Claude's own Bash tool.

The Docker checks, `test/docker/confirm.sh` and `test/docker/integration.sh`,
say where to run them at the top of each script, and refuse to start in the
wrong place.

## Releasing

`/release repo-remote-control` at the repo root — bump `packages/repo-remote-control/VERSION` on `main`,
move `release/repo-remote-control-vX.x` onto it, tag `repo-remote-control-vX.Y.Z` there. The tag is what
publishes it. The release carries what `PAYLOAD` lists, and nothing else in
this directory.
