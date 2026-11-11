#!/bin/bash
# flutter-hot-reload-mac 2.0: the checks not yet run on the Mac.
#   1. a real fast-forward: a new local commit on the branch the Mac has out
#   2. one save through watch.sh, after c3ee011 changed its PID-file read
#   3. watch.sh's exit 2 when the run dies under it
#   4. PROFILE layering reaching this skill's settings
# Works from a clone of the project in the scratchpad, so the project's own
# checkout is only read. The Mac's branch is put back to where it was.
# Logs to $TMPDIR/fhrm-mac-remaining.log.
set -uo pipefail
S=/mnt/sda/Development/github-lenny1882/claude-skills/packages/flutter-hot-reload-mac/skill/bin
SRC=/mnt/sda/Development/oi/client_hugo-boss/hugoboss-flutter-runner
SC=/tmp/claude-1000/-mnt-sda-Development-github-lenny1882-claude-skills/6e9299d0-74d4-40b8-904f-5eff596f9096/scratchpad/hb-clone
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
out=$(START_TRIES=90 bash "$S/start.sh" --build 2>&1); rc=$?
echo "$out" | sed 's/^/    /'
there=$(_ssh "git -C '$REPO' rev-parse HEAD")
[ $rc = 0 ] && [ "$there" = "$new" ] && ok "the Mac's branch moved forward to the new commit, and the app came up" \
  || no "the Mac's branch moved forward" "rc=$rc there=$there new=$new"

echo "2. one save through watch.sh"
( timeout 120 bash "$S/watch.sh" > "$TMPDIR/fhrm-rem-watch.out" 2>&1; echo "exit=$?" >> "$TMPDIR/fhrm-rem-watch.out" ) &
w=$!
sleep 4; touch lib/main_dev.dart
wait "$w"
sed 's/^/    /' "$TMPDIR/fhrm-rem-watch.out"
grep -q '^exit=0' "$TMPDIR/fhrm-rem-watch.out" && grep -q 'Reloaded 1 of' "$TMPDIR/fhrm-rem-watch.out" && grep -q '^SHOT: ' "$TMPDIR/fhrm-rem-watch.out" \
  && ok "synced, reloaded, screenshot, exit 0" || no "one save through watch.sh" "see above"

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
