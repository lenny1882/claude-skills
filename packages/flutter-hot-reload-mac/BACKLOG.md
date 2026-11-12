# Backlog — flutter-hot-reload-mac

Opened 25 Aug 2026, when the package was moved here from `~/.claude/skills`.
Each item's status was checked against 1.0.0 on 9 Nov 2026, and against
2.0.0 on 12 Nov 2026.

## Packaging

1. **No installer.** Needs `install.sh` (with `--link` for development),
   `uninstall.sh` and `manifest.sh`, to match the other packages here.
   `claude-package-kit/skill/bin/new-package.sh --name flutter-hot-reload-mac
   --kind skill --no-release` scaffolds the lot; the payload then moves into
   the generated `skill/`.
   Status: **DONE by 1.0.0 (26 Oct 2026).** `install.sh` (with `--link`),
   `uninstall.sh`, `manifest.sh` and `update.sh` are in the package; 1.0.0 is
   installed from its release tarball at
   `/mnt/sda/User/Programs/claude-tools/flutter-hot-reload-mac`.

2. **No tests.** `bash -n` and one manual run is all that stands behind it. The
   testable parts without a Mac: conf discovery in `lib.sh`, `_pick_host`'s
   cache, the `find -newer` detection in `watch.sh`, and `frun.py`'s command
   assembly with a stubbed `subprocess`.
   Status: **MOSTLY DONE by 1.0.0.** `test/run-tests.sh` (52 checks on 9 Nov
   2026) covers conf discovery, `_pick_host`'s single-host, cached and
   first-answer cases, `frun.py`'s command assembly with a fake flutter, and
   `reload.sh`, against an ssh stub. Still untested: `watch.sh`'s `find -newer`
   detection, which is parse-checked only.
   **DONE in 2.0.0 (12 Nov 2026).** 84 checks; every script runs end to end
   against a stand-in `maestro-drive` in local transport and a fake flutter,
   `watch.sh`'s detection included (one save → sync → reload → screenshot).
   Since run against the Mac and on Android: the scripts in `test/manual/`
   (item 14, item 20). 88 checks on 12 Nov 2026.

3. **No git.** Same gap as `maestro-remote-mac`.
   Status: **DONE.** The package lives in `claude-skills`, at
   `packages/flutter-hot-reload-mac`.

