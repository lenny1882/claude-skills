# flutter-hot-reload-mac

Edit Flutter code here, see it on the iOS simulator on the Mac. Each save is
rsynced to the Mac's checkout, hot reloaded into the running app, and comes
back as a screenshot in the conversation.

Written 25 Aug 2026, out of a session spent doing all of this by hand on
a client app project while tweaking a status banner.

Part of [claude-skills](https://github.com/lenny1882/claude-skills), which holds several packages
that are each versioned, released and installed on their own.

## Status

2.0.0, released 12 Nov 2026. Rebuilt on `maestro-drive`, as `rrcd` is built on
`rrc`: `skill/bin/lib.sh` sources `maestro-drive`'s `bin/lib.sh` and keeps only
what is this skill's own. The reasons and the plan are in `V2-PLAN.md`; 1.0's
drift from `maestro-drive` is BACKLOG item 14.

It needs a `maestro-drive` whose `bin/lib.sh` sets
`MAESTRO_DRIVE_LIB_VERSION=1`. That is `maestro-drive` 2.2.0 and later;
2.1.1 and earlier have no library version, and this refuses them. A physical
iPhone (`PLATFORM=ios-device`) needs `maestro-drive` 2.3.0 or later, which has
its phone commands; `start.sh` refuses a phone with an older one.

The scripts in `skill/bin/` carry an execute bit since 2.1 (BACKLOG item 5);
SKILL.md still calls them with `bash`.

## What is in it

| | |
|---|---|
| `skill/SKILL.md` | the settings, what to do when `start.sh` stops, the watch-loop protocol, and the five things that cost a day |
| `skill/bin/lib.sh` | loads `maestro-drive` and checks its library version; this skill's settings, per-device paths, the sync |
| `skill/bin/start.sh` | the guards, then push the branch, check it out, sync, launch, wait for the app |
| `skill/bin/watch.sh` | one save → sync → reload (restart for an asset) → screenshot → exit (`--loop` to stay up); a save made between two runs is handled by the next; exits 4 listing changes only a rebuild applies, 2 when the run has gone |
| `skill/bin/reload.sh` | `r` / `restart` / `q` by hand; shows flutter's answer and any error the key threw |
| `skill/bin/status.sh` | the Mac checkout's branch, and every run: device, checkout, last reloads |
| `skill/bin/logs.sh` | a phone only: the app's `flutter: ` lines from the phone's syslog, through `maestro-drive`'s `logs`, to a file, for a set time |
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
`MAC_HOST`, `MAC_FQDN`, `APP_ID`, `REPO` — and `PROFILE` and `TRANSPORT` are read
here too. This skill adds `WATCH_DIR` (default `lib`), `WATCH_ASSETS` (default `assets`)
and `WATCH_REBUILD` (default `pubspec.yaml ios android`). Flavour and entry file
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

**2.0**, 11 Nov 2026, against mac-office and the iPhone 16 Pro simulator
(`C61983AE-1974-4ACD-8087-8FD849CF89B1`), from the hugoboss-flutter-runner
project on `unit/HBD20-1770-idcloud-search-deeplink-quick`, with
`maestro-drive` 2.2.0 installed:

- `start.sh --build` pushed the branch, moved the Mac checkout onto it from
  `feature/pre-peak-release`, synced `lib/` and launched; `describe --env`
  gave `dev` and `lib/main_dev.dart`, what 1.0 used by default
- `reload.sh` 161 ms; `reload.sh restart` 438 ms; `status.sh` named the
  device, the checkout and the branch, under the Mac's zsh
- one save through `watch.sh`: synced, reloaded 1 of 2604 libraries in
  345 ms, screenshot fetched, exit 0
- `stop.sh` stopped frun.py and flutter, nothing left running; a second stop
  said nothing was running

Two faults found there and fixed: a restart on the branch the Mac already has
checked out failed at the push (`receive.denyCurrentBranch` is unset there, so
git refuses), and zsh printed "no such file or directory" for a PID file not
yet written. `test/run-tests.sh`, 86 checks, covers both, against a stand-in
`maestro-drive` in local transport and a fake `flutter`, plus checks that the
real `maestro-drive` `main` sets the library version and every function and
variable listed above. Then, the same day and Mac:

- **The guards**, 6 of 6: `start.sh --build` refused, with the expected
  message and before any build, for another session's label on the device
  today, another live run on the same checkout (a pid file pointing at a live
  process), a live 1.0 run (a process named `/tmp/frun.py`), an uncommitted
  `README.md` in the Mac checkout, and a commit made on the Mac. Each set-up
  was undone and nothing was left behind.
- **Two devices at once**, 6 of 6: the iPhone 16 Pro on the project's
  checkout (up in 43 s) and an iPhone 16 (`CCF89EAD-…`) on a second checkout
  cloned to `/tmp/fhrm-second-checkout` (cold build, up in 81 s), with `REPO`
  and `DEV` exported. `status.sh` showed both alive, each from its own
  checkout; each reloaded through its own fifo (220 and 171 ms); stopping the
  first left the second running. Cleaned up after: both stopped, the clone
  deleted, the iPhone 16 shut down.
- **The rest**, 5 of 5, from a clone of the project in the scratchpad: a new
  local commit fast-forwarded the branch the Mac had checked out, and the app
  came up; one save through `watch.sh` after `c3ee011` changed its PID-file
  read (346 ms reload, screenshot); `watch.sh` exited 2 with the end of the log
  when the run was stopped under it; a `PROFILE` overlay's values reached this
  skill, and a missing profile stopped it. The Mac's branch was reset to where
  it was.

**Android on this machine, 12 Nov 2026**, `TRANSPORT=bridge` from inside the
sandbox and `TRANSPORT=local` from a terminal, each 10 of 10: a `flutter
create` app on the `Pixel_6_Pro_API_34` emulator came up without `--build`
(43 s over the bridge, 53 s local), `describe` decided unflavoured and
`lib/main.dart`, reload (162 and 164 ms), restart (1,237 and 1,206 ms), status,
one save through `watch.sh` with a screenshot, and stop. The first Gradle
build there needs the disk to itself: beside a cold-booting emulator on the
same spinning disk it took over 25 minutes, alone 90 s. The bridge needs
`maestro-drive` 2.2.1 or later; 2.2.0 let any session's end stop another
session's bridge.

**Mac again, 12 Nov 2026**, against mac-home after `reload.sh` and `watch.sh`
began waiting for flutter's answer: `mac-remaining.sh` 7 of 7 — the
fast-forward, a reload (181 ms) and a hot restart (387 ms) each showing only
its own line, one watcher save with a screenshot, the watcher's exit 2, and
`PROFILE` — and `mac-two-devices.sh` 6 of 6, reloads of 205 and 150 ms. The
Android check over the bridge ran once more on `maestro-drive` 2.2.1, 10 of 10,
the helper recording this session as its owner.

**Errors and a dead run, 12 Nov 2026** (BACKLOG items 10 and 13, on `main`,
not released), against mac-home and the iPhone 16 Pro simulator:
`mac-errors.sh` 9 of 9 on its third run. A save that throws in a build
showed its reload line (419 ms), then flutter's `EXCEPTION CAUGHT BY WIDGETS
LIBRARY` header, the exception's text and its stack; a save that does not
compile answered in 5 s with the error, the source line and the caret; the
next clean save showed no error; flutter killed with no save made the
watcher exit 2 two seconds later. The first two runs found three faults in
how the log is cleaned, all fixed (BACKLOG item 13). After those fixes, on
the same code: `mac-guards.sh` 6 of 6, `mac-two-devices.sh` 6 of 6 (reloads
of 165 and 154 ms), `mac-remaining.sh` 7 of 7 (reload 162 ms, restart 396 ms,
a watcher save 310 ms), and on this machine `android-bridge.sh` with
`TRANSPORT=local` 10 of 10 (reload 155 ms, restart 3.2 s, a watcher save
522 ms).

**Items 5, 6, 7 and 9, 12 Nov 2026** (on `main`, not released), against
mac-home and the iPhone 16 Pro simulator, and on this machine against the
`Pixel_6_Pro_API_34` emulator over the bridge: `mac-remaining.sh` 11 of 11
(up after 27 s; a save made between two watcher runs handled 4 s after the next
started; an asset rsynced and hot restarted in 465 ms; a `pubspec.yaml` save
exiting 4 with the Mac's copy untouched), `mac-errors.sh` 9 of 9,
`mac-guards.sh` 6 of 6, `mac-two-devices.sh` 6 of 6 (reloads of 135 and
148 ms), and `android-bridge.sh` 15 of 15 (up after 62 s; the gap save in 3 s;
a red asset replaced by a blue one, hot restarted, the screenshot showing
blue). The first Mac run found one fault in `watch.sh`, fixed: a file put back
to `HEAD` with `git checkout` was listed as a REBUILD.

**On a phone, 12 Nov 2026** (BACKLOG item 21, on `main`, not released), against
hz's iPhone (iPhone 11, iOS 26.5.2) on mac-home, with `maestro-drive`'s `main`:
`mac-phone.sh` 9 of 9 — `maestro-drive`'s signed debug build and install, up
33 s after it, a reload 888 ms, a hot restart 2.8 s, a watcher save reloaded in
254 ms with the phone's screenshot, 11 `flutter:` lines from `logs.sh` in 20 s.

The scripts behind every check above are in `test/manual/`.

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
