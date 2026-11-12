#!/bin/bash
# flutter-hot-reload-mac 2.0: the checks not yet run on the Mac.
#   1. a real fast-forward: a new local commit on the branch the Mac has out
#   2. one save through watch.sh, after c3ee011 changed its PID-file read
#   3. watch.sh's exit 2 when the run dies under it
#   4. PROFILE layering reaching this skill's settings
#   5. reload and hot restart through reload.sh, each showing only its own answer
#      (12 Nov: a fixed 4s sleep showed the previous reload's line for a 4.5s restart)
#   6. f7f092d (BACKLOG items 6, 7, 9): start.sh's on-the-Mac wait says "up after";
#      a save made between two watcher runs is handled by the next at once; an
#      asset save is rsynced to the Mac and hot restarted; a pubspec.yaml save
#      is not synced and exits 4
# Works from a clone of the project in $TMPDIR (SC), so the project's own
# checkout is only read. The Mac's branch is put back to where it was.
# Logs to $TMPDIR/fhrm-mac-remaining.log.
set -uo pipefail
S=/mnt/sda/Development/github-lenny1882/claude-skills/packages/flutter-hot-reload-mac/skill/bin
SRC=/mnt/sda/Development/oi/client_hugo-boss/hugoboss-flutter-runner
: "${TMPDIR:=/tmp}"
SC=${SC:-$TMPDIR/fhrm-hb-clone}   # made and removed by this script
LOG=$TMPDIR/fhrm-mac-remaining.log
exec > >(tee "$LOG") 2>&1
pass=0; fail=0
ok(){ echo "  ok    $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1"; echo "$2" | sed 's/^/    /'; fail=$((fail+1)); }

rm -rf "$SC"
git clone -q --no-local "$SRC" "$SC" || exit 1
git -C "$SC" switch -q "$(git -C "$SRC" rev-parse --abbrev-ref HEAD)" 2>/dev/null
cp "$SRC/.maestro-drive.conf" "$SC/"
cd "$SC" || exit 1
. "$S/lib.sh" || exit 1
_pick_host || exit 1
dev=$(_dev) || exit 1; _paths "$dev"
branch=$(git rev-parse --abbrev-ref HEAD)
before=$(_ssh "git -C '$REPO' rev-parse HEAD")
echo "$(date '+%F %T') on $(_where), $dev, $REPO on $branch at ${before:0:8}"

