# Manual checks against real devices

Run on 11 Nov 2026 for 2.0; results are in `../../README.md` ("Verified") and
`../../BACKLOG.md` items 14 and 20. Not part of `test/run-tests.sh`, and not
portable as they stand: they hard-code this machine's paths — the hugoboss
project checkout, the claude-skills scratchpad, the Mac simulator UDIDs, the
bridge directory of the session that ran them. Each logs to
`$TMPDIR/fhrm-<name>.log` and undoes what it set up.

| script | where | what |
|---|---|---|
| `mac-guards.sh` | Mac, ssh | every `start.sh` refusal: label, live run on the same checkout, live 1.0 run, uncommitted work, a commit made there |
| `mac-two-devices.sh` | Mac, ssh | two simulators on two checkouts at once; stop one, the other runs on |
| `mac-remaining.sh` | Mac, ssh | a real fast-forward, one watcher save, the watcher's exit 2, `PROFILE` |
| `android-bridge.sh` | this machine, `TRANSPORT=bridge` | Android emulator end to end — stopped unfinished at the first Gradle build (BACKLOG item 20) |
