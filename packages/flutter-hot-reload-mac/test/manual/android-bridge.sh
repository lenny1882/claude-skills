#!/bin/bash
# flutter-hot-reload-mac 2.0 on this machine: an Android emulator reached through
# maestro-drive's bridge transport. A throwaway `flutter create` app in the
# scratchpad, the Pixel_6_Pro_API_34 emulator; start, reload, restart, one save
# through the watcher, status, stop. Shuts the emulator down and deletes the app
# after. Logs to $TMPDIR/fhrm-android-bridge.log.
set -uo pipefail
S=/mnt/sda/Development/github-lenny1882/claude-skills/packages/flutter-hot-reload-mac/skill/bin
SCR=/tmp/claude-1000/-mnt-sda-Development-github-lenny1882-claude-skills/6e9299d0-74d4-40b8-904f-5eff596f9096/scratchpad
P=$SCR/fhrm-android-probe
LOG=$TMPDIR/fhrm-android-bridge.log
exec > >(tee "$LOG") 2>&1
pass=0; fail=0
ok(){ echo "  ok    $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1"; echo "$2" | sed 's/^/    /'; fail=$((fail+1)); }

rm -rf "$P" "$SCR/fhrm-rdir"; mkdir -p "$P" "$SCR/fhrm-rdir"
cat > "$P/.maestro-drive.conf" <<EOF
: "\${TRANSPORT:=bridge}"
: "\${BRIDGE_DIR:=/tmp/claude-1000/maestro-bridge-w3lvafk3}"
: "\${BRIDGE_HOST:=10.0.52.95}"
: "\${PLATFORM:=android}"
: "\${RUNNER:=flutter}"
: "\${APP_ID:=com.example.fhrm_probe}"
: "\${REPO:=$P}"
: "\${RDIR:=$SCR/fhrm-rdir}"
: "\${ANDROID_HOME:=/mnt/sda/User/Programs/android-sdk}"
EOF
cd "$P" || exit 1
. "$S/lib.sh" || exit 1
echo "$(date '+%F %T') TRANSPORT=$TRANSPORT PLATFORM=$PLATFORM REPO=$REPO RDIR=$RDIR"
serial=

cleanup() {
  echo "cleanup"
  [ -n "$serial" ] && { DEV=$serial bash "$S/stop.sh" 2>&1 | sed 's/^/    /'
    _ssh "sh '$PLATFORM_SH' shutdown '$serial'" 2>&1 | tail -2 | sed 's/^/    /'; }
  cd /; rm -rf "$P" "$SCR/fhrm-rdir"
}
trap cleanup EXIT

echo "flutter create"
_ssh "flutter create --org com.example --project-name fhrm_probe --platforms android '$P' 2>&1 | tail -3; flutter --version 2>/dev/null | head -1" | sed 's/^/    /'
[ -f "$P/lib/main.dart" ] && ok "app created" || { no "app created" "no lib/main.dart"; exit 1; }

echo "boot Pixel_6_Pro_API_34"
serial=$(TMO=420 _ssh "BOOT_TMO=300 sh '$PLATFORM_SH' boot Pixel_6_Pro_API_34" 2>"$TMPDIR/fhrm-boot.err" | tail -1)
case $serial in emulator-*) ok "booted $serial" ;; *) no "boot" "serial='$serial' $(tail -5 "$TMPDIR/fhrm-boot.err")"; exit 1 ;; esac
export DEV=$serial

echo "start.sh (cold Gradle build)"
t0=$(date +%s)
out=$(START_TRIES=120 START_POLL=10 bash "$S/start.sh" 2>&1); rc=$?
echo "$out" | sed 's/^/    /'
[ $rc = 0 ] && ok "up in $(( $(date +%s) - t0 ))s, without --build (the app was not installed)" || no "start" "rc=$rc; last of the log:
$(tail -30 "$RDIR/frun-$serial.log" 2>/dev/null)"
grep -q "flavour none, lib/main.dart" <<<"$out" && ok "describe: unflavoured, lib/main.dart" || no "describe" "$out"

echo "reload, restart, status"
out=$(bash "$S/reload.sh" 2>&1); grep -q Reloaded <<<"$out" && ok "reload: $(tail -1 <<<"$out" | cut -c1-60)" || no "reload" "$out"
out=$(bash "$S/reload.sh" restart 2>&1); grep -q Restarted <<<"$out" && ok "restart: $(tail -1 <<<"$out" | cut -c1-60)" || no "restart" "$out"
out=$(bash "$S/status.sh" 2>&1); echo "$out" | sed 's/^/    /'
grep -q "run:      $serial  alive" <<<"$out" && ok "status shows the run alive" || no "status" "$out"

echo "one save through watch.sh"
( timeout 180 bash "$S/watch.sh" > "$TMPDIR/fhrm-and-watch.out" 2>&1; echo "exit=$?" >> "$TMPDIR/fhrm-and-watch.out" ) &
w=$!
sleep 5; sed -i 's/Flutter Demo Home Page/fhrm watch test/' "$P/lib/main.dart"
wait "$w"
sed 's/^/    /' "$TMPDIR/fhrm-and-watch.out"
shot=$(sed -n 's/^SHOT: //p' "$TMPDIR/fhrm-and-watch.out")
grep -q '^exit=0' "$TMPDIR/fhrm-and-watch.out" && grep -q 'Reloaded 1 of' "$TMPDIR/fhrm-and-watch.out" && [ -s "$shot" ] && file "$shot" | grep -q PNG \
  && { ok "synced nothing (same checkout), reloaded, PNG screenshot"; cp "$shot" "$SCR/android-watch-shot.png"; } || no "watch" "shot=$shot"

echo "stop"
out=$(bash "$S/stop.sh" 2>&1); echo "$out" | sed 's/^/    /'
left=$(_ssh "pgrep -fl '[f]run.py' ; true")
[ "$out" = stopped ] && [ -z "$left" ] && ok "stopped, nothing left running" || no "stop" "$out / $left"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
