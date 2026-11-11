# flutter-hot-reload-mac

Edit Flutter code here, see it on the iOS simulator on the Mac. Each save is
rsynced to the Mac's checkout, hot reloaded into the running app, and comes
back as a screenshot in the conversation.

Written 25 Aug 2026, out of a session spent doing all of this by hand on
a client app project while tweaking a status banner.

Part of [claude-skills](https://github.com/lenny1882/claude-skills), which holds several packages
that are each versioned, released and installed on their own.

## Status

2.0, not yet released. Rebuilt on `maestro-drive`, as `rrcd` is built on
`rrc`: `skill/bin/lib.sh` sources `maestro-drive`'s `bin/lib.sh` and keeps only
what is this skill's own. The reasons and the plan are in `V2-PLAN.md`; 1.0's
drift from `maestro-drive` is BACKLOG item 14.

It needs a `maestro-drive` whose `bin/lib.sh` sets
`MAESTRO_DRIVE_LIB_VERSION=1`. That is on `maestro-drive`'s `main` from
`2b6d703` and in no release yet: 2.1.1 and earlier have no library version, and
this refuses them.

No script in `skill/bin/` carries an execute bit — SKILL.md calls them with
`bash`.

## What is in it

| | |
|---|---|
| `skill/SKILL.md` | the settings, what to do when `start.sh` stops, the watch-loop protocol, and the five things that cost a day |
| `skill/bin/lib.sh` | loads `maestro-drive` and checks its library version; this skill's settings, per-device paths, the sync |
| `skill/bin/start.sh` | the guards, then push the branch, check it out, sync, launch, wait for the app |
| `skill/bin/watch.sh` | one save → sync → reload → screenshot → exit (`--loop` to stay up); exits 2 when the run has gone |
| `skill/bin/reload.sh` | `r` / `restart` / `q` by hand |
| `skill/bin/status.sh` | the Mac checkout's branch, and every run: device, checkout, last reloads |
| `skill/bin/stop.sh` | stop this device's run, flutter included, and clear its files |
| `skill/remote/frun.py` | the pty supervisor that makes hot reload reachable at all |

`shot.sh` went in 2.0: `maestro-drive`'s `bin/shot.sh` and `bin/driver.sh shot`
crop, rotate and scale.

## What it uses from maestro-drive

Sourced from `$FHRM_MAESTRO_DRIVE`, or `~/.claude/skills/maestro-drive`, never
`PATH`:

- **Functions** (`MD_USES_FUNCS` in `skill/bin/lib.sh`), covered by the
  library version: `_pick_host`, `_ssh`, `_push`, `_pull`, `_dev`,
  `_label_guard`, `_fs_shared`, `_where`.
- **Variables** (`MD_USES_VARS`), which the library version does not cover:
  `MAESTRO_DRIVE_CONF_FOUND`, `PROJECT_DIR`, `TRANSPORT`, `MAC_HOST`, `REPO`,
  `APP_ID`, `DEV`, `RDIR`, `RMODS`, `LDIR`, `SSH_OPTS`, `PLATFORM_SH`,
  `FRAMEWORK_SH`. `test/run-tests.sh` checks a `maestro-drive` checkout still
  sets each one.
- **Runner modules**, copied to the Mac by `start.sh` from
  `maestro-drive`'s `runners/flutter/` and `runners/<platform>/`:
  `framework.sh describe <repo> <app-id> --env`, `build.sh --detect --env` with
  `--flavor`/`--target` when `BUILD_FLAVOR`/`BUILD_TARGET` are set (`build.sh`
  is that module's own file, not the runner contract), and `platform.sh
  installed-info` and `screenshot`.

## Configuration

There is no config file of its own. The project's `.maestro-drive.conf` is read
by `maestro-drive`'s loader, so it needs what `maestro-drive` needs over ssh —
`MAC_HOST`, `MAC_FQDN`, `APP_ID`, `REPO` — and `PROFILE` and `TRANSPORT` work
here too. This skill adds `WATCH_DIR` (default `lib`). Flavour and entry file
are `maestro-drive`'s `BUILD_FLAVOR` and `BUILD_TARGET`; 1.0's `FLAVOR` and
`TARGET` are read with a warning, and `FLUTTER_BIN` is ignored.

## Install

Needs `curl`, `tar` and `jq`, and `maestro-drive` installed first: the
installer's probe fails without it, or with a library version this was not
written against. From the newest release:

    v=$(curl -fsSL https://raw.githubusercontent.com/lenny1882/claude-skills/versions/versions.txt | awk '$1=="flutter-hot-reload-mac" {print $2}')
    curl -fsSL "https://github.com/lenny1882/claude-skills/releases/download/flutter-hot-reload-mac-v$v/flutter-hot-reload-mac.tar.gz" | tar -xz
    cd flutter-hot-reload-mac && ./install.sh

These lines never change between versions: `versions.txt` names the newest
stable release, and only once its tarball is uploaded. To pin a version,
download `.../releases/download/flutter-hot-reload-mac-vX.Y.Z/flutter-hot-reload-mac.tar.gz` instead.

Or from a clone of the whole repo:

    git clone https://github.com/lenny1882/claude-skills && cd claude-skills/packages/flutter-hot-reload-mac
    ./install.sh              # install
    ./install.sh --link       # or symlink, so edits in the checkout are live
    ./install.sh --dry-run    # show the settings change, write nothing
    ./install.sh --yes        # no prompts

Re-running the installer is safe and is how you upgrade. It replaces whatever
is at `~/.claude/skills/flutter-hot-reload-mac` and keeps no copy of it.

Skills need no `settings.json` entry — Claude Code reads anything under
`skills/` at startup, so restart before using it.

## Trying it from here

```sh
cd ~/Development/client/app
bash ~/claude-skills/packages/flutter-hot-reload-mac/skill/bin/status.sh
bash ~/claude-skills/packages/flutter-hot-reload-mac/skill/bin/start.sh
```

The scripts find the project from `$PWD`, so they work from a source checkout
without being installed.

## Verified

**2.0**, 11 Nov 2026: `test/run-tests.sh`, 84 checks, against a stand-in
`maestro-drive` in local transport and a fake `flutter` — start, the guards
(installed app, another session's label, an undecided flavour, a live 1.0 run,
another run on the same checkout, uncommitted work outside `WATCH_DIR`), one
save through the watcher, reload and restart, two devices at once on two
checkouts, and a stop that leaves the other device's run alone. The last
section checks the real `maestro-drive` `main` sets the library version and
every function and variable listed above. **Not yet run against a Mac.**

**1.0**, 25 Aug 2026, against `my-mac` and the iPhone 16 Pro simulator, on
`unit/ABC-124-session-timeout-phase`: four saves synced, hot reloaded and
screenshotted end to end — 302, 353, 311 and 338 ms per reload, roughly 4 s
from save to image.

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

Logs to `$TMPDIR/flutter-hot-reload-mac-tests.log`. Checks the real
`maestro-drive` at `$MD_SRC` (default: its checkout beside this repo) on
`$MD_REF` (default `main`), and skips that section when there is none.
Redirects `HOME` and `CLAUDE_DIR` into a temp directory, so your real config is
never touched. `./test/run-tests.sh` at the repo root runs every package's.

## Releasing

`/release flutter-hot-reload-mac` at the repo root — bump `packages/flutter-hot-reload-mac/VERSION` on `main`,
move `release/flutter-hot-reload-mac-vX.x` onto it, tag `flutter-hot-reload-mac-vX.Y.Z` there. The tag is what
publishes it. The release carries what `PAYLOAD` lists, and nothing else in
this directory.
