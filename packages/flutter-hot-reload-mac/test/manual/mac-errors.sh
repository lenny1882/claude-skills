#!/bin/bash
# flutter-hot-reload-mac: BACKLOG items 10 and 13 against a real flutter on the Mac.
#   1. a save whose first frame throws: the reload's output carries the error
#   2. a save that does not compile: answered at once, with the compile error
#   3. the edits undone: the next save reloads clean
#   4. the run dies with no save: the watcher exits 2 within WATCH_ALIVE
# Works from a clone of the project in $TMPDIR (SC), so the project's own
# checkout is only read; the probe edits go into the clone's lib/app.dart and
# reach the Mac through watch.sh's sync. The Mac's lib/ is synced back clean
# and its branch put back to where it was.
# Logs to $TMPDIR/fhrm-mac-errors.log.
set -uo pipefail
S=/mnt/sda/Development/github-lenny1882/claude-skills/packages/flutter-hot-reload-mac/skill/bin
SRC=/mnt/sda/Development/oi/client_hugo-boss/hugoboss-flutter-runner
: "${TMPDIR:=/tmp}"
SC=${SC:-$TMPDIR/fhrm-hb-errors}   # made and removed by this script
LOG=$TMPDIR/fhrm-mac-errors.log
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
  git checkout -q -- lib/app.dart
  _sync >/dev/null 2>&1 && echo "    the Mac's lib/ synced back clean"
  bash "$S/stop.sh" 2>&1 | sed 's/^/    /'
  _ssh "cd '$REPO' && git update-ref -d 'refs/remotes/fhrm/$branch'
echo \"    branch \$(git rev-parse --abbrev-ref HEAD) at \$(git log -1 --format='%h %s' | cut -c1-70)\"
git status --porcelain --untracked-files=no | sed 's/^/    /'"
  rm -rf "$SC"
}
trap restore EXIT

# save <name> — one save of lib/app.dart through watch.sh; output in $W, seconds in $secs.
save() {
  W=$TMPDIR/fhrm-err-$1.out
  ( timeout 180 bash "$S/watch.sh" > "$W" 2>&1; echo "exit=$?" >> "$W" ) &
  local w=$! t0
  sleep 4; t0=$(date +%s); touch lib/app.dart
  wait "$w"; secs=$(( $(date +%s) - t0 ))
  sed 's/^/    /' "$W"
}

echo "start"
out=$(START_WAIT=900 bash "$S/start.sh" --build 2>&1); rc=$?
echo "$out" | sed 's/^/    /'
[ $rc = 0 ] && ok "the app came up" || { no "start" "rc=$rc"; exit 1; }

echo "1. a save whose first frame throws"
# Thrown below MaterialApp, in its builder, so the error widget that replaces it
# still has a Directionality above it. Thrown above it (the first version of
# this check), the app's own error widget fails too and flutter logs the same
# exception until the reload gives up: 19,312 lines, 230 s.
grep -q '^                    child: child!,$' lib/app.dart || { no "probe site" "no 'child: child!,' in MaterialApp's builder in lib/app.dart"; exit 1; }
sed -i 's/^                    child: child!,$/                    child: Builder(builder: (_) => throw Exception('"'"'fhrm probe: thrown in build'"'"')),/' lib/app.dart
save throw
grep -q '^exit=0' "$W" && grep -q 'Reloaded .* in ' "$W" && ok "reloaded, exit 0" || no "reloaded, exit 0" "see above"
grep -q 'error from this key:' "$W" && grep -q 'fhrm probe: thrown in build' "$W" \
  && ok "the exception's text is read back" || no "the exception's text is read back" "see above; the raw lines from the run's log:
$(_ssh "grep -n 'fhrm probe' '$RLOG' | tail -5")"
grep -q '^══╡ EXCEPTION CAUGHT BY' "$W" && ok "with flutter's header line, which shares the spinner's line in the log" || no "the header line" "see above"
! grep -q $'\033' "$W" && ok "without colour codes" || no "without colour codes" "$(grep -n $'\033' "$W" | cat -v | head -3)"

echo "2. a save that does not compile"
git checkout -q -- lib/app.dart
echo 'int fhrmProbe = ;' >> lib/app.dart
save compile
grep -q '^exit=0' "$W" && [ "$secs" -lt 30 ] && ok "answered in ${secs}s, not the 60s wait" || no "answered at once" "exit and ${secs}s, see above"
grep -q 'error from this key:' "$W" && grep -q '^lib/app.dart:[0-9]*:[0-9]*: Error: ' "$W" && grep -q 'fhrmProbe' "$W" && ok "the compile error is read back" || no "the compile error is read back" "see above"

echo "3. the edits undone"
git checkout -q -- lib/app.dart
save clean
grep -q '^exit=0' "$W" && grep -q 'Reloaded .* in ' "$W" && ! grep -q 'error from this key:' "$W" \
  && ok "reloads clean, no error shown" || no "reloads clean" "see above"

echo "4. the run dies with no save"
W=$TMPDIR/fhrm-err-gone.out
( WATCH_ALIVE=5 timeout 120 bash "$S/watch.sh" > "$W" 2>&1; echo "exit=$?" >> "$W" ) &
w=$!
sleep 4
fl=$(_ssh "read p f r < '$RPID' && echo \$f")
_ssh "kill $fl"; t0=$(date +%s)
echo "    killed flutter (pid $fl) on the Mac"
wait "$w"; secs=$(( $(date +%s) - t0 ))
sed 's/^/    /' "$W"
grep -q '^exit=2' "$W" && grep -q 'has gone' "$W" && grep -q '\[frun\] flutter run exited' "$W" && ! grep -q 'saved:' "$W" && [ "$secs" -le 15 ] \
  && ok "exit 2 in ${secs}s with no save, with the end of the log" || no "exit 2 between saves" "${secs}s, see above"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
