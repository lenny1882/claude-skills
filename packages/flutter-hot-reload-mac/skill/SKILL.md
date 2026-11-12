---
name: flutter-hot-reload-mac
description: "BUILD and run this Flutter app from source on the remote Mac's iOS simulator, syncing local code edits via hot reload — every save pushes, reloads, and returns a screenshot. Use when the user wants to build, launch from source, iterate on code changes, or 'watch my changes'. NOT for driving, testing, or interacting with the app UI — tapping, typing, navigating, reproducing bugs, or 'drive the app' — that is maestro-drive. Works in any project; needs maestro-drive installed, and reads the same .maestro-drive.conf."
allowed-tools:
  - Bash
  - Read
  - Write
  - SendUserFile
  - TaskStop
---

# Flutter hot reload on a remote Mac

The code is edited here. The build, the simulator and the app all live on the
Mac. This skill keeps the two in step: save a file, and about four seconds
later the change is on the simulator and a screenshot of it is in the
conversation.

It is built on `maestro-drive`, which must be installed: `bin/lib.sh` sources
its `bin/lib.sh` and refuses any library version but the one it was written
against. So the conf, the transport, picking the Mac alias, ssh and which
simulator are all `maestro-drive`'s, from the project's `.maestro-drive.conf`
(`MAC_HOST`, `MAC_FQDN`, `REPO`, `APP_ID`, `DEV`, `PROFILE`, `TRANSPORT`). The
SDK, the flavour and the entry file come from `maestro-drive`'s Flutter runner,
which works them out from the checkout and `APP_ID` and refuses when it cannot.

This skill's own settings, in the same conf or exported for one call:

| variable | default | |
|---|---|---|
| `WATCH_DIR` | `lib` | synced and watched, relative to both checkouts; a save there is hot reloaded |
| `WATCH_ASSETS` | `assets` | also synced and watched; a save there is hot restarted, since a reload keeps the old image cached. Space-separated, empty for none |
| `WATCH_REBUILD` | `pubspec.yaml ios android` | watched, never synced: no reload applies a change there (see the watch loop) |
| `BUILD_FLAVOR` | worked out | `maestro-drive`'s own override, read by both skills |
| `BUILD_TARGET` | worked out | the same |
| `WATCH_ALIVE` | `30` | seconds between the watcher's checks that the run is alive; `0` for none |
| `RELOAD_TMO` | `60` | seconds to wait for flutter's answer to a key |
| `RELOAD_SETTLE` | `1` | seconds to wait after the answer, for what the first frame throws |
| `RELOAD_ERR_LINES` | `40` | lines of an error to show; the rest stay in the log |
| `START_WAIT` | `600` | seconds `start.sh` waits for the app to come up |
| `LLDB_GRACE` | `180` | phone: seconds after "LLDB is taking longer" before the wait gives up |
| `DEVICE_BUILD_TIMEOUT` | `1200` | phone: seconds for `maestro-drive`'s signed build |
| `LOGS_FOR` | `600` | phone: seconds `logs.sh` streams when given no number |

1.0's `FLAVOR` and `TARGET` are still read, with a warning to rename them;
`FLUTTER_BIN` is ignored.

## Running it

```sh
bash $SKILL/bin/start.sh     # push branch, sync, launch, wait for the app
bash $SKILL/bin/status.sh    # every run on the Mac: device, checkout, last reloads
bash $SKILL/bin/reload.sh    # r by hand; `restart` for R
bash $SKILL/bin/stop.sh      # stop this device's run, and only that
bash $SKILL/bin/logs.sh      # a phone only: the app's own output, to a file
```

`DEV=<udid>` before any of them picks the device; without it, `maestro-drive`
picks the first booted one and says so when there is more than one. Each
device has its own run, fifo and log (`$RDIR/frun-<udid>.*`), so two simulators
can each have one. A screenshot by hand is `maestro-drive`'s
`bin/driver.sh shot` or `bin/shot.sh`.

Call them with `bash`, as above. Since 2.1 the scripts carry an execute bit, but
`bash <script>` works whether or not the installed copy has one.
`remote/frun.py` is run as `python3 frun.py`.

### When start.sh stops

- **Exit 3, the app is already installed.** This skill builds from source. If
  the user asked to drive, tap, test or reproduce something, that is
  `maestro-drive` — use it and do not rebuild. Only if they asked to build from
  source, launch from source, or watch their edits, run `start.sh --build`.
- **Another session's label on the device**, or **another live run using the
  same `REPO`**: launching would replace the app or move the checkout under
  someone else's work. Tell the user which; do not pass `LABEL_GUARD=off`
  unless they have checked with that session. A second branch at the same time
  needs a second checkout: `REPO` in a `.maestro-drive.conf.<name>` profile,
  run with `PROFILE=<name>`.
- **Uncommitted changes in the Mac's checkout** outside `WATCH_DIR`,
  `WATCH_ASSETS` and the two lock files, when the branch would change: they are someone's work. Report
  them; `--no-branch` builds the branch that is there as it is.
- **The flavour cannot be decided**: `maestro-drive`'s reason is printed. Ask
  which flavour, and set `BUILD_FLAVOR`.

