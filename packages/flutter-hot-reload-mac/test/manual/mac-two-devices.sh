#!/bin/bash
# flutter-hot-reload-mac 2.0: two devices at once on the Mac, each with its own
# checkout. Run from the project directory. Cleans up after itself.
# Logs to $TMPDIR/fhrm-mac-two-devices.log.
set -uo pipefail
S=/mnt/sda/Development/github-lenny1882/claude-skills/packages/flutter-hot-reload-mac/skill/bin
LOG=$TMPDIR/fhrm-mac-two-devices.log
exec > >(tee "$LOG") 2>&1
. "$S/lib.sh" || exit 1
_pick_host || exit 1
A=$(_dev) || exit 1
B=CCF89EAD-F94B-4EC5-B3FF-FDD13AB2CE7C        # iPhone 16
C2=/tmp/fhrm-second-checkout
pass=0; fail=0
ok(){ echo "  ok    $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1"; echo "$2" | sed 's/^/    /'; fail=$((fail+1)); }
echo "$(date '+%F %T') on $(_where): A=$A ($REPO)  B=$B ($C2)"

cleanup() {
  echo "cleanup"
  DEV=$A bash "$S/stop.sh" 2>&1 | sed 's/^/    A: /'
  DEV=$B REPO=$C2 bash "$S/stop.sh" 2>&1 | sed 's/^/    B: /'
  _ssh "rm -rf '$C2'; rm -f '$RDIR/frun-$B.log'; xcrun simctl shutdown '$B' 2>&1; ls -d '$C2' 2>/dev/null; xcrun simctl list devices | grep '$B'" | sed 's/^/    /'
}
trap cleanup EXIT

echo "setup"
_ssh "git clone -q --local '$REPO' '$C2' && cp -a '$REPO/.fvm' '$C2/' && git -C '$C2' rev-parse --abbrev-ref HEAD && xcrun simctl boot '$B' 2>&1; xcrun simctl list devices booted | grep -c Booted" | sed 's/^/    /'

echo "start A ($A, $REPO)"
t0=$(date +%s)
DEV=$A START_WAIT=900 bash "$S/start.sh" --build > "$TMPDIR/fhrm-two-A.out" 2>&1; rc=$?
sed 's/^/    /' "$TMPDIR/fhrm-two-A.out"
[ $rc = 0 ] && ok "A up in $(( $(date +%s) - t0 ))s" || no "A up" "rc=$rc"

echo "start B ($B, $C2) — cold build"
t0=$(date +%s)
DEV=$B REPO=$C2 START_WAIT=1500 bash "$S/start.sh" --build > "$TMPDIR/fhrm-two-B.out" 2>&1; rc=$?
sed 's/^/    /' "$TMPDIR/fhrm-two-B.out"
[ $rc = 0 ] && ok "B up in $(( $(date +%s) - t0 ))s" || no "B up" "rc=$rc"

echo "both at once"
st=$(bash "$S/status.sh" 2>&1); echo "$st" | sed 's/^/    /'
grep -q "run:      $A  alive  from $REPO" <<<"$st" && grep -q "run:      $B  alive  from $C2" <<<"$st" \
  && ok "status shows both alive, each from its own checkout" || no "status shows both alive" "$st"
out=$(DEV=$A bash "$S/reload.sh" 2>&1); grep -q Reloaded <<<"$out" && ok "A reloads: $(tail -1 <<<"$out" | cut -c1-60)" || no "A reloads" "$out"
out=$(DEV=$B REPO=$C2 bash "$S/reload.sh" 2>&1); grep -q Reloaded <<<"$out" && ok "B reloads: $(tail -1 <<<"$out" | cut -c1-60)" || no "B reloads" "$out"
for d in "$A" "$B"; do
  _ssh "xcrun simctl io '$d' screenshot '$RDIR/two-$d.png' >/dev/null 2>&1" && _pull "$RDIR/two-$d.png" "$FLDIR/shots/two-${d:0:8}.png" \
    && echo "    shot: $FLDIR/shots/two-${d:0:8}.png"
done

echo "stop A only"
DEV=$A bash "$S/stop.sh" 2>&1 | sed 's/^/    /'
alive=$(_ssh "for u in '$A' '$B'; do [ -r '$RDIR'/frun-\$u.pid ] && read p f r < '$RDIR'/frun-\$u.pid && kill -0 \$p 2>/dev/null && echo \$u; done; true")
grep -q "$B" <<<"$alive" && ! grep -q "$A" <<<"$alive" && ok "A stopped, B still running" || no "A stopped, B still running" "alive: $alive"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
