#!/bin/bash
# flutter-hot-reload-mac 2.0 on this machine: an Android emulator reached through
# maestro-drive's TRANSPORT=bridge (the default, from inside the sandbox) or
# TRANSPORT=local (sandbox off: your own terminal). A throwaway `flutter create` app in the
# scratchpad, the Pixel_6_Pro_API_34 emulator; start, reload, restart, one save
# through the watcher, status, stop. Shuts the emulator down and deletes the app
# after. Logs to $TMPDIR/fhrm-android-$TRANSPORT.log.
#
# Since f7f092d (BACKLOG items 6, 7, 9) also: start.sh's on-the-machine wait
# says "up after"; a save between two watcher runs; an asset the home page
# shows, replaced, hot restarted, the screenshot changing; a pubspec.yaml save
# exiting 4. The screenshots before and after the asset go to $SCR.
#
# Before start.sh it runs one `flutter build apk --debug -v` by itself, so a
# stalled first Gradle build says what it waits on (BACKLOG item 20). Its output
# goes to $SCR/fhrm-android-gradle.log. GRADLE_ONLY=1 stops after that build.
#
# BRIDGE_DIR and BRIDGE_HOST are what the maestro-bridge tool's `start` prints;
# SCR is this session's scratchpad. SERIAL: see the boot step.
set -uo pipefail
S=/mnt/sda/Development/github-lenny1882/claude-skills/packages/flutter-hot-reload-mac/skill/bin
: "${TRANSPORT:=bridge}"
if [ "$TRANSPORT" = bridge ]; then
  : "${BRIDGE_DIR:?set BRIDGE_DIR to the directory the bridge serves}"
  : "${BRIDGE_HOST:?set BRIDGE_HOST to the host address the bridge prints}"
else BRIDGE_DIR= BRIDGE_HOST=; fi
: "${TMPDIR:=/tmp}"
: "${SCR:?set SCR to the session scratchpad}"
GLOG=$SCR/fhrm-android-gradle.log
P=$SCR/fhrm-android-probe
LOG=$TMPDIR/fhrm-android-$TRANSPORT.log
exec > >(tee "$LOG") 2>&1
pass=0; fail=0
ok(){ echo "  ok    $1"; pass=$((pass+1)); }
no(){ echo "  FAIL  $1"; echo "$2" | sed 's/^/    /'; fail=$((fail+1)); }

rm -rf "$P" "$SCR/fhrm-rdir"; mkdir -p "$P" "$SCR/fhrm-rdir"
cat > "$P/.maestro-drive.conf" <<EOF
: "\${TRANSPORT:=$TRANSPORT}"
: "\${BRIDGE_DIR:=$BRIDGE_DIR}"
: "\${BRIDGE_HOST:=$BRIDGE_HOST}"
: "\${PLATFORM:=android}"
: "\${RUNNER:=flutter}"
: "\${APP_ID:=com.example.fhrm_probe}"
: "\${REPO:=$P}"
: "\${RDIR:=$SCR/fhrm-rdir}"
: "\${ANDROID_HOME:=/mnt/sda/User/Programs/android-sdk}"
EOF
cd "$P" || exit 1
. "$S/lib.sh" || exit 1
# png <file> <r> <g> <b> — a 64x64 PNG of one colour, for the asset check.
png(){ python3 -I -c '
import sys, zlib, struct
f, r, g, b = sys.argv[1], *map(int, sys.argv[2:])
row = b"\0" + bytes([r, g, b]) * 64
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d))
open(f, "wb").write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 64, 64, 8, 2, 0, 0, 0))
  + chunk(b"IDAT", zlib.compress(row * 64)) + chunk(b"IEND", b""))' "$@"; }
echo "$(date '+%F %T') TRANSPORT=$TRANSPORT PLATFORM=$PLATFORM REPO=$REPO RDIR=$RDIR"
serial=

# The bridge helper serves one session, but maestro-drive's SessionEnd hook in
# ANY session stops the helper named in /tmp/claude-<uid>/.maestro-bridge, which
# is shared: on 12 Nov another project's session ending stopped this run's
# bridge mid-build, and every later call hung. So check it, and fail rather
# than wait on a helper that is gone.
bridge_up() { [ "$TRANSPORT" != bridge ] || [ -f "$BRIDGE_DIR/pid" ]; }

