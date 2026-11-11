# flutter-hot-reload-mac 2.0 — rebuilt on maestro-drive

Written 11 Nov 2026. Answers BACKLOG item 14. Reviewed against 1.0.0 in this
repo and `maestro-drive`'s source at `4475adb`
(`/mnt/sda/Development/github-lenny1882/maestro-drive`), which is ahead of the
installed 2.1.1.

---

## 1. What the two share today

- Only `.maestro-drive.conf`. This skill reads `MAC_HOST`, `REPO` and `DEV`
  from `maestro-drive`'s settings, plus `FLUTTER_BIN`, `FLAVOR`, `TARGET` and
  `WATCH_DIR`, which only it reads.
- No script calls the other. One reference runs the other way:
  `maestro-drive`'s `runners/flutter/vmservice.sh` reads this skill's fixed
  `/tmp/frun.log` by name (`FRUN_LOG`).

## 2. Where this skill has fallen behind

1. **Flavour, entry file, SDK.** Hard-coded: `FLUTTER_BIN=.fvm/flutter/bin/flutter`,
   `FLAVOR=dev`, `TARGET=lib/main_dev.dart` (`skill/bin/lib.sh:55-58`).
   `maestro-drive`'s `runners/flutter/build.sh` finds the SDK from eight
   candidates (the pinned one first), the flavour from the Xcode configuration
   that produces `APP_ID`, and the entry file from the flavour. It refuses when
   two flavours produce the same app. A project not flavoured `dev` gets the
   right build from one skill and the wrong one from the other, and nothing
   reports it.
2. **Two key sets in one conf.** `maestro-drive` overrides with `BUILD_FLAVOR`
   and `BUILD_TARGET`; this skill reads `FLAVOR` and `TARGET`. Neither reads
   the other's.
3. **CocoaPods.** `remote/frun.py` always sets `GEM_HOME=~/.gem`.
   `maestro-drive` sets it only when `pod` is missing from the build's PATH,
   because setting it otherwise can break a working install.
4. **Transport.** `maestro-drive` has `TRANSPORT=ssh|local|bridge`. This skill
   knows SSH only; with `TRANSPORT=local` it fails with "MAC_HOST is not set".
5. **SSH.** `maestro-drive`'s `_pick_host` retries a slow Mac with the full
   timeout and lists the other `~/.ssh/config` aliases on failure; its `_ssh`
   bounds every call by `$TMO` and re-picks the host on exit 255 or 124. This
   copy does none of it. `watch.sh`'s `rsync`, `scp` and raw `ssh` calls also
   bypass `_ssh`.
6. **Conf lookup.** Missing the fourth step (the conf this session last found,
   cached in `$LDIR`, for detached scripts started outside the project) and
   `PROFILE=<name>` layering of `.maestro-drive.conf.<name>`.
7. **Several booted simulators.** `maestro-drive`'s `_dev` asks
   `platform.sh devices --booted`, names them all and says to pin `DEV`. This
   skill takes the first UDID from `simctl list` without saying so.
8. **Screenshots.** `maestro-drive`'s `bin/shot.sh` and `bin/driver.sh shot`
   crop, rotate and scale through `img.sh` — this skill's item 12.
9. **Physical devices.** `maestro-drive` has `physical-device.md`,
   `runners/ios-device/` (its own usbmux forwarder in Python) and profile
   builds signed through the GUI session — where this skill's item 19 starts.
10. **Shared checkout and simulator.** `maestro-drive`'s done item 24 names
    this skill's `start.sh`: `git checkout` on the one shared `$REPO` can move
    HEAD off another session's uncommitted work. Its open item 112 plans a
    check refusing a launch onto a simulator another live session has
    labelled, with this `start.sh` as a caller. Together with this skill's
    item 18 (the `pkill` and the fixed `/tmp/frun.*` paths).
11. **Helpers on the Mac.** `maestro-drive` pushes its helpers once to `$RDIR`
    (`/tmp/maestro-mac`) with `bin/install.sh`. This skill copies `frun.py` to
    `/tmp` with `scp` on every start.

### Where this skill is ahead

- Exported values beat the conf even when it uses plain `X=y` lines: it saves
  and restores them around sourcing (`skill/bin/lib.sh:31-45`).
  `maestro-drive` sources the conf directly, so there that only holds for
  `: "${X:=y}"` lines.
- `frun.py`'s pty and keystroke fifo is the only way to send `r`/`R` to a
  running `flutter run`. `maestro-drive`'s recipe starts it detached, with no
  way to send keys.

### What maestro-drive already plans

