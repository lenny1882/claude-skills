---
name: flutter-hot-reload-mac
description: "BUILD and run this Flutter app from source on the remote Mac's iOS simulator, syncing local code edits via hot reload — every save pushes, reloads, and returns a screenshot. Use when the user wants to build, launch from source, iterate on code changes, or 'watch my changes'. NOT for driving, testing, or interacting with the app UI — tapping, typing, navigating, reproducing bugs, or 'drive the app' — that is maestro-drive. Works in any project; settings come from the same .maestro-drive.conf as maestro-drive."
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

Nothing is installed on either machine. `.maestro-drive.conf` supplies the Mac,
the simulator UDID and the checkout path — the same file `maestro-drive`
reads. Flutter-specific values default to an fvm-pinned SDK and a flavoured
entrypoint and can be overridden per project or per call:

| variable | default | |
|---|---|---|
| `FLUTTER_BIN` | `.fvm/flutter/bin/flutter` | relative to `REPO`, or absolute |
| `FLAVOR` | `dev` | empty for an unflavoured build |
| `TARGET` | `lib/main_dev.dart` | |
| `WATCH_DIR` | `lib` | synced and watched |

## Running it

```sh
bash $SKILL/bin/start.sh     # push branch, sync, launch, wait for the app
bash $SKILL/bin/status.sh    # what is running, last reload
bash $SKILL/bin/reload.sh    # r by hand; `restart` for R
bash $SKILL/bin/shot.sh      # one screenshot, prints the local path
bash $SKILL/bin/stop.sh      # kill the run on the Mac
```

Call them with `bash`: the sandbox mounts `~/.claude/skills` read-only, so the
scripts were written without an execute bit and `chmod` cannot add one from
here. `remote/frun.py` does not need one — it is run as `python3 frun.py`.

`start.sh` pushes the current branch **to** the Mac's checkout and checks it
out there, discarding `Podfile.lock` and `pubspec.lock` first — they are build
output on that machine and block the checkout every time. Never `git push`
**from** the Mac. `--no-branch` skips all of that and syncs the working tree
onto whatever branch is already there.

A cold build of a branch the Mac has not seen takes a few minutes; after that,
relaunching is about 40 seconds and a reload about 350 ms.

## The watch loop — how Claude drives it

`bin/watch.sh` handles **one** save and exits. That is deliberate: a background
Bash task only notifies Claude when it exits, and that notification is the only
thing that lets Claude put the screenshot in front of the user. So the cycle is:

1. `bash $SKILL/bin/watch.sh` with `run_in_background: true`.
2. On the task notification, `cat` the output file. It ends with `SHOT: <path>`
   and the reload line from the Mac's log.
3. `SendUserFile` that path, captioned with the reload time.
4. Relaunch `bin/watch.sh` in the background immediately.

Tell the user once that a save landing between steps 3 and 4 is missed and they
should save again. `--loop` never exits and never surfaces anything — only
useful when nobody is watching the conversation.

## What cost time the first day, so it does not cost it again

- **`flutter run` over SSH ignores piped stdin.** The app launches and works,
  but `r` never reloads and nothing in the log says why. It needs a real pty —
  hence `remote/frun.py`. macOS `script(1)` cannot supply one: it wants a tty on
  its own stdin and dies with `tcgetattr/ioctl: Operation not supported on
  socket`.
- **`tmux` is not on the Mac**, so the obvious "send keys to a session" route
  is not available. The fifo at `/tmp/frun.in` replaces it; it is opened
  `O_RDWR` so it never sees EOF between writers.
- **SSH `ControlMaster` fails in this sandbox** — `muxclient socket():
  Operation not permitted`. Every call pays a fresh ~0.4 s connect, which is
  why the watcher detects changes with a local `find -newer` and only reaches
  the Mac when something actually changed.
- **A backgrounded process does not survive its Bash call.** Each call is its
  own PID namespace, so `nohup … &` here dies immediately; only
  `run_in_background: true` persists. On the Mac, `nohup` is fine.
- **`xcrun simctl io … screenshot`** will not write to `-` or `/dev/stdout`. It
  writes a file; pull it with `scp`.

## Mirroring the simulator here — don't

Asked, investigated, dead end. Simulator.app is a Cocoa app, so X11 forwarding
carries nothing; XQuartz only forwards X11 clients. macOS Screen Sharing is
live on port 5900 (security types `[30, 33, 36, 31, 32, 2, 35]` — 30 is Apple
Remote Desktop auth, 2 is standard VNC), but no VNC client is installed here
and `sudo` needs a password, and VNC serves the **whole desktop** — there is no
single-window mirroring on macOS. James's call on 25 Aug 2026: if it cannot be
one app, he would rather not. Screenshot-per-save is the answer instead.