cleanup() {
  echo "cleanup"
  bridge_up || { echo "  the bridge is down: emulator ${serial:-none} and $P left for a manual cleanup"; return; }
  [ -n "$serial" ] && { DEV=$serial bash "$S/stop.sh" 2>&1 | sed 's/^/    /'
    _ssh "adb -s '$serial' uninstall '$APP_ID' 2>&1 | tr -d '\r'" | sed 's/^/    uninstall: /'
    _ssh "sh '$PLATFORM_SH' shutdown '$serial'" 2>&1 | tail -2 | sed 's/^/    /'; }
  cd /; rm -rf "$P" "$SCR/fhrm-rdir"
}
trap cleanup EXIT

echo "flutter create"
_ssh "flutter create --org com.example --project-name fhrm_probe --platforms android '$P' 2>&1 | tail -3; flutter --version 2>/dev/null | head -1" | sed 's/^/    /'
[ -f "$P/lib/main.dart" ] && ok "app created" || { no "app created" "no lib/main.dart"; exit 1; }
# An asset the home page shows, for the asset check (BACKLOG item 7): a red
# square, replaced by a blue one later.
mkdir -p "$P/assets"; png "$P/assets/fhrm.png" 255 0 0
sed -i 's/^flutter:$/flutter:\n  assets:\n    - assets\//' "$P/pubspec.yaml"
sed -i "s/^\( *\)const Text('You have pushed the button this many times:'),/\1Image.asset('assets\/fhrm.png', width: 200, height: 200),\n\1const Text('You have pushed the button this many times:'),/" "$P/lib/main.dart"
grep -q "Image.asset('assets/fhrm.png'" "$P/lib/main.dart" && grep -q '^    - assets/$' "$P/pubspec.yaml" \
  && ok "the home page shows assets/fhrm.png" || { no "asset set up" "$(grep -n -A3 '^flutter:' "$P/pubspec.yaml"; grep -n 'pushed the button' "$P/lib/main.dart")"; exit 1; }

# Gradle first, with no emulator running. Everything here is on /dev/sda, a
# spinning disk: the AVD, the SDK and the Gradle home. A cold-booting emulator
# keeps that disk saturated, and on 12 Nov a cold build beside one was killed
# at 1500s while still merging dex. x86_64 only, the emulator's ABI: a plain
# `build apk` also runs CMake for arm64-v8a and armeabi-v7a, which `flutter run`
# on the emulator never needs. start.sh's build is then incremental.
echo "flutter build apk --debug --target-platform android-x64 -v (cold Gradle, no emulator)"
rm -f "$GLOG" "$GLOG.rc"
_ssh "cd '$P' && FL=\$(command -v flutter) && echo \"flutter: \$FL\" > '$GLOG' && { setsid nohup sh -c \"timeout 2400 '\$FL' build apk --debug --target-platform android-x64 -v >> '$GLOG' 2>&1; echo \\\$? > '$GLOG.rc'\" < /dev/null > /dev/null 2>&1 & } ; echo launched" | sed 's/^/    /'
t0=$(date +%s)
while [ ! -f "$GLOG.rc" ]; do
  sleep 15
  bridge_up || { no "gradle build alone" "the bridge stopped mid-build; the build carries on outside it"; exit 1; }
  n=$(wc -l < "$GLOG" 2>/dev/null || echo 0)
  echo "    $(( $(date +%s) - t0 ))s, $n lines: $(tail -1 "$GLOG" 2>/dev/null | cut -c1-110)"
done
grc=$(cat "$GLOG.rc")
[ "$grc" = 0 ] && ok "gradle build alone in $(( $(date +%s) - t0 ))s" || no "gradle build alone" "rc=$grc (124 = killed at 2400s); last of $GLOG:
$(tail -40 "$GLOG")"
[ "${GRADLE_ONLY:-0}" = 1 ] && { printf '\n%d passed, %d failed\n' "$pass" "$fail"; exit 0; }