Its item 93 (open): make this skill consume its Flutter runner verbs —
`describe`, `build`, `inspect` — instead of its own defaults. Gated on its item
87 (open), the framework/platform split. The Flutter module's verbs have all
been run end to end, so they are stable even though 87 isn't closed.

## 3. Why a rebuild rather than fixes

Points 4–7 are fixed by sourcing `maestro-drive`'s `bin/lib.sh`, and 1–3 by
calling its runner. Those replace all of `skill/bin/lib.sh` (113 lines) and the
flavour, SDK and CocoaPods half of `start.sh` and `frun.py`. What is this
skill's own — `frun.py`'s pty and fifo, `watch.sh`, `reload.sh`, `status.sh` —
is about 200 of 473 lines. Fixing point by point is writing 2.0 slowly.

Cost: it can no longer be installed alone; tests need a stubbed
`maestro-drive`; and it should rely only on the verbs verified end to end
(`describe`, `variant-for-appid`, `build`, `inspect`) and the
`config.sh`/`lib.sh` functions.

Not chosen, and not ruled out: folding hot reload into `maestro-drive` as a
runner module (its item 93's end state). That would remove item 16 at the root
but puts building back inside the skill that promises not to build unprompted,
and moves the work out of this repo. 2.0's own code is the part that would
move.

## 4. The plan

### What 2.0 sources

`$CLAUDE_DIR/skills/maestro-drive/bin/lib.sh`, which loads `config.sh` itself.
That brings the conf lookup (with its fourth step and `PROFILE`), the three
transports, `_pick_host`/`_ssh` with retry, re-pick and `$TMO`, `_dev` with the
several-booted warning, `_push`/`_pull`, `$RDIR` and `$RHELP`.

Sourcing runs no remote commands. It does `mkdir -p "$LDIR"`, exports every
`APP_*` value, and exits the caller when the conf is incomplete.

### Files

| 1.0 file | 2.0 |
|---|---|
| `skill/bin/lib.sh` | About 20 lines: find `maestro-drive`, source it, check the version, set this skill's own paths |
| `skill/bin/start.sh` | Rewritten — below |
| `skill/bin/watch.sh` | Kept; raw `ssh`/`scp`/`rsync` move to `_ssh`, `_pull` and one sync function |
| `skill/bin/reload.sh`, `skill/bin/status.sh` | Kept; per-device paths |
| `skill/bin/stop.sh` | Kept; kills the PID its run recorded, not every `flutter run` |
| `skill/bin/shot.sh` | Dropped; `maestro-drive`'s `bin/shot.sh` or `bin/driver.sh shot` |
| `skill/remote/frun.py` | Kept; pipe and log paths from the environment; stops forcing `GEM_HOME` |

### start.sh in 2.0

1. SDK, flavour and entry file from the Mac through
   `runners/flutter/framework.sh` (`describe`, `variant-for-appid`), as
   `bin/build.sh` does. Honours `BUILD_FLAVOR`/`BUILD_TARGET`; sets `GEM_HOME`
   only when `describe` reports `pod` missing; refuses when the flavour can't
   be decided.
2. Sync `WATCH_DIR`: over SSH, `rsync` with the same SSH options; with `local`
   or `bridge` (`_fs_shared`) nothing to sync, since `REPO` is the checkout.
3. Push `frun.py` to `$RHELP` once, not on every start.
4. Start `frun.py` with `$RDIR/frun-$DEV.in` (pipe), `$RDIR/frun-$DEV.log`
   (log) and `$RDIR/frun-$DEV.pid` (PID file).
5. Before launching, run `maestro-drive`'s preflight check that the app is
   installed — item 16's proposed check.

### Config keys

- `FLUTTER_BIN` dropped; `maestro-drive` finds the SDK.
- `FLAVOR` and `TARGET` read for one version, with a warning pointing to
  `BUILD_FLAVOR`/`BUILD_TARGET`, then dropped.
- `WATCH_DIR` stays.
- New: in SSH transport `maestro-drive`'s `config.sh` also requires `MAC_FQDN`
  and `APP_ID`. A conf from its `init.sh` has both.

### Installer and tests

- `manifest.sh` gets a `verify_probe` failing the install when `maestro-drive`
  is missing or at the wrong library version, with the reason — as
  `repo-remote-control-server`'s does.
- Tests point `FHRM_MAESTRO_DRIVE` at a fake `maestro-drive` directory whose
  `lib.sh` stubs `_ssh`, `_dev` and `_push`. The 1.0 tests already stub `ssh`.

### Backlog items

| Item | What it is | Under 2.0 |
|---|---|---|
| 1, 3, 4 | packaging | already done |
| 8 | one simulator only | closed: per-device paths and `_dev` |
| 11 | no `init.sh` for the settings | closed: `maestro-drive`'s `init.sh` |
| 12 | no cropping | closed: `maestro-drive`'s `shot.sh` |
| 14 | review of the drift | closed: this rebuild |
| 17 | empty `FLAVOR` | already fixed |
| 18 | `pkill` kills every run; fixed `/tmp` paths | closed: PID file and per-device paths |
| 19 | physical devices | handed to `maestro-drive`'s `ios-device` runner |
| 2 | `watch.sh` detection untested | carried |
| 5 | no execute bits | carried |
| 6 | saves missed between watcher restarts | carried |
| 7 | only `*.dart` watched | carried |
| 9 | ten-second SSH polls in `start.sh` | carried |
| 10 | nothing notices `flutter run` dying | carried |
| 13 | exception text not read back | carried |
| 16 | wrong skill picked to drive | carried, with the check in step 5 |

### Needed in maestro-drive first

For a session in that repo; nothing has been sent.

1. A library version constant in `bin/lib.sh` (see section 5).
2. A machine-readable `framework.sh describe` — for example `describe --env`
   printing `FLUTTER=…`, `FLAVOR=…`, `TARGET=…`, `GEM_HOME=…`. Today it prints
   a report for people (`flavour    dev — the only one whose…`).
3. `runners/flutter/vmservice.sh` taking the per-device log,
   `$RDIR/frun-$DEV.log`, instead of `/tmp/frun.log`.
4. Its item 112's label check as a function `start.sh` can call.

### Branch handling on the shared `$REPO`

Chosen 11 Nov 2026: **check, then switch.** 1.0 pushes the local branch to
`$REPO` on the Mac, discards `ios/Podfile.lock` and `pubspec.lock`, runs
`git checkout <branch>`, then `rsync --delete`s `WATCH_DIR` over the Mac's
copy — moving HEAD and overwriting `lib/` under any other session using that
checkout (`maestro-drive` item 24).

2.0 keeps the push and checkout, and refuses when:

- another live run is using that `$REPO` — this skill's `$RDIR/frun-*.pid`
  files, or a `maestro-drive` label from another session (its item 112's
  check); or
- anything is uncommitted outside `WATCH_DIR` and the two lock files. Changes
  inside `WATCH_DIR` are expected: this skill's own sync put them there.

Two branches at once means a second `REPO`, through a conf profile — the rule
`maestro-drive` documents in `SKILL.md` ("Reviewing several branches at once").

This goes one step past `maestro-drive`, whose `build.sh` builds whatever is
checked out and never runs `git checkout`. Not chosen: a worktree per branch
created by `start.sh` (each needs its own `pub get`, `pod install` and cold
build, and `maestro-drive` would still read the conf's `REPO`); never touching
the branch (matches `maestro-drive`, but every switch becomes manual and the
sync still overwrites another session's `lib/`); keeping 1.0's behaviour.

## 5. The version check, copied from rrcd

`rrcd` (`packages/repo-remote-control-server/skill/bin/rrcd:41-53`):

1. `NEEDS_LIB=1` — the `rrc-lib.sh` version it was written against.
2. Looks for the library only in the session skill's directory, never `PATH`:
   `RRC_LIB=${RRCD_RRC_LIB:-$CLAUDE_DIR/skills/repo-remote-control-session/lib/rrc-lib.sh}`.
3. Missing file: exits with "needs repo-remote-control-session … install it".
4. Sources it. The file defines things and runs nothing.
5. `RRC_LIB_VERSION` not exactly `NEEDS_LIB`: exits with "update
   repo-remote-control-session and repo-remote-control-server together".
6. `manifest.sh`'s `verify_probe` fails the install for the same reasons, with
   `rrcd`'s message.

`rrc-lib.sh`'s header has the rule: adding a function leaves the version
alone; changing what one takes or does, or removing one, increments it.

For 2.0: `NEEDS_MD_LIB=1`,
`MD_LIB=${FHRM_MAESTRO_DRIVE:-$CLAUDE_DIR/skills/maestro-drive}/bin/lib.sh`,
and a check of `MAESTRO_DRIVE_LIB_VERSION` after sourcing.

Two differences from `rrc`:

- `maestro-drive`'s `lib.sh` is not side-effect free: through `config.sh` it
  exits the caller when the conf is incomplete. Right for 2.0, but the version
  check can't run before the conf check, so `verify_probe` (no project) must
  set `MAESTRO_DRIVE_CONF` to a minimal test conf.
- The constant doesn't exist yet. Until it does, the only check is the
  `VERSION` file in `/mnt/sda/User/Programs/claude-tools/maestro-drive/`,
  which is absent for a `--link` install and ties 2.0 to release numbers
  rather than the library's interface.