restore() {
  echo "restore"
  bash "$S/stop.sh" 2>&1 | sed 's/^/    /'
  _ssh "rm -f '$REPO/assets/fhrm-probe.txt'"
  _ssh "cd '$REPO' && h=\$(git rev-parse HEAD)
if [ \"\$h\" != '$before' ] && [ \"\$(git log -1 --format=%s)\" = 'fhrm fast-forward test' ]; then git reset -q --soft '$before'; fi
git update-ref -d 'refs/remotes/fhrm/$branch'
echo \"    branch \$(git rev-parse --abbrev-ref HEAD) at \$(git log -1 --format='%h %s' | cut -c1-70)\"
git status --porcelain --untracked-files=no | sed 's/^/    /'"
  rm -rf "$SC"
}
trap restore EXIT

echo "1. a real fast-forward"
git -c user.name=fhrm-test -c user.email=t@example.invalid commit -q --allow-empty -m 'fhrm fast-forward test'
new=$(git rev-parse HEAD)
out=$(START_WAIT=900 bash "$S/start.sh" --build 2>&1); rc=$?
echo "$out" | sed 's/^/    /'
there=$(_ssh "git -C '$REPO' rev-parse HEAD")
[ $rc = 0 ] && [ "$there" = "$new" ] && ok "the Mac's branch moved forward to the new commit, and the app came up" \
  || no "the Mac's branch moved forward" "rc=$rc there=$there new=$new"
grep -q '^up after [0-9]*s' <<<"$out" && ok "start.sh's wait on the Mac: $(grep -o 'up after [0-9]*s' <<<"$out")" || no "start.sh says up after" "$out"

echo "5. reload, then hot restart"
out=$(bash "$S/reload.sh" 2>&1); echo "$out" | sed 's/^/    /'
grep -q 'Reloaded .* in ' <<<"$out" && ! grep -q Restarted <<<"$out" && ok "reload shows its own line" || no "reload" "$out"
out=$(bash "$S/reload.sh" restart 2>&1); echo "$out" | sed 's/^/    /'
grep -q 'Restarted application' <<<"$out" && ! grep -q Reloaded <<<"$out" && ok "restart waits for and shows its own line" || no "restart" "$out"

echo "2. one save through watch.sh"
( timeout 120 bash "$S/watch.sh" > "$TMPDIR/fhrm-rem-watch.out" 2>&1; echo "exit=$?" >> "$TMPDIR/fhrm-rem-watch.out" ) &
w=$!
sleep 4; touch lib/main_dev.dart
wait "$w"
sed 's/^/    /' "$TMPDIR/fhrm-rem-watch.out"
grep -q '^exit=0' "$TMPDIR/fhrm-rem-watch.out" && grep -q 'Reloaded 1 of' "$TMPDIR/fhrm-rem-watch.out" && grep -q '^SHOT: ' "$TMPDIR/fhrm-rem-watch.out" \
  && ok "synced, reloaded, screenshot, exit 0" || no "one save through watch.sh" "see above"

# w1 <name> — one watcher run in the background, output in $TMPDIR/fhrm-rem-<name>.out
w1(){ WO=$TMPDIR/fhrm-rem-$1.out; ( timeout 180 bash "$S/watch.sh" > "$WO" 2>&1; echo "exit=$?" >> "$WO" ) & w=$!; }
show(){ sed 's/^/    /' "$WO"; }

echo "6a. a save between two watcher runs"
touch lib/main_dev.dart                     # no watcher running now
s0=$SECONDS; w1 gap; wait "$w"; show
grep -q '^exit=0' "$WO" && grep -q 'saved: lib/main_dev.dart' "$WO" && grep -q 'Reloaded 1 of' "$WO" && [ $((SECONDS - s0)) -lt 30 ] \
  && ok "handled by the next run at once ($((SECONDS - s0))s)" || no "a save between two watcher runs" "see above"

echo "6b. an asset save"
w1 asset; sleep 4; echo "fhrm probe $(date +%s)" > assets/fhrm-probe.txt; wait "$w"; show
mac=$(_ssh "cat '$REPO/assets/fhrm-probe.txt' 2>/dev/null")
grep -q '^exit=0' "$WO" && grep -q 'Restarted application' "$WO" && grep -q 'state was reset' "$WO" && grep -q '^SHOT: ' "$WO" \
  && [ "$mac" = "$(cat assets/fhrm-probe.txt)" ] \
  && ok "rsynced to the Mac and hot restarted" || no "an asset save" "on the Mac: '$mac'"

echo "6c. a pubspec.yaml save"
sum0=$(_ssh "md5 -q '$REPO/pubspec.yaml'")
w1 pubspec; sleep 4; echo "# fhrm probe" >> pubspec.yaml; wait "$w"; show
sum1=$(_ssh "md5 -q '$REPO/pubspec.yaml'")
grep -q '^exit=4' "$WO" && grep -qx 'REBUILD: pubspec.yaml' "$WO" && ! grep -q '^SHOT: ' "$WO" && [ "$sum0" = "$sum1" ] \
  && ok "exit 4, REBUILD: pubspec.yaml, the Mac's copy untouched" || no "a pubspec.yaml save" "md5 $sum0 -> $sum1"
git checkout -q -- pubspec.yaml

echo "3. the run dies under the watcher"
( timeout 120 bash "$S/watch.sh" > "$TMPDIR/fhrm-rem-gone.out" 2>&1; echo "exit=$?" >> "$TMPDIR/fhrm-rem-gone.out" ) &
w=$!
sleep 4; bash "$S/stop.sh" | sed 's/^/    stop: /'
touch lib/main_dev.dart
wait "$w"
sed 's/^/    /' "$TMPDIR/fhrm-rem-gone.out"
grep -q '^exit=2' "$TMPDIR/fhrm-rem-gone.out" && grep -q 'has gone' "$TMPDIR/fhrm-rem-gone.out" \
  && ok "exit 2, saying the run has gone, with the end of its log" || no "run gone under the watcher" "see above"

echo "4. PROFILE"
printf 'WATCH_DIR=lib/feature\nDEV=PROFILE-DEV\n' > .maestro-drive.conf.alt
got=$(PROFILE=alt bash -c '. "$1" >/dev/null 2>&1 && echo "$WATCH_DIR $DEV"' _ "$S/lib.sh")
[ "$got" = "lib/feature PROFILE-DEV" ] && ok "a profile's values reach this skill (WATCH_DIR, DEV)" || no "PROFILE" "got: $got"
out=$(PROFILE=nope bash -c '. "$1"; echo after' _ "$S/lib.sh" 2>&1)
grep -q "profile 'nope' not found" <<<"$out" && ! grep -q after <<<"$out" && ok "a missing profile stops it, naming the file" || no "missing profile" "$out"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