4. **Two copies exist** until `~/.claude/skills/flutter-hot-reload-mac` is
   removed by hand. Nothing keeps them in step.
   Status: **DONE by 1.0.0.** The installer replaced the hand copy at
   `~/.claude/skills/flutter-hot-reload-mac` (a test covers "installing over a
   hand copy replaces it"), and `update.sh` keeps the installed copy in step
   with releases.

5. **No execute bits** on `skill/bin/*.sh` — they cannot be set from Claude's
   Bash, so callers use `bash <script>`. An installer would fix this properly.
   Status: **OPEN.** Still true in 1.0.0: `skill/bin/*.sh` are mode 100644 in
   git and 664 when installed, and `install.sh` only sets execute bits on
   `FILES`, which this package leaves empty. `SKILL.md` calls each script with
   `bash`.
   **DONE on `main`, not released (12 Nov 2026).** `chmod` works in the
   checkout; only the installed copy under `~/.claude/skills` is read-only
   from the sandbox. `start`, `watch`, `reload`, `status` and `stop` are mode
   100755 in git. `git archive` keeps the mode in the release tarball and
   `install.sh`'s `cp -r` keeps it on install. Tested: the installed scripts are
   executable, and git has the bit. `SKILL.md` still calls them with `bash`.

## Behaviour

6. **The watcher misses saves in the relaunch gap.** `watch.sh` exits after
   each save so the harness wakes Claude to post the screenshot; a save landing
   between the exit and the relaunch is not seen. A queue file the next run
   drains would close it.
   Status: **OPEN.** Unchanged in 1.0.0; `watch.sh`'s header documents the gap.
   **DONE on `main`, not released (12 Nov 2026).** No queue file was needed.
   The marker now persists between runs, so a save made while no watcher runs
   is newer than it, and the next run handles it at once. `watch.sh` only
   creates the marker when it is missing, and `start.sh` resets it after its
   sync. A run takes the new marker after the 0.4 s settle and before its final
   look, so a save after that look goes to the next run. Tested: a save made
   between two runs is synced and reloaded within 5 s of the next run
   starting, and the run after that does not replay it.
   Run on real devices 12 Nov 2026: on the Mac (`mac-remaining.sh`, mac-home,
   iPhone 16 Pro, hugoboss-flutter-runner) handled 4 s after the next run
   started; on the Android emulator over the bridge (`android-bridge.sh`) 3 s.
   It also changed how `mac-errors.sh` had to be written: each step edited the
   file, started the watcher, then touched the file again, and the watcher now
   handles the edit as it starts, leaving the touch for the next step's run.
   The script no longer touches.

7. **Only `lib/**/*.dart` is watched.** Assets, translation JSON, `pubspec.yaml`
   and iOS native code are neither synced nor reloaded — the last two need a
   full rebuild, not a reload, and nothing says so when they change.
   Status: **OPEN.** `watch.sh` still finds only `*.dart` under `WATCH_DIR`.
   **DONE on `main`, not released (12 Nov 2026).** Three settings in
   `bin/lib.sh`, each a space-separated list of project paths:
   - `WATCH_DIR` (`lib`): every file is now watched, not just `*.dart`.
     Synced, then hot reload.
   - `WATCH_ASSETS` (`assets`): synced, then hot restart, because a reload
     keeps the old image in Flutter's image cache.
   - `WATCH_REBUILD` (`pubspec.yaml ios android`): not synced. Each changed
     file is printed as a `REBUILD:` line, and the one-shot mode exits 4 with
     "Commit it, then bin/start.sh --build".
   Not counted as saves: dotfiles, editor backups (`*~`, `*.swp`, `*.tmp`),
   `Pods`, `.symlinks`, `ephemeral`, `build`, `.gradle`, `.dart_tool`, `.cxx`,
   and the files `flutter pub get` regenerates. `start.sh` syncs
   `WATCH_ASSETS` with `WATCH_DIR` and leaves both out of its uncommitted-work
   check. The first run of the new tests found that this was needed: assets
   the watcher had synced were refused as someone's work. Deletions are only
   synced when another file in that directory is saved, as before.
   Tested against the stand-in, not yet on a real Flutter run: an asset save
   is synced and restarted; a `pubspec.yaml` save is not synced and exits 4; a
   code save together with an `ios/Runner` save reloads and lists the native
   file; `ios/Pods` and editor backups trigger nothing.
   Run on real devices 12 Nov 2026. On the Android emulator
   (`android-bridge.sh`): the probe app's home page shows `assets/fhrm.png`; a
   red square replaced by a blue one was hot restarted, and the screenshot after
   it shows the blue square where the red one was. On the Mac
   (`mac-remaining.sh`): a new file under `assets/` reached the Mac's checkout by
   rsync and the app hot restarted (465 ms); a `pubspec.yaml` save exited 4
   with the Mac's copy unchanged. The first Mac run found a fault, fixed: a file
   put back with `git checkout --` gets a new time, so the next run listed
   `pubspec.yaml` as a REBUILD although it matched `HEAD`. `watch.sh` now drops
   tracked files identical to `HEAD` from the REBUILD list, and goes on
   watching when nothing else is left.

8. **One simulator.** `DEV` picks a single device; the iPad booted alongside it
   is ignored. Reloading both would mean two `flutter run`s, so two fifos and
   two logs.
   Status: **DONE in 2.0.0 (12 Nov 2026).** Every remote path is per device,
   `$RDIR/frun-<udid>.{in,log,pid}`, and `DEV=<udid>` picks one; a run per
   device, two at once tested. Each device's run needs its own `REPO`.

9. **`start.sh` waits up to ten minutes** in ten-second SSH polls. A cold build
   is minutes, so this is right, but each poll is a fresh connection.
   Status: **OPEN.**
   **DONE on `main`, not released (12 Nov 2026).** The log is now read on the
   Mac, every `START_POLL` seconds (2), inside one connection that lasts up to
   `START_CHUNK` seconds (120), with `TMO` raised to match for that call. So a
   ten-minute build uses five connections instead of sixty, and the app being
   up is seen within 2 s instead of 10. `START_WAIT` (600) is the whole wait,
   replacing `START_TRIES` × `START_POLL`. A connection that returns nothing is
   retried rather than read as a failure. Tested: a 4 s build is waited for in
   at most 2 connections; `START_WAIT=4` gives up after 4 s.
   Run on real devices 12 Nov 2026: up after 27 s on the Mac, over ssh; up
   after 62 s on the Android emulator, in one bridge call.

10. **Nothing notices when `flutter run` dies.** The log gets
    `[frun] flutter run exited`; the watcher keeps syncing into a dead app and
    the screenshots simply stop changing.
    Status: **MOSTLY DONE in 2.0.0 (12 Nov 2026).** `watch.sh` checks the run's
    PID before each reload and exits 2 with the last of the log when it has
    gone; `SKILL.md` says not to relaunch the watcher then. Between saves
    nothing checks, so a death is noticed at the next save, not when it
    happens.
    **DONE on `main`, not released.** Between saves `watch.sh` checks the run
    every `WATCH_ALIVE` seconds (30 by default, 0 for never) in one round trip
    and exits 2 with the end of the log when it has gone. A failed ssh is not
    read as a dead run. Tested against the stand-in: flutter killed with no
    save, reported in under 6 s with `WATCH_ALIVE=1`. On the Mac, 12 Nov 2026
    (`test/manual/mac-errors.sh`, mac-home, iPhone 16 Pro,
    hugoboss-flutter-runner): flutter killed with no save, exit 2 two seconds
    later with `WATCH_ALIVE=5`.

## Wanted

11. **A `.maestro-mac.conf` block** for `FLUTTER_BIN`, `FLAVOR`, `TARGET` and
    `WATCH_DIR`, written by an `init.sh` like the maestro skill's, so the
    defaults are not silently assumed.
    Status: **PARTLY DONE.** `FLUTTER_BIN`, `FLAVOR`, `TARGET` and `WATCH_DIR`
    are read from the per-project conf, now `.maestro-drive.conf`
    (`bin/lib.sh:38`), and their defaults are listed in `SKILL.md`. No `init.sh`
    writes them.
    **DONE in 2.0.0 (12 Nov 2026)**, by removing them: the SDK, flavour and
    entry file are worked out by `maestro-drive`, whose `bin/init.sh` writes
    the conf; `WATCH_DIR` is the one setting left, defaulting to `lib`.

12. **Cropping to a region** for UI work on one widget — the whole 1206×2622
    frame is mostly chrome when the change is a banner.
    Status: **DONE in 2.0.0 (12 Nov 2026)**, by `maestro-drive`: its
    `bin/shot.sh --crop X,Y,W,H` and `bin/driver.sh shot` (crop to a named
    element). This skill's `shot.sh` went. `watch.sh`'s per-save screenshot is
    still the whole frame.

13. **Reading `flutter run`'s exceptions back** into the conversation rather
    than just the reload line, so a save that throws is visible immediately.
    Status: **PARTLY DONE.** After each reload `watch.sh` prints the log
    lines matching `Reloaded`, `reload failed/rejected`, `Error` or
    `Exception` that this reload added; the exception text itself is not
    read back.
    **DONE on `main`, not released.** `reload.sh` and `watch.sh` share one
    remote script (`_key_script` in `bin/lib.sh`). It notes the log's length
    before the key, waits for flutter's answer and `RELOAD_SETTLE` (1 s) more,
    then prints everything from the first error line the key added (`EXCEPTION
    CAUGHT BY`, `Another exception was thrown`, `Unhandled Exception`,
    `: Error: `), without colour codes, up to `RELOAD_ERR_LINES` (40). Two
    faults found on the way, both fixed: a reload that did not compile has no
    "Reloaded" line, so the wait ran the full 60 s (it now also ends on "Try
    again after fixing"); and `watch.sh`'s wait ended on any line with
    "Exception" in it, the app's own output included.
    On the Mac, 12 Nov 2026 (`test/manual/mac-errors.sh`, 9 of 9 on the third
    run): a save that throws in a build showed its reload line, then the
    `EXCEPTION CAUGHT BY WIDGETS LIBRARY` block with the exception's text and
    stack; a save that does not compile answered in 5 s with the error, the
    source line and the caret; the next clean save showed no error. The first
    two runs found three faults, all fixed: flutter writes each error line
    after a carriage return on its spinner's line, so deleting carriage
    returns hid the compile error and the exception header behind
    "Performing hot reload..." (a carriage return inside a line is now a line
    break); the colour-code pattern, applied after the escapes were gone,
    cut `[frun]` to `run]` (codes now go only with their escape, in one `awk`
    that macOS's awk and gawk run alike); and the "no answer" and "run has
    gone" log tails kept their terminal codes. A throw above `MaterialApp` is
    no test of this: the app's own error widget fails for want of a
    `Directionality`, and flutter logged 19,312 lines and took 230 s to
    answer the reload.

15. **~~`--flavor` splice position breaks device selection~~ — fixed.**
    `cmd[3:3]` in `frun.py:55` inserted `--flavor dev` between `-d` and the
    UDID, so flutter parsed `--flavor` as the device name. Changed to `cmd[2:2]`.

16. **This skill gets reached for when the ask was to DRIVE, four times in one
    day.** 15 Sep 2026, four separate sessions in a client app project
    opened by starting hot reload when James had asked for UI driving —
    *"You made this same mistake yesterday. Did I ask for hot reload?"*,
    *"Right, you keep jumping straight to hot reload, why?"*, *"stop with the
    fucking hot reload skill"*, *"The fuck are you doing? maestro skill."*

    Both descriptions already say it. This skill's says it is not for driving;
    `maestro-remote-mac`'s says it does not build or launch from source. The
    session pressed for a real answer gave one: *"I'm pattern-matching 'start
    driving' + 'DEV app' + 'build' to 'launch the app', and hot-reload is the
    skill that launches. The distinction I'm failing to make is between running
    the app and driving the app."* The trigger is a request that mentions a
    build or an environment, which is most of them.

    Four repeats in a day, after the description was written to prevent exactly
    this, is the argument `maestro-remote-mac` item 51 made for a hook over more
    prose: a rule read at the wrong moment is not a rule.

    *Approximate resolution.* A `PreToolUse` hook on this skill's entry points
    that asks whether the app is already installed on the target simulator — if
    it is, name `maestro-remote-mac` and stop. The check is cheap:
    `maestro-remote-mac`'s `bin/preflight.sh` answers it in one round trip. It
    fires at the moment of the mistake rather than at session start, which is
    the whole point. `maestro-remote-mac/src/hooks/gate-journey-first.sh` is the
    worked precedent, and that package's `ship.sh` shows how a hook ships with a
    skill.

    Raised from `maestro-remote-mac` BACKLOG item 82 (17 Sep 2026), where the
    cost landed. The fix belongs here.
    Status: **PARTLY DONE in 2.0.0 (12 Nov 2026).** Not a hook: `start.sh` stops
    with exit 3 when `APP_ID` is already installed on the device, saying
    driving is `maestro-drive`'s and rebuilding is `--build`, and `SKILL.md`
    says which to choose. It fires at the first command, not before the skill
    is picked.
    **DEFERRED 12 Nov 2026.** Four ways forward were on the table:
    - *A blocking hook.* A `PreToolUse` hook on the Skill call for this skill
      reads the user's last message and stops the call, naming `maestro-drive`,
      when it asks to drive (tap, drive, test the UI, reproduce, step through)
      and says nothing about building or watching changes. No Mac round trip.
      Risk: a wrong block on a message that asks for both.
    - *A one-off block.* As `maestro-drive`'s `hooks/gate-journey-first.sh`
      does: block the first call in a session with exit 2, saying driving is
      `maestro-drive`'s, and let a repeat through. A wrong block costs one
      retry, so it needs no reading of the message.
    - *A reminder hook.* Let the call through and add a note to the context.
      Never blocks wrongly; it is more prose of the kind that failed four
      times in one day.
    - *Leave it.* Close the item on `start.sh`'s exit 3.
    Found while looking: `maestro-drive`'s description stopped naming this
    skill on 26 Oct 2026 (`9512ae4`, a README commit tied to no item), when
    "does NOT build or launch from source (that is flutter-hot-reload-mac)"
    became "builds and installs it only when asked". `maestro-drive` item 82
    closed by handing the fix here and changed nothing there.

17. **~~An empty `FLAVOR` cannot turn the flavour off~~ — fixed in 1.0.0.**
    `SKILL.md` says `FLAVOR` is "empty for an unflavoured build", but the
    pre-release `bin/lib.sh:47` defaulted it with `: "${FLAVOR:=dev}"`, and `:=`
    replaces an empty value as well as an unset one. Measured 21 Oct 2026 on the
    hand-made installed copy: `FLAVOR= bash bin/start.sh` still launched with
    `--flavor dev`. 1.0.0 has `: "${FLAVOR=dev}"` (no colon) at `bin/lib.sh:59`.

18. **`start.sh` kills every `flutter run` on the Mac, not just its own.**
    `start.sh:39` runs `pkill -f frun.py; pkill -f 'flutter_tools.snapshot run'`.
    The Mac is shared by several sessions and projects, and that pattern matches
    all of them. 21 Oct 2026: a 5 Oct `flutter run` (`sh -c tail -f
    /tmp/fr-1824.in | … flutter run`, PID 21129) was found with its flutter
    process gone and only the parent shell left; whether this pkill did it is
    unconfirmed. The same day a peer session (ABC-125) and this skill were both
    launching onto one iPhone 16 Pro, each killing the other's app — "Termination
    requested by simulator host" in SpringBoard's log at 16:37 and 16:44.
    The fixed paths make it worse: `bin/lib.sh:69-73` sets `/tmp/frun.py`,
    `/tmp/frun.in`, `/tmp/frun.log`, `/tmp/frun.err` and `/tmp/frun-shot.png`,
    one each per Mac (`remote/frun.py:38-39` hard-codes the fifo and log too),
    so a second session's `start.sh` takes over the first's fifo and log.
    *Fix:* record the PID `frun.py` starts in a per-device state file and kill
    only that; key the fifo/log/script paths by UDID (which item 8 needs anyway).

    Items 17 and 18 were raised 21 Oct 2026 in the pre-release copy at
    `~/scratch/flutter-hot-reload-mac/BACKLOG.md` and ported
    here 26 Oct 2026. Line numbers checked against 1.0.0.
    Status: **OPEN.** Still true in 1.0.0: `start.sh:39` and `stop.sh:13` run
    the same `pkill`, and `bin/lib.sh:69-73` still fixes the `/tmp/frun.*`
    paths.
    **DONE in 2.0.0 (12 Nov 2026).** No `pkill`: `frun.py` writes
    `$RDIR/frun-<udid>.pid` ("<frun pid> <flutter pid> <repo>"), and `stop.sh`
    and a restart kill that run only — frun.py's SIGTERM handler stops
    flutter's process group. Paths are per device. `start.sh` also refuses a
    device another session labelled today (`maestro-drive`'s `_label_guard`),
    and refuses while a 1.0 run (`/tmp/frun.py`) is live.

19. **No physical-device path.** The skill covers simulators only. On 11 Nov
    2026 the hugoboss-flutter-runner session ran `flutter run --debug` on a
    USB iPhone 11 Pro (iOS 26.5.2) from the Mac oi-jamesl-mac (Xcode 27.2,
    macOS 27.2, Flutter 3.41.9 via fvm) to read `debugPrint` output. It failed
    three ways:
    - **No Rosetta.** Flutter's bundled `artifacts/libusbmuxd/iproxy` is
      x86_64. The app built, installed and launched, then the run died with
      "Flutter failed to run .../iproxy ... built with the incorrect
      architecture". Installing Rosetta (sudo, by the user) fixed it.
    - **LLDB never connects.** With LLDB on: "LLDB is taking longer than
      expected to start debugging the app", then 11 minutes of silence. lldb
      was attached and the app running; device support for iPhone12,3 26.5.2
      was already in `~/Library/Developer/Xcode/iOS DeviceSupport`.
    - **mDNS discovery fails without LLDB.** With `flutter config
      --no-enable-lldb-debugging`: "Flutter could not access the local
      network", "SocketException: Send failed (OS Error: No route to host,
      errno = 65), address = 0.0.0.0, port = 5353", then "The Dart VM Service
      was not discovered after 60 seconds". This persisted after Local Network
      and Automation→Xcode were granted to Terminal and both apps restarted.
      Default route was en0 via 10.0.52.254.

    Release-mode `flutter run` and `devicectl device process launch --console`
    show no Dart `print`/`debugPrint` output, so neither replaces a debug run.
    `log stream` has no device option and `devicectl` has no syslog subcommand.
    `flutter logs -d <udid>` (idevicesyslog, runnable once Rosetta is in)
    streams the app's output; it was the only working route found.
    *Fix:* a physical-device mode, here or in a sibling skill: check for
    Rosetta (`arch -x86_64 /usr/bin/true`) before launching; detect the LLDB
    stall and the port-5353 `errno = 65` failure and name them; fall back to
    `flutter logs -d <udid>` for output.
    Status: **OPEN.** Raised 11 Nov 2026 from the hugoboss-flutter-runner
    session's report.
    **HANDED TO `maestro-drive` (12 Nov 2026).** 2.0 sits on `maestro-drive`
    and reuses its runners, and a physical iPhone is its `runners/ios-device`
    module (`V2-PLAN.md`, item 14). The Rosetta check, the LLDB-stall and
    port-5353 detection, and the `flutter logs` fallback belong there. Nothing
    is left to do here; the maestro-drive session was told the same day.
    Using what `maestro-drive` built for it is item 21.

20. **Nothing but the ssh transport had run end to end.** On 12 Nov 2026
    `test/manual/android-bridge.sh` passed 10 of 10 with `TRANSPORT=bridge`
    (from inside the sandbox) and again with `TRANSPORT=local` (in a
    terminal, sandbox off): a throwaway `flutter create` app, the
    `Pixel_6_Pro_API_34` emulator on this machine, then start without
    `--build`, `describe` deciding unflavoured and `lib/main.dart`, reload,
    restart, status, one save through `watch.sh` with a PNG screenshot, and
    stop with nothing left running.

    Four things stood in the way, found on the way there:

    - *The Gradle "stall" of 11 Nov was the disk.* The AVD, the Android SDK
      and the Gradle home (`/mnt/sda/User/Programs/.gradle`) are all on
      `/dev/sda`, a spinning disk. A cold-booting emulator kept it saturated
      (I/O pressure 64% full, 14 requests queued, about 40 MB per 10 s of
      random I/O from qemu), so the Gradle client took three minutes just to
      open its own jars, and a cold `build apk` beside the emulator was
      killed at 1500 s while still merging dex. With no emulator running the
      same cold build, x86_64 only, took 90 s. The check now builds first
      and boots after, and `start.sh`'s build is incremental (43–62 s up).
      Nothing in this skill changed for it; a user on that disk hits the
      same wait on any first Android build beside a booting emulator.
    - *The bridge was stopped by another session.* `maestro-drive` 2.2.0 kept
      the running helper in `/tmp/claude-<uid>/.maestro-bridge`, shared by
      every session, so any session's SessionEnd hook stopped this one's
      helper (10:45:07, when an oneiota-products-rn session ended), and every
      later call hung. Fixed in `maestro-drive` 2.2.1: one record per
      Claude session, and the helper records its owner. The check now fails
      at once, rather than hanging, if the bridge goes.
    - *The app was still installed from 11 Nov.* The emulator keeps its data
      across boots, so `start.sh` rightly stopped at "already installed";
      the check now uninstalls the probe after boot and in cleanup.
    - *`reload.sh restart` read the log too early.* It slept a fixed 4 s;
      a hot restart on the emulator took 4.45 s, so it showed the previous
      reload's line. `reload.sh` and `watch.sh` now count flutter's result
      lines before sending the key and wait (up to `RELOAD_TMO`, 60 s) for
      a new one, printing only that. `test/run-tests.sh` covers it with a
      fake restart that takes 5 s.

    Also found: hugoboss-flutter-runner cannot be the Android test bed. Its
    Android build has no product flavours (`applicationId
    com.example.hugoboss_flutter_runner`), while `maestro-drive`'s `describe`
    decides `dev` from the iOS project, so 2.0 would pass `--flavor dev` to
    an Android build that has none. That is `maestro-drive`'s flavour rule
    (iOS evidence only), not this skill's.
    Status: **DONE in 2.0.0 (12 Nov 2026).**

21. **No phone launch: `start.sh` uses none of `maestro-drive`'s phone
    checks.** Item 19 went to `maestro-drive`, which added three Mac-side
    commands to `runners/flutter/framework.sh` as its item 176 (`ce8045f` on
    its `main`, 12 Nov 2026, not released):
    - `device-check <flutter-bin>`: exit 1 naming Rosetta when Flutter's
      `iproxy` is x86_64 only and `arch -x86_64` fails.
    - `run-diagnose <flutter-run-log>`: names ROSETTA, LLDB STALL, MDNS
      BLOCKED or NO VM SERVICE; exit 1 when the log shows none.
    - `logs <udid> <flutter-bin>`: `device-check`, then `flutter logs -d`.

    Its session suggested: `start.sh` calls `device-check` before a phone
    launch, `run-diagnose` on `frun-<udid>.log` when the VM Service is not
    found or the LLDB line appears, and `logs` for the app's output.

    Found while reading for this, and not in that suggestion: a phone build
    has to be signed, and `codesign` over ssh fails with
    `errSecInternalComponent` (`maestro-drive`'s `physical-device.md`).
    `maestro-drive`'s own phone build gets round it by running in the Mac's
    GUI Terminal through `osascript` (`runners/flutter/build.sh:292`).
    `frun.py` is started over ssh, so `flutter run` on a phone would fail at
    signing before any of the three failures above. Whether it does is
    unmeasured: on 11 Nov the hugoboss-flutter-runner session's run built and
    installed, but how it was started is not recorded.

    *Chosen 12 Nov 2026: build with `maestro-drive`, run over ssh.*
    `start.sh` builds the signed debug app with `maestro-drive`'s
    `runners/flutter/build.sh --device <udid> --debug --build-only`, which
    builds in the Mac's GUI Terminal, and reads its `MMARTIFACT` line.
    `frun.py` then runs `flutter run --use-application-binary <app>` over ssh,
    so the run itself never signs. Not chosen: starting `frun.py` in the GUI
    Terminal through `osascript`, which would open a Terminal window per run.
    Whether hot reload works on a phone with `--use-application-binary` is
    unmeasured.
    Needs from `maestro-drive`: `--device` takes `--debug`. It builds
    `flutter build ios --profile` today (`build.sh:265`), and a profile build
    cannot hot reload. Asked of the maestro-drive-4a session 12 Nov 2026.
    Done there the same day (`0c1f6b3`, then `ba38e68`, on its `main`, not
    released): `framework.sh build <repo> --platform ios-device --device
    <udid> --mode debug` builds `flutter build ios --debug` in the GUI
    session and prints `artifact <path>`. That session then ran this route on
    an iPhone 11 (iOS 26.5.2): the debug build with the UAT profile embedded,
    a `devicectl` install, and `flutter run -d <udid> --debug -t
    lib/main_uat.dart --use-application-binary build/ios/iphoneos/Runner.app`
    over ssh with LLDB on reached its VM Service in 71 s; `r` reloaded in
    301 ms. No LLDB stall and no mDNS failure. Its other route (a `devicectl`
    launch, `framework.sh vm-url`, then `flutter attach --debug-url`) works on
    iOS 18.7.9 only: on iOS 26 a debug build will not start without a
    debugger ("Cannot create a FlutterEngine instance in debug mode without
    Flutter tooling or Xcode"), and `vm-url` exits 3 saying so.
    `--use-application-binary` has not been tried on iOS 18.
    Also from that session: the Mac's `/tmp/maestro-mac` was emptied between
    16:58 and 17:07 on 12 Nov 2026 (`maestro-drive` item 144). That is
    `RDIR`, where this skill keeps `frun-<udid>.{in,log,pid}`; a wipe during a
    run makes `reload.sh` find no run and `watch.sh` report it gone, and
    `start.sh` recovers, since it pushes `frun.py` and the runner modules
    every time.

    The rest of the plan:
    1. `PLATFORM=ios-device` in the conf picks the phone; that runner's
       `installed-info` and `screenshot` keep the exit-3 stop and the
       watcher's screenshot working.
    2. `framework.sh device-check <flutter>` before the build; exit 1 stops
       with its text.
    3. The build and launch above.
    4. For a phone, the wait stops on "incorrect architecture", "LLDB is
       taking longer" or "VM Service was not discovered", runs
       `run-diagnose` on `frun-<udid>.log`, prints it and exits 1.
    5. `bin/logs.sh` runs `framework.sh logs`, logging to a file, for the
       app's output.
    6. An installed `maestro-drive` without these commands stops `start.sh`,
       saying to update it.
    7. `test/run-tests.sh`: stand-in `ios-device` runner and fake
       `device-check`/`run-diagnose`; a refused check stops before any
       launch; an LLDB line gives the diagnosis and exit 1; the contract check
       finds the three commands on `maestro-drive`'s `main`.
    8. `test/manual/mac-phone.sh` on oi-jamesl-mac with a USB iPhone:
       `device-check`, build, launch, reload, a watcher save with a phone
       screenshot, `logs.sh`, stop.
    9. `SKILL.md` phone section, README, `test/manual/README.md`.

    Blocked on: a `maestro-drive` release carrying `ce8045f`; Rosetta on
    oi-jamesl-mac, missing again since macOS 27.2.1 (`arch -x86_64`: "Bad
    CPU type"), which needs sudo there; and a USB iPhone on that Mac for the
    test run.
    Status: **OPEN**, raised 12 Nov 2026.
    **DONE on `main`, not released (12 Nov 2026)**, as planned, steps 1 to 9.
    - `start.sh` with `PLATFORM=ios-device`: checks the installed
      `maestro-drive` has the phone commands (stops saying to update it if
      not), runs `device-check` before anything changes, then after the sync
      has `maestro-drive` build the signed debug app (`framework.sh build ...
      --mode debug`, reading its `artifact` line; `DEVICE_BUILD_TIMEOUT`,
      1200 s) and installs it. `frun.py` takes `FRUN_APP_BINARY` and adds
      `--debug --use-application-binary <app>`. It prints `>>> <udid> must be
      UNLOCKED now` as the launch starts.
    - The wait, on a phone, also ends on "incorrect architecture" and "Dart VM
      Service was not discovered"; "LLDB is taking longer" gets `LLDB_GRACE`
      (180 s) and is then a stall. A run that does not come up prints
      `run-diagnose`.
    - `bin/logs.sh [seconds]`: `framework.sh logs` for `LOGS_FOR` (600) s,
      bounded on the Mac too, into `logs-<udid>.log`, with idevicesyslog's
      escaped colour codes and emoji bytes taken out. Its `pkill` pattern is
      `[i]devicesyslog`: the plain one matched the shell running it, which
      killed the test suite on the first run.
    - `test/run-tests.sh`: 125 checks, with a stand-in `ios-device` runner and
      stand-in `device-check`, `run-diagnose`, `build` and `logs`; the contract
      check finds the four commands and `build.sh --debug` on `maestro-drive`'s
      `main`.
    On a phone, 12 Nov 2026 (`test/manual/mac-phone.sh`, mac-home, hz's iPhone,
    an iPhone 11 on iOS 26.5.2, hugoboss-flutter-runner's UAT flavour,
    `maestro-drive` `main` at `5bad32b`), 9 of 9: Rosetta found; the signed
    debug build in the GUI session and the install; up 33 s after the build
    (75 s in all); a reload 888 ms, a hot restart 2,794 ms; one watcher save,
    reloaded in 254 ms, with a screenshot from the phone; `logs.sh` caught 11
    `flutter:` lines in 20 s and left nothing reading; stop. The phone first
    carried the maestro-drive-4a session's label, and `start.sh` refused it
    until that session released it.
    Run again after `logs.sh` began cleaning the lines and the script began
    streaming `start.sh`'s output, 9 of 9: up 31 s after the build (69 s in
    all), a reload 2,360 ms, a hot restart 1,285 ms, a watcher save 261 ms, 11
    `flutter:` lines, now plain text (`flutter: [ Easy Localization] [DEBUG]
    Start`), and the UNLOCK line reached the log while the launch waited.
    Releasing needed a `maestro-drive` release carrying its item 176
    (`ce8045f`, `0c1f6b3`, `ba38e68`): `start.sh` refuses a phone without it.
    `maestro-drive` 2.3.0, released 12 Nov 2026 (tag `v2.3.0` at `dfbdca3`),
    carries it, with its library version still 1.

## Scope

14. **Rebuild as 2.0 on top of `maestro-drive`, as `rrcd` is on `rrc`.**
    Raised as a review of how far this skill's copies of `maestro-drive`'s
    plumbing (then `maestro-remote-mac`) had drifted; answered 11 Nov 2026.
    The review, the plan and the version check are in `V2-PLAN.md`.

    1.0.0 shares only `.maestro-drive.conf` with `maestro-drive`, and has
    fallen behind it everywhere they overlap (reviewed against `maestro-drive`
    at `4475adb`): flavour, entry file and SDK are hard-coded
    (`bin/lib.sh:55-58`) where `maestro-drive`'s `runners/flutter` derives
    them from `APP_ID` and refuses when it cannot; the conf carries two key
    sets for one setting (`FLAVOR`/`TARGET` here, `BUILD_FLAVOR`/
    `BUILD_TARGET` there); `GEM_HOME` is always set, where `maestro-drive`
    sets it only when `pod` is missing; only the SSH transport is known, so
    `TRANSPORT=local` fails with "MAC_HOST is not set"; `_pick_host`/`_ssh`
    lack the slow-wake retry, the mid-command re-pick and the `$TMO` bound,
    and `watch.sh`'s raw `ssh`/`scp`/`rsync` bypass `_ssh` entirely; the
    conf lookup lacks the session cache and `PROFILE` layering; `_dev` picks
    the first booted simulator without saying so.

    *Plan.* 2.0 sources `maestro-drive`'s `bin/lib.sh` and keeps only what
    is its own: `frun.py`'s pty and fifo, `watch.sh`, `reload.sh`,
    `status.sh`, `stop.sh`. `shot.sh` goes (`maestro-drive`'s crops and
    rotates). `start.sh` gets SDK, flavour and entry file from
    `framework.sh describe`/`variant-for-appid`, and uses per-device
    remote paths with a PID file. Install refuses without `maestro-drive`
    at the library version it needs. Closes items 8, 11, 12 and 18; hands
    19 to `maestro-drive`'s `ios-device` runner; carries 2, 5, 6, 7, 9, 10,
    13 and 16.

    *Needs from `maestro-drive` first:* a library version constant (none
    exists; `rrc-lib.sh`'s `RRC_LIB_VERSION` is the model); a
    machine-readable `describe`; `runners/flutter/vmservice.sh` reading the
    per-device log instead of `/tmp/frun.log`; its item 112's label check
    as a callable function. Closes `maestro-drive` item 93 from this side.

    *Branch handling, chosen 11 Nov 2026:* `start.sh` keeps the push and
    `git checkout` on the shared `$REPO`, but refuses when another live run
    uses that `$REPO` (this skill's PID files, or a `maestro-drive` label
    from another session) or when anything is uncommitted outside
    `WATCH_DIR` and the two lock files. Two branches at once means a second
    `REPO` through a conf profile, as `maestro-drive` documents.
    Status: **DONE in 2.0.0, released 12 Nov 2026.** `maestro-drive`'s four
    changes are on its `main` (`2b6d703`), unreleased. 2.0 is on branch
    `flutter-hot-reload-mac-v2`: 84 tests against a stand-in `maestro-drive`
    pass, and the contract checks against its `main` pass. Releasing needs
    a `maestro-drive` release first.
    **Run against the Mac 11 Nov 2026** (mac-office, iPhone 16 Pro,
    hugoboss-flutter-runner, `maestro-drive` 2.2.0): start, reload, restart,
    status, one save through the watcher and stop all worked. It found two
    faults, both fixed: a restart on the branch already checked out there
    failed at the push (the Mac refuses pushes to its checked-out branch), so
    `start.sh` now pushes to `refs/remotes/fhrm/<branch>` and fast-forwards
    there, refusing when a commit was made there; and zsh reported a missing
    PID file. 86 tests. `maestro-drive` 2.2.0 is released.
    Then on the Mac: every guard refused as it should (another session's
    label, another live run on the same checkout, a live 1.0 run, uncommitted
    work, a commit made there), and two devices ran at once on two
    checkouts, each reloading and stopping on its own. Every 2.0 path has
    now run on the Mac. Then, also on the Mac, 5 of 5: a real fast-forward
    from a new local commit, one save through `watch.sh` since `c3ee011`,
    `watch.sh`'s exit 2 when the run dies under it, and `PROFILE` layering.
    Merged to `main`, released as 2.0.0 and installed from its tarball
    12 Nov 2026. The bridge and local transports
    are item 20, done 12 Nov 2026; the Mac checks were rerun that day after
    `reload.sh` and `watch.sh` began waiting for flutter's answer (88 tests).