echo "boot Pixel_6_Pro_API_34"
# SERIAL=emulator-NNNN uses an emulator already booted instead (it is still shut
# down at the end). A cold boot without the default_boot snapshot has taken
# over 300s here, so BOOT_TMO is 900.
if [ -n "${SERIAL:-}" ]; then serial=$SERIAL
else serial=$(TMO=960 _ssh "BOOT_TMO=900 sh '$PLATFORM_SH' boot Pixel_6_Pro_API_34" 2>"$TMPDIR/fhrm-boot.err" | tail -1); fi
case $serial in emulator-*) ok "booted $serial" ;; *) no "boot" "serial='$serial' $(tail -5 "$TMPDIR/fhrm-boot.err")"; exit 1 ;; esac
export DEV=$serial
# The emulator keeps its data across boots: on 12 Nov this run found 11 Nov's
# probe still installed, and start.sh rightly stopped at "already installed".
_ssh "adb -s '$serial' uninstall '$APP_ID' 2>&1 | tr -d '\r'" | sed 's/^/    uninstall leftover: /'

echo "start.sh (Gradle now warm)"
t0=$(date +%s)
out=$(START_WAIT=1200 bash "$S/start.sh" 2>&1); rc=$?
echo "$out" | sed 's/^/    /'
[ $rc = 0 ] && grep -q '^up after [0-9]*s' <<<"$out" && ok "up in $(( $(date +%s) - t0 ))s, without --build (the app was not installed); $(grep -o 'up after [0-9]*s' <<<"$out")" || no "start" "rc=$rc; last of the log:
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

# w1 <name> — one watcher run in the background, output in $TMPDIR/fhrm-and-<name>.out
w1(){ WO=$TMPDIR/fhrm-and-$1.out; ( timeout 180 bash "$S/watch.sh" > "$WO" 2>&1; echo "exit=$?" >> "$WO" ) & w=$!; }
show(){ sed 's/^/    /' "$WO"; }

echo "a save between two watcher runs (BACKLOG item 6)"
sed -i 's/fhrm watch test/fhrm gap test/' "$P/lib/main.dart"   # no watcher running now
s0=$SECONDS; w1 gap; wait "$w"; show
grep -q '^exit=0' "$WO" && grep -q 'saved: lib/main.dart' "$WO" && grep -q 'Reloaded 1 of' "$WO" && [ $((SECONDS - s0)) -lt 30 ] \
  && ok "handled by the next run at once ($((SECONDS - s0))s)" || no "a save between two watcher runs" "see above"
shot0=$(sed -n 's/^SHOT: //p' "$WO"); [ -s "$shot0" ] && cp "$shot0" "$SCR/android-before-asset.png"

echo "an asset save (BACKLOG item 7)"
w1 asset; sleep 5; png "$P/assets/fhrm.png" 0 0 255; wait "$w"; show
shot1=$(sed -n 's/^SHOT: //p' "$WO")
grep -q '^exit=0' "$WO" && grep -q 'saved: assets/fhrm.png' "$WO" && grep -q 'Restarted application' "$WO" && grep -q 'state was reset' "$WO" \
  && ok "hot restarted for the asset" || no "an asset save" "see above"
[ -s "$shot1" ] && cp "$shot1" "$SCR/android-after-asset.png"
[ -s "$shot0" ] && [ -s "$shot1" ] && ! cmp -s "$shot0" "$shot1" \
  && ok "the screenshot changed (compare $SCR/android-before-asset.png and android-after-asset.png)" \
  || no "the screenshot changed after the asset save" "before=$shot0 after=$shot1"

echo "a pubspec.yaml save"
w1 pubspec; sleep 5; echo "# fhrm probe" >> "$P/pubspec.yaml"; wait "$w"; show
grep -q '^exit=4' "$WO" && grep -qx 'REBUILD: pubspec.yaml' "$WO" && ! grep -q '^SHOT: ' "$WO" \
  && ok "exit 4, REBUILD: pubspec.yaml, no reload" || no "a pubspec.yaml save" "see above"

echo "stop"
out=$(bash "$S/stop.sh" 2>&1); echo "$out" | sed 's/^/    /'
left=$(_ssh "pgrep -fl '[f]run.py' ; true")
[ "$out" = stopped ] && [ -z "$left" ] && ok "stopped, nothing left running" || no "stop" "$out / $left"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
