#!/bin/bash
# flutter-hot-reload-mac on a physical iPhone (BACKLOG item 21), on the Mac.
#   1. start.sh: maestro-drive's device-check, its signed debug build in the
#      GUI session, the install, flutter run --use-application-binary; "up after"
#   2. reload.sh, then a hot restart
#   3. one save through watch.sh: synced, reloaded, a screenshot from the phone
#   4. logs.sh: the app's flutter: lines from the phone's syslog, for 20 s
#   5. stop.sh, nothing left running
#
# PHONE=<udid> is required: the phone, plugged into the Mac, trusted, Developer
# Mode on, and in the provisioning profile of the flavour being built. It must
# be UNLOCKED while start.sh launches the app; the script says so when that
# starts. APP_ID and BUILD_FLAVOR override the project conf's for one run.
#
# Until maestro-drive releases its item 176 (device-check, run-diagnose, logs,
# build --mode debug), this runs against maestro-drive's main: exported with
# git archive into $TMPDIR (MD_MAIN), never its working tree, which may hold
# another session's uncommitted edits. FHRM_MAESTRO_DRIVE then points there.
#
# Works from a clone of the project in $TMPDIR (SC), so the project's own
# checkout is only read. Run from anywhere. The Mac's lib/ is synced back and
# its branch left where it was (--no-branch).
# Logs to $TMPDIR/fhrm-mac-phone.log.
set -uo pipefail
S=/mnt/sda/Development/github-lenny1882/claude-skills/packages/flutter-hot-reload-mac/skill/bin
SRC=${SRC:-/mnt/sda/Development/oi/client_hugo-boss/hugoboss-flutter-runner}
MDSRC=${MDSRC:-/mnt/sda/Development/github-lenny1882/maestro-drive}
: "${TMPDIR:=/tmp}"
: "${PHONE:?set PHONE to the udid of the phone (xcrun devicectl list devices on the Mac)}"
SC=${SC:-$TMPDIR/fhrm-hb-phone}
MD_MAIN=${MD_MAIN:-$TMPDIR/fhrm-md-main}
LOG=$TMPDIR/fhrm-mac-phone.log
exec > >(tee "$LOG") 2>&1
pass=0; fail=0
ok(){ echo "  ok    $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1"; echo "$2" | sed 's/^/    /'; fail=$((fail+1)); }

rm -rf "$MD_MAIN"; mkdir -p "$MD_MAIN"
git -C "$MDSRC" archive main skill | tar -x -C "$MD_MAIN" --strip-components=1 || exit 1
export FHRM_MAESTRO_DRIVE=$MD_MAIN
rm -rf "$SC"
git clone -q --no-local "$SRC" "$SC" || exit 1
git -C "$SC" switch -q "$(git -C "$SRC" rev-parse --abbrev-ref HEAD)" 2>/dev/null
cp "$SRC/.maestro-drive.conf" "$SC/"
cd "$SC" || exit 1
export PLATFORM=ios-device DEV=$PHONE
. "$S/lib.sh" || exit 1
_pick_host || exit 1
_paths "$DEV"
echo "$(date '+%F %T') on $(_where), phone $DEV, $REPO, APP_ID=$APP_ID, maestro-drive main at $(git -C "$MDSRC" rev-parse --short main)"
_ssh "xcrun devicectl list devices 2>/dev/null | grep '$DEV'" | sed 's/^/    /'

restore() {
  echo "restore"
  bash "$S/stop.sh" 2>&1 | sed 's/^/    /'
  git -C "$SC" checkout -q -- lib 2>/dev/null; (cd "$SC" && _sync) && echo "    the Mac's lib/ synced back clean"
  _ssh "pgrep -fl '[i]devicesyslog -u $DEV'; git -C '$REPO' status --porcelain --untracked-files=no | sed 's/^/    /'"
  cd /; rm -rf "$SC" "$MD_MAIN"
}
trap restore EXIT

