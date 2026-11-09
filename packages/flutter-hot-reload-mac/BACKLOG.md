# Backlog — flutter-hot-reload-mac

Opened 25 Aug 2026, when the package was moved here from `~/.claude/skills`.
Each item's status was checked against 1.0.0 on 9 Nov 2026.

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

## Behaviour

6. **The watcher misses saves in the relaunch gap.** `watch.sh` exits after
   each save so the harness wakes Claude to post the screenshot; a save landing
   between the exit and the relaunch is not seen. A queue file the next run
   drains would close it.
   Status: **OPEN.** Unchanged in 1.0.0; `watch.sh`'s header documents the gap.

7. **Only `lib/**/*.dart` is watched.** Assets, translation JSON, `pubspec.yaml`
   and iOS native code are neither synced nor reloaded — the last two need a
   full rebuild, not a reload, and nothing says so when they change.
   Status: **OPEN.** `watch.sh` still finds only `*.dart` under `WATCH_DIR`.

8. **One simulator.** `DEV` picks a single device; the iPad booted alongside it
   is ignored. Reloading both would mean two `flutter run`s, so two fifos and
   two logs.
   Status: **OPEN.**

9. **`start.sh` waits up to ten minutes** in ten-second SSH polls. A cold build
   is minutes, so this is right, but each poll is a fresh connection.
   Status: **OPEN.**

10. **Nothing notices when `flutter run` dies.** The log gets
    `[frun] flutter run exited`; the watcher keeps syncing into a dead app and
    the screenshots simply stop changing.
    Status: **OPEN.** `start.sh` checks the log for `exited` only while waiting
    for the launch; `watch.sh` never checks.

## Wanted

11. **A `.maestro-mac.conf` block** for `FLUTTER_BIN`, `FLAVOR`, `TARGET` and
    `WATCH_DIR`, written by an `init.sh` like the maestro skill's, so the
    defaults are not silently assumed.
    Status: **PARTLY DONE.** `FLUTTER_BIN`, `FLAVOR`, `TARGET` and `WATCH_DIR`
    are read from the per-project conf, now `.maestro-drive.conf`
    (`bin/lib.sh:38`), and their defaults are listed in `SKILL.md`. No `init.sh`
    writes them.

12. **Cropping to a region** for UI work on one widget — the whole 1206×2622
    frame is mostly chrome when the change is a banner.
    Status: **OPEN.**

13. **Reading `flutter run`'s exceptions back** into the conversation rather
    than just the reload line, so a save that throws is visible immediately.
    Status: **PARTLY DONE.** After each reload `watch.sh` prints the last two
    log lines matching `Reloaded`, `reload failed/rejected`, `Error` or
    `Exception`; the exception text itself is not read back.

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
    Status: **OPEN.**

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

## Scope

14. **Review against rot and bloat, and how much of this should be
    `maestro-remote-mac`'s job instead.** `skill/bin/lib.sh`'s `_find_conf` is a
    byte-for-byte copy of `maestro-remote-mac/src/bin/config.sh`'s (13 lines,
    only the package name in the error message differs). Past that they've
    diverged: this skill's `_pick_host`/`_ssh` are an earlier draft of logic
    `maestro-remote-mac/src/bin/lib.sh` has since grown past — no retry on a
    slow wake, no re-picking after a stale connection dies mid-command, no
    `_macip`, no `REMOTE_ENV` for a non-interactive shell's missing PATH — so
    this skill isn't sharing that plumbing, it's frozen behind it. Work out
    whether the conf lookup should be the one place that's actually shared, and
    whether the SSH/host-picking layer should be dropped in favour of calling
    into `maestro-remote-mac` rather than maintaining a second, drifting copy.
    Status: **OPEN.**
