#!/bin/bash
# flutter-hot-reload-mac 2.0 guard checks on the Mac. Run from the project
# directory. Each sets something up, expects start.sh to refuse, and undoes it.
# Logs to $TMPDIR/fhrm-mac-guards.log.
set -uo pipefail
S=/mnt/sda/Development/github-lenny1882/claude-skills/packages/flutter-hot-reload-mac/skill/bin
LOG=$TMPDIR/fhrm-mac-guards.log
exec > >(tee "$LOG") 2>&1
. "$S/lib.sh" || exit 1
_pick_host || exit 1
dev=$(_dev) || exit 1
pass=0; fail=0
ok(){ echo "  ok    $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1"; echo "$2" | sed 's/^/    /'; fail=$((fail+1)); }
expect(){ # expect <name> <pattern> — start.sh --build must exit 1 with <pattern>
  local out rc
  out=$(bash "$S/start.sh" --build 2>&1); rc=$?
  if [ $rc = 1 ] && grep -q -- "$2" <<<"$out"; then ok "$1"; echo "$out" | grep -- "$2" | head -1 | sed 's/^/          /'
  else no "$1" "rc=$rc"$'\n'"$out"; fi
}
echo "$(date '+%F %T') on $(_where), $dev, $REPO"

echo "label from another session today"
_ssh "mkdir -p '$RDIR/labels'; printf 'name=fhrm-guard-test\nby=another-session-test\n' > '$RDIR/labels/$dev'"
expect "refused, naming the session" "labelled by another session today: another-session-test"
_ssh "rm -f '$RDIR/labels/$dev'; rmdir '$RDIR/labels' 2>/dev/null; true"

echo "another live run on the same checkout"
sp=$(_ssh "nohup sleep 300 >/dev/null 2>&1 & echo \$!")
_ssh "printf '%s 0 %s\n' '$sp' '$REPO' > '$RDIR/frun-FHRM-GUARD-TEST.pid'"
expect "refused, naming the device" "is in use by a live run on FHRM-GUARD-TEST"
_ssh "kill '$sp' 2>/dev/null; rm -f '$RDIR/frun-FHRM-GUARD-TEST.pid'"

echo "a live 1.0 run"
lp=$(_ssh "nohup /bin/bash -c 'exec -a \"python3 /tmp/frun.py\" sleep 300' >/dev/null 2>&1 & echo \$!")
sleep 1
expect "refused, saying how to stop it" "1.0 run is live"
_ssh "kill '$lp' 2>/dev/null; true"

echo "uncommitted work outside WATCH_DIR"
_ssh "echo 'fhrm guard test' >> '$REPO/README.md'"
expect "refused, listing the file" "README.md"
_ssh "git -C '$REPO' checkout -q -- README.md"

echo "a commit made on the Mac"
_ssh "git -C '$REPO' -c user.name=fhrm-guard-test -c user.email=t@example.invalid commit -q --no-verify --allow-empty -m 'fhrm guard test'"
expect "refused rather than overwritten" "has commits this checkout does not"
_ssh "cd '$REPO' && [ \"\$(git log -1 --format=%s)\" = 'fhrm guard test' ] && git reset -q --soft HEAD~1"

echo "left behind"
left=$(_ssh "ls '$RDIR' | grep -E 'FHRM-GUARD|^labels\$'; pgrep -fl '[s]leep 300'; git -C '$REPO' status --porcelain --untracked-files=no | grep -vE 'Podfile.lock|pubspec.lock|^ ?M lib/'; git -C '$REPO' log -1 --format='%h %s'")
echo "$left" | sed 's/^/    /'
grep -q 'fhrm guard test\|FHRM-GUARD\|sleep 300\|README' <<<"$left" && no "nothing left behind" "$left" || ok "nothing left behind"
printf '\n%d passed, %d failed\n' "$pass" "$fail"
