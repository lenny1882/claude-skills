# repo-remote-control-session

Opens one Claude Remote Control session in any repo on this machine, as a
detached process, so it can be picked up from claude.ai or the Claude app.

`claude remote-control --spawn session` only opens a session in the directory
it was started in, has to outlive the shell that started it, needs the repo
trusted in `~/.claude.json` first, and prints its URL inside a redrawing
status screen. Claude can't do any of that from its own Bash tool: the
sandbox blocks `~/.claude.json`, and ends every process a call started when
the call ends. `rrc session` does it in one call, and the installer lets
that call out of the sandbox.

For servers that survive reboots and serve every session in a repo, install
[`repo-remote-control-server`](../repo-remote-control-server/) as well. It
builds on this package.

Part of [claude-skills](https://github.com/lenny1882/claude-skills), which holds several packages
that are each versioned, released and installed on their own.

## What you actually see

Ask Claude to open a session in a repo, or run it yourself:

    $ rrc session ~/repos/client_acme/shop --name "fix the login page"
    /home/me/repos/client_acme/shop
    https://claude.ai/code/session_01EXAMPLE2
    one session: it ends when the conversation does, and never comes back at boot

    $ rrc list
    /home/me/repos/client_acme/shop
      one session, running
      https://claude.ai/code/session_01EXAMPLE2

Open the URL. The session ends when the conversation does; nothing comes
back at boot.

## Install

Needs `curl`, `tar` and `jq`. From the newest release:

    v=$(curl -fsSL https://raw.githubusercontent.com/lenny1882/claude-skills/versions/versions.txt | awk '$1=="repo-remote-control-session" {print $2}')
    curl -fsSL "https://github.com/lenny1882/claude-skills/releases/download/repo-remote-control-session-v$v/repo-remote-control-session.tar.gz" | tar -xz
    cd repo-remote-control-session && ./install.sh

These lines never change between versions: `versions.txt` names the newest
stable release, and only once its tarball is uploaded. To pin a version,
download `.../releases/download/repo-remote-control-session-vX.Y.Z/repo-remote-control-session.tar.gz` instead.

Or from a clone of the whole repo:

    git clone https://github.com/lenny1882/claude-skills && cd claude-skills/packages/repo-remote-control-session
    ./install.sh              # install
    ./install.sh --link       # or symlink, so edits in the checkout are live
    ./install.sh --dry-run    # show the settings change, write nothing
    ./install.sh --yes        # no prompts

Re-running the installer is safe and is how you upgrade. It merges into
`settings.json` rather than replacing it, backs the file up first, and only ever
touches its own entries. If Claude Code is already running, `/hooks` forces a
settings reload.

The one settings entry is `"rrc *"` in `sandbox.excludedCommands`, added next
to whatever is there. The rest of `sandbox` is left as it is.

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

Uninstalling stops every running session and takes
`"rrc *"` out of `sandbox.excludedCommands`, unless `--keep-settings` is
given. A stale entry would let any later program called `rrc` run outside
the sandbox.

## How it works

- `rrc session` finds the repo root, sets
  `projects["<root>"].hasTrustDialogAccepted` in `~/.claude.json` (backed up,
  written through a temp file and `mv`), and starts
  `claude remote-control --spawn session` in the root with `setsid nohup`: in
  a session of its own, with no terminal, so it keeps running after `rrc`,
  the Bash call that ran it, that Claude Code and an SSH logout. Its output
  goes to `state/logs/<instance>.session.log`, emptied at every start, and
  its PID to `state/sessions/<instance>.pid`, the instance being the root
  escaped with `systemd-escape --path`. `rrc` reads the session URL from the
  output.
- A PID file counts only while its PID is a `remote-control` process running
  in that root, so a PID the system has since reused is never listed or
  killed. Nothing restarts a session, and a reboot ends it.
- Before a start, `rrc` deletes `~/.claude/projects/<folder>/bridge-pointer.json`
  when no live process holds it. `claude` keeps the folder's last session
  there, and the next start resumes it; once that session was ended in the
  app, the resume fails with a 404 and the process stays up holding the
  folder.
- Up to 1.0.0 each session was a systemd unit, `rrc-session@.service`. On
  systemd 245 (Ubuntu 20.04) it never started: `StandardOutput=truncate:`
  needs 248, and the unit's `%i.env` was not found for a path with a hyphen
  in it. `rrc teardown` stops and unlinks one left from 1.0.0.
- Everything `rrc` writes is in the skill's `state/`, which reinstalls keep.
- The code for finding the repo, trust, the lock and reading the output is in
  `skill/lib/rrc-lib.sh`. `rrc` sources it, and so does `rrcd`, from
  `repo-remote-control-server`, which loads it from this skill's directory
  and checks its `RRC_LIB_VERSION`. Loading it only defines functions.

It relies on Claude Code behaviour checked in Docker (see
`repo-remote-control-server`'s `DESIGN.md`), any of which an update could
change:

- The output format: the `https://claude.ai/code/session_…` line, and the
  "Workspace not trusted" and "already served" errors. A folder is refused
  as "already served" for up to about 3 minutes after its last session stops
  (131 to 194 seconds in Docker, 2 Nov); `rrc session` stops the refused
  process and tries again every 15 seconds for up to 5 minutes. If the format changes,
  `rrc session` waits two minutes and fails with "no URL".
- `claude` resumes a folder's last session from
  `~/.claude/projects/<folder>/bridge-pointer.json`, a file of its own with
  no documentation. If it moves, a second session in a repo fails again.
- Claude refuses a single session in a folder that already has a server.
  `rrc session` checks for `rrc-server@<instance>.service` first and hands out
  the server's URL from `rrcd url`.
- The sandbox exclusion matches only a call that is `rrc …` and nothing else.
  Chained with `;` or `&&`, redirected, run after a `cd` or by its full path,
  the call stays sandboxed and fails with "Read-only file system".

## Before uninstalling

    rrc teardown

stops every session. `uninstall.sh` runs it first, before removing anything.

## Tests

    ./test/run-tests.sh

Redirects `HOME` and `CLAUDE_DIR` into a temp directory, so your real config is
never touched. `./test/run-tests.sh` at the repo root runs every package's.
They run anywhere: your own terminal, `!`, or Claude's own Bash tool.

## Releasing

`/release repo-remote-control-session` at the repo root — bump `packages/repo-remote-control-session/VERSION` on `main`,
move `release/repo-remote-control-session-vX.x` onto it, tag `repo-remote-control-session-vX.Y.Z` there. The tag is what
publishes it. The release carries what `PAYLOAD` lists, and nothing else in
this directory.
