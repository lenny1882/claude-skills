# flutter-hot-reload-mac

Edit Flutter code here, see it on the iOS simulator on the Mac. Each save is
rsynced to the Mac's checkout, hot reloaded into the running app, and comes
back as a screenshot in the conversation.

Written 25 Aug 2026, out of a session spent doing all of this by hand on
`hugoboss-flutter-runner` while tweaking an inactivity banner.

Part of [claude-skills](https://github.com/lenny1882/claude-skills), which holds several packages
that are each versioned, released and installed on their own.

## Status

Packaged on 24 Sep 2026 from `~/claude-sandbox/flutter-hot-reload-mac`, and not
yet installed from here. The copy in `~/.claude/skills/flutter-hot-reload-mac/`
is a hand copy made before the package existed, and still has the `--flavor`
splice bug that BACKLOG item 15 fixed. `./install.sh` replaces it; there is no
need to delete it first.

No script in `skill/bin/` carries an execute bit — SKILL.md calls them with
`bash`.

## What is in it

| | |
|---|---|
| `skill/SKILL.md` | the config table, the watch-loop protocol Claude follows, and the five things that cost a day |
| `skill/bin/lib.sh` | conf discovery, SSH host picking, simulator resolution |
| `skill/bin/start.sh` | push the branch to the Mac, check it out, sync, launch, wait for the app |
| `skill/bin/watch.sh` | one save → sync → reload → screenshot → exit (`--loop` to stay up) |
| `skill/bin/reload.sh` | `r` / `restart` / `q` by hand |
| `skill/bin/shot.sh` | one screenshot, pulled here |
| `skill/bin/status.sh` | branch on the Mac, whether the run is alive, last reloads |
| `skill/bin/stop.sh` | kill the run, clear its files |
| `skill/remote/frun.py` | the pty supervisor that makes hot reload reachable at all |

## Configuration

There is no config file of its own. `skill/bin/lib.sh` reads the project's
`.maestro-drive.conf` — the same file `maestro-drive` uses — for `MAC_HOST`,
`REPO` and `DEV`. Flutter values (`FLUTTER_BIN`, `FLAVOR`, `TARGET`,
`WATCH_DIR`) default to an fvm-pinned SDK with a flavoured entrypoint and can
be overridden in that file or per call.

## Install

Needs `curl`, `tar` and `jq`. From the newest release:

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
cd /mnt/sda/Development/oi/native/hugoboss-flutter-runner
bash /mnt/sda/Development/github-lenny1882/claude-skills/packages/flutter-hot-reload-mac/skill/bin/status.sh
bash /mnt/sda/Development/github-lenny1882/claude-skills/packages/flutter-hot-reload-mac/skill/bin/start.sh
```

The scripts find the project from `$PWD`, so they work from a source checkout
without being installed.

## Verified

25 Aug 2026, against `mac-home` and the iPhone 16 Pro simulator
(`C61983AE-1974-4ACD-8087-8FD849CF89B1`), on
`unit/HBD20-1788-automated-logout-phase`:

- four saves synced, hot reloaded and screenshotted end to end — 302, 353, 311
  and 338 ms per reload, roughly 4 s from save to image
- all seven shell scripts pass `bash -n`; `frun.py` parses
- `status.sh` read the Mac's branch, saw the run was gone and printed the last
  three reload times

That run used the copy in `~/.claude/skills`. Since then `frun.py` has had the
BACKLOG item 15 fix, and `lib.sh` two fixes made while packaging it: an exported
setting now beats `.maestro-drive.conf`, and `FLAVOR=` now means an unflavoured
build. None of the three has been run against a Mac.

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

## Releasing

`/release flutter-hot-reload-mac` at the repo root — bump `packages/flutter-hot-reload-mac/VERSION` on `main`,
move `release/flutter-hot-reload-mac-vX.x` onto it, tag `flutter-hot-reload-mac-vX.Y.Z` there. The tag is what
publishes it. The release carries what `PAYLOAD` lists, and nothing else in
this directory.
