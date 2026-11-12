# Manual checks against real devices

Run on 11 and 12 Nov 2026 for 2.0; results are in `../../README.md` ("Verified") and
`../../BACKLOG.md` items 14 and 20. Not part of `test/run-tests.sh`, and not
portable as they stand: they hard-code this machine's paths — the hugoboss
project checkout, the claude-skills scratchpad, the Mac simulator UDIDs, the
bridge directory of the session that ran them. Each logs to
`$TMPDIR/fhrm-<name>.log` and undoes what it set up.

| script | where | what |
|---|---|---|
| `mac-guards.sh` | Mac, ssh | every `start.sh` refusal: label, live run on the same checkout, live 1.0 run, uncommitted work, a commit made there |
| `mac-two-devices.sh` | Mac, ssh | two simulators on two checkouts at once; stop one, the other runs on |
| `mac-remaining.sh` | Mac, ssh | a real fast-forward, reload and hot restart each showing only its own answer, one watcher save, the watcher's exit 2, `PROFILE`; since items 6, 7 and 9: "up after", a save between two watcher runs, an asset save rsynced and hot restarted, a `pubspec.yaml` save exiting 4 |
| `mac-errors.sh` | Mac, ssh | BACKLOG items 10 and 13: a save that throws in a build, one that does not compile, a clean one after, and flutter killed with no save |
| `android-bridge.sh` | this machine, `TRANSPORT=bridge` or `TRANSPORT=local` | Android emulator end to end: Gradle first with no emulator, then boot, start, reload, restart, status, one watcher save, stop; since items 6, 7 and 9: "up after", a save between two watcher runs, a red asset replaced by a blue one and hot restarted (both screenshots kept in `SCR`), a `pubspec.yaml` save exiting 4. Takes `BRIDGE_DIR`, `BRIDGE_HOST` and `SCR` from the environment; `local` runs in a terminal with the sandbox off |