echo "1. start.sh on the phone"
echo "    >>> UNLOCK THE PHONE ($DEV) and keep it unlocked until 'up after' — the launch needs it."
t0=$(date +%s)
# Streamed, not collected: start.sh's own "must be UNLOCKED now" line has to
# reach the log while the launch waits on it.
START_WAIT=1200 bash "$S/start.sh" --build --no-branch 2>&1 | tee "$TMPDIR/fhrm-phone-start.out" | sed -u 's/^/    /'
rc=${PIPESTATUS[0]}; out=$(cat "$TMPDIR/fhrm-phone-start.out")
grep -q '^rosetta: ' <<<"$out" && ok "device-check: $(grep -m1 '^rosetta: ' <<<"$out")" || no "device-check ran" "no rosetta: line"
grep -q '^  built .*Runner.app' <<<"$out" && ok "maestro-drive's debug build: $(grep -m1 '^  built ' <<<"$out" | sed 's/^ *//')" || no "the phone build" "see above"
[ $rc = 0 ] && grep -q '^up after' <<<"$out" && ok "up in $(( $(date +%s) - t0 ))s; $(grep -o 'up after [0-9]*s' <<<"$out")" || no "start on the phone" "rc=$rc; last of the log:
$(_ssh "tail -30 '$RLOG'")"
_ssh "grep -m1 'ARGS\|use-application-binary\|Launching' '$RLOG'" | sed 's/^/    log: /'
[ $rc = 0 ] || exit 1

echo "2. reload, then hot restart"
out=$(bash "$S/reload.sh" 2>&1); echo "$out" | sed 's/^/    /'
grep -q 'Reloaded .* in ' <<<"$out" && ok "reload: $(grep -m1 -o 'Reloaded .* in [0-9,]*ms' <<<"$out")" || no "reload" "$out"
out=$(bash "$S/reload.sh" restart 2>&1); echo "$out" | sed 's/^/    /'
grep -q 'Restarted application' <<<"$out" && ok "restart: $(grep -m1 -o 'Restarted application in [0-9,]*ms' <<<"$out")" || no "restart" "$out"

echo "3. one save through watch.sh"
W=$TMPDIR/fhrm-phone-watch.out
( WATCH_ALIVE=0 timeout 180 bash "$S/watch.sh" > "$W" 2>&1; echo "exit=$?" >> "$W" ) & w=$!
sleep 4; touch lib/main_dev.dart; wait "$w"
sed 's/^/    /' "$W"
shot=$(sed -n 's/^SHOT: //p' "$W")
grep -q '^exit=0' "$W" && grep -q 'Reloaded .* in ' "$W" && [ -s "$shot" ] && file "$shot" | grep -q PNG \
  && { ok "synced, reloaded, a PNG from the phone"; cp "$shot" "$TMPDIR/fhrm-phone-shot.png"; echo "    copy: $TMPDIR/fhrm-phone-shot.png"; } \
  || no "a save through watch.sh" "see above"

echo "4. logs.sh for 20 s (a hot restart in the middle, so the app prints)"
( bash "$S/logs.sh" 20 > "$TMPDIR/fhrm-phone-logs.out" 2>&1 ) & l=$!
sleep 6; bash "$S/reload.sh" restart >/dev/null 2>&1; wait "$l"
sed 's/^/    /' "$TMPDIR/fhrm-phone-logs.out"
lf=$FLDIR/logs-$DEV.log
n=$(grep -c 'flutter: ' "$lf" 2>/dev/null); n=${n:-0}
head -5 "$lf" 2>/dev/null | sed 's/^/    log: /'
[ "$n" -gt 0 ] && ok "$n flutter: lines from the phone" || no "logs.sh" "no flutter: lines in $lf (the app may print nothing on a restart)"
left=$(_ssh "pgrep -fl '[i]devicesyslog -u $DEV'; true")
[ -z "$left" ] && ok "nothing left reading the phone's syslog" || no "logs.sh cleanup" "$left"

echo "5. stop"
out=$(bash "$S/stop.sh" 2>&1); echo "$out" | sed 's/^/    /'
[ "$out" = stopped ] && ok "stopped" || no "stop" "$out"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