`start.sh` pushes the current branch **to** the Mac's checkout and checks it
out there, discarding `Podfile.lock` and `pubspec.lock` first — they are build
output on that machine and block the checkout every time. The push goes to
`refs/remotes/fhrm/<branch>` there and the branch is fast-forwarded to it, since
git refuses a push to the branch a checkout has checked out. If the branch there
has a commit this checkout does not — rewritten here, or committed to there —
`start.sh` refuses rather than overwrite it; report that. Never `git push`
**from** the Mac. `--no-branch` skips all of that and syncs the working tree
onto whatever branch is already there.

A cold build of a branch the Mac has not seen takes a few minutes; after that,
relaunching is about 40 seconds and a reload about 350 ms.

## On a physical iPhone

`PLATFORM=ios-device` in the conf (or exported) and `DEV=<the phone's udid>`.
It needs a `maestro-drive` with its phone commands (`device-check`,
`run-diagnose`, `logs`, `build --mode debug`); `start.sh` says so if the
installed one lacks them. The phone must be plugged into the Mac, trusted,
in Developer Mode, and listed in the provisioning profile of the flavour being
built.

`start.sh` then:
1. runs `maestro-drive`'s `device-check`: no Rosetta, and Flutter's x86_64
   `iproxy` would kill the run after the install. It stops with the command to
   install Rosetta, which needs an administrator on the Mac. Pass that on.
2. has `maestro-drive` build a signed debug app in the Mac's GUI session, since
   `codesign` fails over ssh, and installs it;
3. runs `flutter run --use-application-binary` on that app;
4. prints `>>> ... must be UNLOCKED now`. **Tell the user at once**, while the
   launch is waiting, not after it gives up.
5. If the run does not come up — Flutter's `iproxy` failing, the VM Service
   never found, or LLDB still "taking longer" after `LLDB_GRACE` — it prints
   `maestro-drive`'s `run-diagnose`, which names the cause. Pass that on.

Reload, restart, the watcher and its screenshots work as on a simulator. The
app's own `print`/`debugPrint` output is not in the run's log on a phone:
`bash $SKILL/bin/logs.sh [seconds]` with `run_in_background: true` streams it
into `logs-<udid>.log` (it prints the path) for that long, then stops.

## The watch loop — how Claude drives it

`bin/watch.sh` handles **one** save and exits. That is deliberate: a background
Bash task only notifies Claude when it exits, and that notification is the only
thing that lets Claude put the screenshot in front of the user. So the cycle is:

1. `bash $SKILL/bin/watch.sh` with `run_in_background: true`.
2. On the task notification, `cat` the output file. It ends with `SHOT: <path>`
   and the reload line from the Mac's log. When the reload threw or did not
   compile, an `error from this key:` block follows the reload line: put the
   error in front of the user with the screenshot, as the result of that save.
3. `SendUserFile` that path, captioned with the reload time.
4. Relaunch `bin/watch.sh` in the background immediately.

If it exits 4, a file under `WATCH_REBUILD` changed — `pubspec.yaml`, or native
code under `ios/` or `android/`. The output lists each as `REBUILD: <path>`,
after the reload and screenshot if code changed in the same save. It was not
synced. Tell the user the change needs a rebuild: once it is committed,
`start.sh --build` builds with it. Do not run that unasked; relaunch the
watcher as usual.

If it exits 2, the run has gone — `flutter run` died or was stopped — and the
output ends with the last of its log. The watcher checks every `WATCH_ALIVE`
seconds between saves as well as before each reload, so this can arrive with
no save behind it. Say so, and do not relaunch the watcher
until `start.sh` has brought the run back.

A save made between steps 3 and 4 is not missed: the next run handles it as
soon as it starts. `--loop` never exits and never surfaces anything — only
useful when nobody is watching the conversation.

## What cost time the first day, so it does not cost it again

- **`flutter run` over SSH ignores piped stdin.** The app launches and works,
  but `r` never reloads and nothing in the log says why. It needs a real pty —
  hence `remote/frun.py`. macOS `script(1)` cannot supply one: it wants a tty on
  its own stdin and dies with `tcgetattr/ioctl: Operation not supported on
  socket`.
- **`tmux` is not on the Mac**, so the obvious "send keys to a session" route
  is not available. The fifo at `$RDIR/frun-<udid>.in` replaces it; it is opened
  `O_RDWR` so it never sees EOF between writers.
- **SSH `ControlMaster` fails in this sandbox** — `muxclient socket():
  Operation not permitted`. Every call pays a fresh ~0.4 s connect, which is
  why the watcher detects changes with a local `find -newer` and only reaches
  the Mac when something actually changed.
- **A backgrounded process does not survive its Bash call.** Each call is its
  own PID namespace, so `nohup … &` here dies immediately; only
  `run_in_background: true` persists. On the Mac, `nohup` is fine.
- **`xcrun simctl io … screenshot`** will not write to `-` or `/dev/stdout`. It
  writes a file, which `maestro-drive`'s `_pull` brings back.

## Mirroring the simulator here — don't

Asked, investigated, dead end. Simulator.app is a Cocoa app, so X11 forwarding
carries nothing; XQuartz only forwards X11 clients. macOS Screen Sharing is
live on port 5900 (security types `[30, 33, 36, 31, 32, 2, 35]` — 30 is Apple
Remote Desktop auth, 2 is standard VNC), but no VNC client is installed here
and `sudo` needs a password, and VNC serves the **whole desktop** — there is no
single-window mirroring on macOS. James's call on 25 Aug 2026: if it cannot be
one app, he would rather not. Screenshot-per-save is the answer instead.
