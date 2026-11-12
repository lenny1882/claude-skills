#!/usr/bin/env bash
# Tests for flutter-hot-reload-mac.
#
# Redirects HOME and CLAUDE_DIR into a temp directory, so the real config is
# never touched. Logs to ${FHRM_TEST_LOG:-${TMPDIR:-/tmp}/flutter-hot-reload-mac-tests.log}.
#
# 2.0 sources maestro-drive's bin/lib.sh, so these tests install a stand-in
# maestro-drive under the temp CLAUDE_DIR. Its _ssh runs each script on this
# machine with sh -c — what maestro-drive's own local transport does — so
# start, watch, reload, status and stop run end to end against a fake flutter
# that prints what it was given and answers r, R and q through the pty.
#
# The last section checks the real maestro-drive, when its checkout is beside
# this repo (or at $MD_SRC): that its main branch still sets the library
# version and every function and variable this skill uses.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG=${FHRM_TEST_LOG:-${TMPDIR:-/tmp}/flutter-hot-reload-mac-tests.log}
exec > >(tee "$LOG") 2>&1
TMP=$(mktemp -d)
cleanup() {
  # Any run a failed test left behind: its frun.py, and the fake flutter under it.
  pkill -f "$TMP/" 2>/dev/null
  rm -rf "$TMP"
}
trap cleanup EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export CLAUDE_DIR="$TMP/claude"; mkdir -p "$CLAUDE_DIR/skills"
export TMPDIR="$TMP"

pass=0; fail=0
ok(){ printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s\n    %s\n' "$1" "$2"; fail=$((fail+1)); }
is(){ [ "$2" = "$3" ] && ok "$1" || no "$1" "expected '$2', got '$3'"; }

# --- the stand-in maestro-drive -------------------------------------------------
MD="$CLAUDE_DIR/skills/maestro-drive"
mkdir -p "$MD/bin" "$MD/runners/flutter" "$MD/runners/ios" "$MD/runners/ios-device"
export FAKE_RDIR="$TMP/rdir"; mkdir -p "$FAKE_RDIR"
export SSH_LOG="$TMP/ssh.log"; : > "$SSH_LOG"
cat > "$MD/bin/lib.sh" <<'SH'
# Stand-in for maestro-drive's bin/lib.sh: the functions and variables
# flutter-hot-reload-mac uses, in local transport.
MAESTRO_DRIVE_LIB_VERSION=${FAKE_MD_VERSION-1}
MAESTRO_DRIVE_CONF_FOUND=
if [ -n "${MAESTRO_DRIVE_CONF:-}" ]; then MAESTRO_DRIVE_CONF_FOUND=$MAESTRO_DRIVE_CONF
else d=$PWD; while [ "$d" != / ]; do [ -r "$d/.maestro-drive.conf" ] && { MAESTRO_DRIVE_CONF_FOUND=$d/.maestro-drive.conf; break; }; d=$(dirname "$d"); done
fi
if [ -n "$MAESTRO_DRIVE_CONF_FOUND" ]; then . "$MAESTRO_DRIVE_CONF_FOUND"; PROJECT_DIR=$(cd "$(dirname "$MAESTRO_DRIVE_CONF_FOUND")" && pwd)
else PROJECT_DIR=$PWD; fi
: "${TRANSPORT:=local}" "${MAC_HOST:=}" "${REPO:=}" "${APP_ID:=}" "${DEV:=}"
: "${RDIR:=$FAKE_RDIR}" "${LDIR:=${TMPDIR:-/tmp}}"
RMODS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../runners" && pwd)"
PLATFORM_SH="$RMODS/${PLATFORM:-ios}/platform.sh"; FRAMEWORK_SH="$RMODS/flutter/framework.sh"
SSH_OPTS=(-o BatchMode=yes)
mkdir -p "$LDIR"
_fs_shared() { [ "$TRANSPORT" != ssh ]; }
_pick_host() { return 0; }
_where() { echo this-machine; }
_ssh() { printf '%s\n----\n' "$1" >> "$SSH_LOG"; sh -c "$1"; }
_push() { cp "$1" "$2"; }
_pull() { cp "$1" "$2"; }
_dev() { if [ -n "$DEV" ]; then printf %s "$DEV"; else printf %s SIM-A; fi; }
_label_guard() { if [ "${FAKE_LABELLED:-}" = "$1" ]; then echo "$1 is labelled by another session today: cyan" >&2; return 1; fi; }
SH
cat > "$MD/runners/ios/platform.sh" <<'SH'
#!/bin/sh
case $1 in
  installed-info) [ "${FAKE_INSTALLED:-0}" = 1 ] && echo container=/x ;;
  screenshot) echo PNG > "$3" ;;
esac
# Android's installed-info exits 0 whether or not the app is there; FAKE_ANDROID
# makes this one do the same, so only its output can say.
[ "$1" != installed-info ] || [ "${FAKE_INSTALLED:-0}" = 1 ] || [ -n "${FAKE_ANDROID:-}" ]
SH
# The phone runner: what start.sh and watch.sh call on it, recording installs.
cat > "$MD/runners/ios-device/platform.sh" <<'SH'
#!/bin/sh
case $1 in
  installed-info) [ "${FAKE_INSTALLED:-0}" = 1 ] && echo version=1.0 ;;
  install) echo "install $2 $3 $4" >> "$FAKE_RDIR/phone.calls"; echo "installed  $2 ($4)" ;;
  screenshot) echo PNG > "$3" ;;
esac
[ "$1" != installed-info ] || [ "${FAKE_INSTALLED:-0}" = 1 ]
SH
cat > "$MD/runners/flutter/framework.sh" <<'SH'
#!/bin/sh
case $1 in
  device-check)
    if [ -n "${FAKE_NO_ROSETTA:-}" ]; then echo "ROSETTA IS NOT INSTALLED on this Mac" >&2; exit 1; fi
    echo "rosetta: installed"; exit 0 ;;
  run-diagnose)
    n=0
    grep -q "incorrect architecture" "$2" && { echo "ROSETTA: Flutter's bundled iproxy is x86_64"; n=1; }
    grep -q "LLDB is taking longer" "$2" && { echo "LLDB STALL: lldb attached but never handed the app on"; n=1; }
    [ $n = 1 ] || { echo "run-diagnose: no known phone failure in $2"; exit 1; } ;;
  build)
    echo "build $*" >> "$FAKE_RDIR/phone.calls"
    [ -n "${FAKE_BUILD_FAIL:-}" ] && { echo "error: no provisioning profile" >&2; exit 1; }
    echo "building for device in the GUI session (debug mode)"
    echo "artifact   $2/build/ios/iphoneos/Runner.app" ;;
  # As the real one: a reader the caller stops by its name, idevicesyslog -u <udid>.
  logs) echo "flutter: hello from $2"
        printf '%s\n' 'flutter: \134^[[90m[\M-p\M^_\M^L\M^N Easy Localization] [DEBUG] Start\134^[[0m'
        exec bash -c 'exec -a "idevicesyslog -u $1" sleep 30' _ "$2" ;;
esac
[ "$1" = describe ] || exit 0
[ -n "${FAKE_UNDECIDED:-}" ] && { echo "flavour NOT DECIDED: dev, uat" >&2; exit 1; }
printf 'FLUTTER=%s\nFLAVOR=%s\nTARGET=%s\nGEM_HOME=%s\n' "$FAKE_FLUTTER" "${FAKE_FLAVOR-dev}" "${FAKE_TARGET-lib/main_dev.dart}" "${FAKE_GEM:-}"
SH
cat > "$MD/runners/flutter/build.sh" <<'SH'
#!/bin/sh
# --debug) is what start.sh looks for: a maestro-drive with phone debug builds.
F=; T=
while [ $# -gt 0 ]; do case $1 in --flavor) F=$2; shift 2 ;; --target) T=$2; shift 2 ;; *) shift ;; esac; done
printf 'FLUTTER=%s\nFLAVOR=%s\nTARGET=%s\nGEM_HOME=\n' "$FAKE_FLUTTER" "$F" "${T:-lib/main_$F.dart}"
SH

# A fake flutter: prints its arguments and the line start.sh waits for, then
# answers keys from the pty until q.
export FAKE_FLUTTER="$TMP/bin/fake-flutter"; mkdir -p "$TMP/bin"
cat > "$FAKE_FLUTTER" <<'SH'
#!/bin/bash
echo "ARGS: $*"
echo "GEM_HOME=${GEM_HOME:-unset}"
[ -n "${FAKE_SLOW:-}" ] && sleep "$FAKE_SLOW"   # a build that takes a while
# A phone's failures, as flutter prints them (BACKLOG item 21).
[ -n "${FAKE_LLDB:-}" ] && { echo "LLDB is taking longer than expected to start debugging the app."; sleep 60; }
[ -n "${FAKE_ARCH:-}" ] && { echo "Flutter failed to run iproxy: built with the incorrect architecture"; exit 1; }
echo "Flutter run key commands."
while IFS= read -r -n1 c; do
  case $c in
    r) echo "Reloaded 1 of 1 libraries in 312ms" ;;
    R) sleep 5; echo "Restarted application in 5000ms" ;;   # longer than the 4s reload.sh once slept
    q) echo "Application finished."; exit 0 ;;
    # A reload whose first frame throws, its header coloured as flutter colours it.
    # As real flutter writes it: the spinner's line, a carriage return, then the header.
    e) printf 'Performing hot reload...   |\r\033[K\033[1m══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY ╞════\033[0m\n'
       echo "The following _Exception was thrown building Banner:"
       echo "Exception: banner text is null"
       echo "════════════════════════════════════════"
       echo "Reloaded 1 of 1 libraries in 298ms" ;;
    # A reload that does not compile: flutter prints no "Reloaded" line at all.
    # Each error line after the spinner on the same line, in red, as on the Mac.
    c) printf 'Performing hot reload...   /\r\033[K\033[31mlib/main.dart:3:1: Error: Expected an identifier.\033[39m\n'
       printf 'Performing hot reload...   -\r\033[K\033[31mint fhrmProbe = ;\033[39m\n'
       printf '\033[1mTry again after fixing the above error(s).\033[22m\n' ;;
    # The app's own output mentions an exception before the reload answers.
    x) echo "flutter: caught Exception in a retry, carrying on"; sleep 2
       echo "Reloaded 1 of 1 libraries in 2001ms" ;;
    # A key flutter never answers, leaving a coloured spinner line in the log.
    n) printf 'Performing hot reload...  \033[1m|\010/\r\033[K\n' ;;
    # A long error: more lines than reload.sh prints.
    l) echo "Unhandled Exception: deep"; for i in $(seq 1 50); do echo "#$i frame"; done
       echo "Reloaded 1 of 1 libraries in 310ms" ;;
  esac
done
SH
chmod +x "$FAKE_FLUTTER"

# The kit's installer tests install into CLAUDE_DIRs of their own, which have no
# maestro-drive in them; this points the probe at the stand-in wherever it runs.
export FHRM_MAESTRO_DRIVE="$MD"
. "$REPO/test/installer-tests.sh"
unset FHRM_MAESTRO_DRIVE

BIN="$REPO/skill/bin"
export START_POLL=0.3 START_WAIT=12 START_CHUNK=3 WATCH_POLL=0.2
unset MAESTRO_DRIVE_CONF DEV MAC_HOST FLAVOR TARGET FLUTTER_BIN WATCH_DIR LDIR BUILD_FLAVOR BUILD_TARGET

# q <dir> <snippet> — source lib.sh from <dir>, then run <snippet>.
q(){ ( cd "$1" && bash -c '. "$1" >/dev/null && eval "$2"' _ "$BIN/lib.sh" "$2" ) 2>"$TMP/qerr"; }

echo "parsing"
for f in "$BIN"/*.sh; do
  bash -n "$f" && ok "bin/$(basename "$f") parses" || no "bin/$(basename "$f") parses" "syntax error"
done
python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' "$REPO/skill/remote/frun.py" \
  && ok "remote/frun.py parses" || no "remote/frun.py parses" "syntax error"

echo "loading maestro-drive"
W="$TMP/work"; mkdir -p "$W"
out=$(cd "$W" && FHRM_MAESTRO_DRIVE="$TMP/nowhere" bash -c '. "$1"; echo after' _ "$BIN/lib.sh" 2>&1)
grep -q "needs maestro-drive, and $TMP/nowhere/bin/lib.sh is missing" <<<"$out" && ! grep -q after <<<"$out" \
  && ok "without maestro-drive it stops, naming the path" || no "without maestro-drive it stops, naming the path" "$out"
out=$(cd "$W" && FAKE_MD_VERSION=2 bash -c '. "$1"; echo after' _ "$BIN/lib.sh" 2>&1)
grep -q "library version 2, and this needs 1" <<<"$out" && ! grep -q after <<<"$out" \
  && ok "a different library version stops it" || no "a different library version stops it" "$out"
out=$(cd "$W" && FAKE_MD_VERSION= bash -c '. "$1"; echo after' _ "$BIN/lib.sh" 2>&1)
grep -q "library version none" <<<"$out" \
  && ok "so does a maestro-drive with no library version (2.1.1 and earlier)" || no "so does a maestro-drive with no library version" "$out"
is "FHRM_MAESTRO_DRIVE points it elsewhere" "$MD/bin/lib.sh" "$(FHRM_MAESTRO_DRIVE="$MD" q "$W" 'echo "$MD_LIB"')"

echo "settings"
A="$W/app"; mkdir -p "$A/lib/deep"
printf 'REPO=/r\nAPP_ID=a\nWATCH_DIR=src\n' > "$A/.maestro-drive.conf"
is "WATCH_DIR from the conf" "src" "$(q "$A/lib/deep" 'echo "$WATCH_DIR"')"
is "an exported WATCH_DIR beats a plain line in the conf" "lib/x" "$(WATCH_DIR=lib/x q "$A" 'echo "$WATCH_DIR"')"
printf 'REPO=/r\nAPP_ID=a\n' > "$A/.maestro-drive.conf"
is "WATCH_DIR defaults to lib" "lib" "$(q "$A" 'echo "$WATCH_DIR"')"
is "1.0's FLAVOR becomes BUILD_FLAVOR" "uat|" "$(FLAVOR=uat q "$A" 'echo "$BUILD_FLAVOR|$FHRM_NO_FLAVOR"')"
grep -q "FLAVOR is 1.0's name" "$TMP/qerr" && ok "and says to rename it" || no "and says to rename it" "$(cat "$TMP/qerr")"
is "1.0's FLAVOR= still means unflavoured" "|1" "$(FLAVOR= q "$A" 'echo "$BUILD_FLAVOR|$FHRM_NO_FLAVOR"')"
is "BUILD_FLAVOR wins over FLAVOR" "prod" "$(BUILD_FLAVOR=prod FLAVOR=uat q "$A" 'echo "$BUILD_FLAVOR"')"
is "1.0's TARGET becomes BUILD_TARGET" "lib/m.dart" "$(TARGET=lib/m.dart q "$A" 'echo "$BUILD_TARGET"')"
FLUTTER_BIN=x q "$A" true
grep -q "FLUTTER_BIN is ignored" "$TMP/qerr" && ok "FLUTTER_BIN is ignored, saying so" || no "FLUTTER_BIN is ignored, saying so" "$(cat "$TMP/qerr")"
is "paths are per device" "$FAKE_RDIR/frun-U1.in $FAKE_RDIR/frun-U1.log $FAKE_RDIR/frun-U1.pid" \
  "$(q "$A" '_paths U1; echo "$RFIFO $RLOG $RPID"')"
is "where the filesystem is shared, frun.py runs from the skill" "$REPO/skill/remote/frun.py" "$(q "$A" 'echo "$RPY"')"
is "across ssh it is pushed into RDIR" "$FAKE_RDIR/frun.py" "$(TRANSPORT=ssh q "$A" 'echo "$RPY"')"

echo "frun.py"
F="$TMP/frun"; mkdir -p "$F"
frun(){ # frun <flavor> <gem> — run to completion: q is sent as soon as it is up
  rm -f "$F/log"
  ( FRUN_REPO="$F" FRUN_DEV=UDID1 FRUN_FLUTTER="$FAKE_FLUTTER" FRUN_FLAVOR="$1" FRUN_GEM_HOME="$2" \
    FRUN_TARGET=lib/main_dev.dart FRUN_FIFO="$F/in" FRUN_LOG="$F/log" FRUN_PID="$F/pid" \
    timeout 20 python3 "$REPO/skill/remote/frun.py" >/dev/null 2>&1 & )
  for _ in $(seq 1 50); do grep -q "key commands" "$F/log" 2>/dev/null && break; sleep 0.1; done
  printf q > "$F/in"
  for _ in $(seq 1 50); do grep -q "flutter run exited" "$F/log" 2>/dev/null && break; sleep 0.1; done
}
frun dev ""
grep -q -- "ARGS: run --flavor dev -d UDID1 -t lib/main_dev.dart" "$F/log" \
  && ok "--flavor goes before -d, and reaches flutter through the pty" || no "--flavor goes before -d" "$(head -3 "$F/log")"
grep -q "GEM_HOME=unset" "$F/log" && ok "no GEM_HOME unless describe gave one" || no "no GEM_HOME unless describe gave one" "$(grep GEM "$F/log")"
grep -q "flutter run exited" "$F/log" && ok "the log records the exit" || no "the log records the exit" "$(tail -2 "$F/log")"
[ ! -e "$F/pid" ] && [ ! -e "$F/in" ] && ok "the pid file and fifo are removed on exit" || no "the pid file and fifo are removed on exit" "$(ls "$F")"
frun "" "$TMP/gems"
grep -q -- "ARGS: run -d UDID1 -t lib/main_dev.dart" "$F/log" && ! grep -q -- "--flavor" "$F/log" \
  && ok "an empty flavour passes no --flavor" || no "an empty flavour passes no --flavor" "$(head -3 "$F/log")"
grep -q "GEM_HOME=$TMP/gems" "$F/log" && ok "a GEM_HOME from describe is set" || no "a GEM_HOME from describe is set" "$(grep GEM "$F/log")"

# --- end to end, in local transport -----------------------------------------------
# P is the project being edited; B is the checkout the build reads, a clone of P.
P="$TMP/proj"; B="$TMP/build"; B2="$TMP/build2"
git init -q "$P"; mkdir -p "$P/lib" "$P/assets" "$P/ios/Runner" "$P/ios/Pods"
echo "void main() {}" > "$P/lib/main.dart"; echo readme > "$P/README"
echo png1 > "$P/assets/logo.png"; echo "name: app" > "$P/pubspec.yaml"
echo plist > "$P/ios/Runner/Info.plist"; echo pod > "$P/ios/Pods/x"
git -C "$P" add -A; git -C "$P" -c user.name=t -c user.email=t@t commit -qm one
git -C "$P" branch -M main
for c in "$B" "$B2"; do
  # Left at git's default, as on the Mac: a push to the checked-out branch is refused.
  git clone -q "$P" "$c"
done
git -C "$P" switch -qc feature
cat > "$P/.maestro-drive.conf" <<EOF
: "\${REPO:=$B}"
: "\${APP_ID:=com.example.app}"
EOF
st(){ ( cd "$P" && bash "$BIN/$1.sh" "${@:2}" ) >"$TMP/out" 2>&1; }
pid_of(){ cut -d' ' -f1 "$FAKE_RDIR/frun-$1.pid" 2>/dev/null; }

echo "start.sh — refusals"
FAKE_INSTALLED=1 st start; rc=$?
[ $rc = 3 ] && grep -q "that is maestro-drive" "$TMP/out" && grep -q -- "--build" "$TMP/out" \
  && ok "an app already installed stops at exit 3, pointing to maestro-drive and --build" \
  || no "an app already installed stops at exit 3" "rc=$rc $(cat "$TMP/out")"
[ ! -e "$FAKE_RDIR/frun-SIM-A.pid" ] && ok "and nothing was launched" || no "and nothing was launched" "pid file exists"
FAKE_LABELLED=SIM-A st start --build; rc=$?
[ $rc = 1 ] && grep -q "labelled by another session" "$TMP/out" \
  && ok "a device another session labelled today is refused" || no "a device another session labelled today is refused" "rc=$rc $(cat "$TMP/out")"
FAKE_UNDECIDED=1 st start --build; rc=$?
[ $rc = 1 ] && grep -q "NOT DECIDED" "$TMP/out" && grep -q "Set BUILD_FLAVOR" "$TMP/out" \
  && ok "an undecided flavour is refused, with maestro-drive's reason" || no "an undecided flavour is refused" "rc=$rc $(cat "$TMP/out")"

# A 1.0 run: any process whose command line has /tmp/frun.py in it.
( exec -a "python3 /tmp/frun.py $TMP/" sleep 30 ) & legacy=$!
sleep 0.3
st start --build; rc=$?
kill "$legacy" 2>/dev/null; wait "$legacy" 2>/dev/null
[ $rc = 1 ] && grep -q "1.0 run is live" "$TMP/out" \
  && ok "a live 1.0 run is refused, saying how to stop it" || no "a live 1.0 run is refused" "rc=$rc $(cat "$TMP/out")"

FAKE_ANDROID=1 FAKE_INSTALLED=0 st start; rc=$?
[ $rc = 0 ] && ok "an installed-info that exits 0 but prints nothing is not 'installed' (Android)" \
  || no "an installed-info that exits 0 but prints nothing is not 'installed'" "rc=$rc $(cat "$TMP/out")"
st stop

echo "start.sh — a run"
echo "// edited" >> "$P/lib/main.dart"
st start --build; rc=$?
[ $rc = 0 ] && grep -q "^up" "$TMP/out" && ok "starts and waits for the app" || no "starts and waits for the app" "rc=$rc $(cat "$TMP/out")"
: > "$SSH_LOG"; FAKE_SLOW=4 st start --build; rc=$?
n=$(grep -c "key commands" "$SSH_LOG")
[ $rc = 0 ] && [ "$n" -le 2 ] && grep -q "^up after" "$TMP/out" \
  && ok "a 4s build is waited for in $n connections, not one per look" \
  || no "a slow build is waited for in few connections" "rc=$rc n=$n $(cat "$TMP/out")"
FAKE_SLOW=30 START_WAIT=4 st start --build; rc=$?
[ $rc = 1 ] && grep -q "gave up waiting after [4-9]s" "$TMP/out" \
  && ok "and gives up after START_WAIT" || no "and gives up after START_WAIT" "rc=$rc $(cat "$TMP/out")"
st start --build
is "the build checkout is on the project's branch" "feature" "$(git -C "$B" rev-parse --abbrev-ref HEAD)"
grep -q "// edited" "$B/lib/main.dart" && ok "WATCH_DIR is synced, uncommitted edits included" || no "WATCH_DIR is synced" "$(cat "$B/lib/main.dart")"
grep -q -- "ARGS: run --flavor dev -d SIM-A -t lib/main_dev.dart" "$FAKE_RDIR/frun-SIM-A.log" \
  && ok "flavour and entry file come from maestro-drive's describe" || no "flavour and entry file come from describe" "$(head -3 "$FAKE_RDIR/frun-SIM-A.log")"
read -r _p _f _r < "$FAKE_RDIR/frun-SIM-A.pid"
[ "$_r" = "$B" ] && kill -0 "$_p" && kill -0 "$_f" && ok "the pid file holds frun.py, flutter and the checkout" || no "the pid file holds frun.py, flutter and the checkout" "$(cat "$FAKE_RDIR/frun-SIM-A.pid")"
BUILD_FLAVOR=uat st start --build
grep -q -- "ARGS: run --flavor uat -d SIM-A -t lib/main_uat.dart" "$FAKE_RDIR/frun-SIM-A.log" \
  && ok "BUILD_FLAVOR overrides describe" || no "BUILD_FLAVOR overrides describe" "$(head -3 "$FAKE_RDIR/frun-SIM-A.log")"
grep -q "stopping this device's previous run (pid $_p)" "$TMP/out" && ! kill -0 "$_p" 2>/dev/null && ! kill -0 "$_f" 2>/dev/null \
  && ok "a restart stops this device's previous run, flutter included" || no "a restart stops this device's previous run" "$(cat "$TMP/out")"
FAKE_INSTALLED=1 st start; rc=$?
[ $rc = 0 ] && ok "an installed app does not stop a restart while this skill's run is live" || no "an installed app does not stop a restart" "rc=$rc $(cat "$TMP/out")"

echo "reload.sh and status.sh"
st reload; grep -q "Reloaded 1 of 1 libraries" "$TMP/out" && ok "r reloads" || no "r reloads" "$(cat "$TMP/out")"
st reload restart; grep -q "Restarted application" "$TMP/out" && ! grep -q Reloaded "$TMP/out" \
  && ok "restart waits for its own answer, past 4s" || no "restart waits for its own answer, past 4s" "$(cat "$TMP/out")"
st reload; grep -q "Reloaded 1 of 1" "$TMP/out" && ! grep -q Restarted "$TMP/out" \
  && ok "and the next reload shows only its own line" || no "and the next reload shows only its own line" "$(cat "$TMP/out")"
st reload; ! grep -q "error from this key" "$TMP/out" \
  && ok "a clean reload shows no error" || no "a clean reload shows no error" "$(cat "$TMP/out")"
st reload e
grep -q "Reloaded 1 of 1 libraries in 298ms" "$TMP/out" && grep -q "error from this key:" "$TMP/out" \
  && grep -q "^══╡ EXCEPTION CAUGHT BY WIDGETS LIBRARY" "$TMP/out" && grep -q "Exception: banner text is null" "$TMP/out" \
  && ok "an exception the reload threw is read back, with its text" || no "an exception the reload threw is read back" "$(cat "$TMP/out")"
! grep -q $'\033' "$TMP/out" && ! grep -q $'\r' "$TMP/out" \
  && ok "without colour codes or carriage returns" || no "without colour codes or carriage returns" "$(cat -v "$TMP/out")"
s0=$SECONDS; st reload c; rc=$?
[ $rc = 0 ] && [ $((SECONDS - s0)) -lt 10 ] && grep -q "Try again after fixing" "$TMP/out" && grep -qx "lib/main.dart:3:1: Error: Expected an identifier." "$TMP/out" \
  && grep -qx "int fhrmProbe = ;" "$TMP/out" \
  && ok "a compile error answers at once, with its error" || no "a compile error answers at once" "rc=$rc $((SECONDS - s0))s $(cat "$TMP/out")"
st reload x
grep -q "in 2001ms" "$TMP/out" && ok "the app's own 'Exception' line does not end the wait early" || no "the app's own 'Exception' line does not end the wait early" "$(cat "$TMP/out")"
RELOAD_ERR_LINES=5 st reload l
[ "$(grep -c ' frame$' "$TMP/out")" = 4 ] && grep -q "46 more lines in $FAKE_RDIR/frun-SIM-A.log" "$TMP/out" \
  && ok "a long error is cut at RELOAD_ERR_LINES, naming the log" || no "a long error is cut at RELOAD_ERR_LINES" "$(cat "$TMP/out")"
RELOAD_TMO=2 st reload n; rc=$?
[ $rc = 1 ] && grep -q "no answer from flutter after 2s" "$TMP/out" && grep -q "Performing hot reload" "$TMP/out" \
  && ! grep -q $'[\033\r\010]' "$TMP/out" \
  && ok "no answer: exit 1 with the last of the log, its terminal codes taken out" || no "no answer: the last of the log, cleaned" "rc=$rc $(cat -v "$TMP/out")"
DEV=SIM-Z st reload; rc=$?
[ $rc = 1 ] && grep -q "no run is listening on SIM-Z" "$TMP/out" && ok "a device with no run says so" || no "a device with no run says so" "rc=$rc $(cat "$TMP/out")"
st status
grep -q "run:      SIM-A  alive  from $B" "$TMP/out" && grep -q "branch:   feature" "$TMP/out" \
  && ok "status names the device, the checkout and the branch" || no "status names the device, the checkout and the branch" "$(cat "$TMP/out")"

echo "watch.sh"
( cd "$P" && timeout 30 bash "$BIN/watch.sh" > "$TMP/watch.out" 2>&1; echo "rc=$?" >> "$TMP/watch.out" ) &
wpid=$!
sleep 1; echo "// saved" >> "$P/lib/main.dart"
wait "$wpid"
grep -q "rc=0" "$TMP/watch.out" && grep -q "Reloaded" "$TMP/watch.out" && grep -q "// saved" "$B/lib/main.dart" \
  && ok "one save is synced, reloaded, and the watcher exits" || no "one save is synced, reloaded, and the watcher exits" "$(cat "$TMP/watch.out")"
shot=$(sed -n 's/^SHOT: //p' "$TMP/watch.out")
[ -n "$shot" ] && [ "$(cat "$shot" 2>/dev/null)" = PNG ] && ok "and the screenshot is fetched" || no "and the screenshot is fetched" "shot=$shot"

# watch1 [env...] — one watcher run in the background; wait for it with wait1.
watch1(){ ( cd "$P" && env "$@" timeout 30 bash "$BIN/watch.sh" > "$TMP/watch.out" 2>&1; echo "rc=$?" >> "$TMP/watch.out" ) & wpid=$!; }
wait1(){ wait "$wpid"; }
sleep 1.1; echo "// in the gap" >> "$P/lib/main.dart"    # saved with no watcher running
s0=$SECONDS; watch1 WATCH_ALIVE=0; wait1
grep -q "rc=0" "$TMP/watch.out" && grep -q "saved: lib/main.dart" "$TMP/watch.out" && grep -q "// in the gap" "$B/lib/main.dart" \
  && [ $((SECONDS - s0)) -lt 5 ] \
  && ok "a save made between two watcher runs is handled by the next one at once" \
  || no "a save made between two watcher runs is handled by the next one" "$(cat "$TMP/watch.out")"
( cd "$P" && WATCH_ALIVE=0 timeout 3 bash "$BIN/watch.sh" ) > "$TMP/out" 2>&1; rc=$?
[ $rc = 124 ] && ! grep -q saved "$TMP/out" && ok "and is not replayed by the run after that" || no "and is not replayed by the run after that" "rc=$rc $(cat "$TMP/out")"

watch1 WATCH_ALIVE=0; sleep 1; echo png2 > "$P/assets/logo.png"; wait1
grep -q "rc=0" "$TMP/watch.out" && grep -q "Restarted application" "$TMP/watch.out" && grep -q "state was reset" "$TMP/watch.out" \
  && [ "$(cat "$B/assets/logo.png")" = png2 ] \
  && ok "an asset is synced and hot restarted, saying the state went" || no "an asset is synced and hot restarted" "$(cat "$TMP/watch.out")"
watch1 WATCH_ALIVE=0; sleep 1; echo "version: 2" >> "$P/pubspec.yaml"; wait1
grep -q "rc=4" "$TMP/watch.out" && grep -qx "REBUILD: pubspec.yaml" "$TMP/watch.out" && grep -q "start.sh --build" "$TMP/watch.out" \
  && ! grep -q "version: 2" "$B/pubspec.yaml" && ! grep -q SHOT "$TMP/watch.out" \
  && ok "pubspec.yaml is not synced or reloaded: REBUILD, exit 4" || no "pubspec.yaml: REBUILD, exit 4" "$(cat "$TMP/watch.out")"
git -C "$P" checkout -q -- pubspec.yaml
( cd "$P" && WATCH_ALIVE=0 timeout 3 bash "$BIN/watch.sh" ) > "$TMP/out" 2>&1; rc=$?
[ $rc = 124 ] && ! grep -q REBUILD "$TMP/out" \
  && ok "pubspec.yaml put back to HEAD with git checkout is not a REBUILD" || no "pubspec.yaml back to HEAD is not a REBUILD" "rc=$rc $(cat "$TMP/out")"
watch1 WATCH_ALIVE=0; sleep 1; echo "// both" >> "$P/lib/main.dart"; echo x >> "$P/ios/Runner/Info.plist"; wait1
grep -q "rc=4" "$TMP/watch.out" && grep -q "Reloaded" "$TMP/watch.out" && grep -qx "REBUILD: ios/Runner/Info.plist" "$TMP/watch.out" \
  && ok "code and native code saved together: reloaded, and the native file listed" || no "code and native code together" "$(cat "$TMP/watch.out")"
echo y >> "$P/ios/Pods/x"; mkdir -p "$P/lib/.hidden"; echo z > "$P/lib/main.dart~"
( cd "$P" && WATCH_ALIVE=0 timeout 3 bash "$BIN/watch.sh" ) > "$TMP/out" 2>&1; rc=$?
[ $rc = 124 ] && ! grep -qE "saved|REBUILD" "$TMP/out" && ok "ios/Pods and editor backups are not saves" || no "ios/Pods and editor backups are not saves" "rc=$rc $(cat "$TMP/out")"
rm -f "$P/lib/main.dart~"; rmdir "$P/lib/.hidden"

read -r _ wf _ < "$FAKE_RDIR/frun-SIM-A.pid"
( cd "$P" && WATCH_ALIVE=1 timeout 30 bash "$BIN/watch.sh" > "$TMP/watch.out" 2>&1; echo "rc=$?" >> "$TMP/watch.out" ) &
wpid=$!
sleep 1.5; kill "$wf"; s0=$SECONDS
wait "$wpid"
grep -q "rc=2" "$TMP/watch.out" && grep -q "has gone" "$TMP/watch.out" && grep -q "^\[frun\] flutter run exited" "$TMP/watch.out" \
  && [ $((SECONDS - s0)) -lt 6 ] \
  && ok "a run that dies between saves is reported within WATCH_ALIVE, with its log" \
  || no "a run that dies between saves is reported within WATCH_ALIVE" "$((SECONDS - s0))s $(cat "$TMP/watch.out")"
( cd "$P" && WATCH_ALIVE=0 timeout 4 bash "$BIN/watch.sh" ) > /dev/null 2>&1; rc=$?
[ $rc = 2 ] && ok "and a watcher started after it says there is no run" || no "and a watcher started after it says there is no run" "rc=$rc"
st start --build

echo "two devices, one checkout"
DEV=SIM-B FAKE_INSTALLED=0 st start --build; rc=$?
[ $rc = 1 ] && grep -q "$B is in use by a live run on SIM-A" "$TMP/out" && grep -q "PROFILE" "$TMP/out" \
  && ok "a second device on the same checkout is refused, pointing to a profile" || no "a second device on the same checkout is refused" "rc=$rc $(cat "$TMP/out")"
DEV=SIM-B REPO="$B2" st start --build; rc=$?
[ $rc = 0 ] && kill -0 "$(pid_of SIM-A)" && kill -0 "$(pid_of SIM-B)" \
  && ok "with its own checkout, both run at once" || no "with its own checkout, both run at once" "rc=$rc $(cat "$TMP/out")"
DEV=SIM-B st reload; grep -q "Reloaded" "$TMP/out" && ok "each device has its own fifo" || no "each device has its own fifo" "$(cat "$TMP/out")"

echo "stop.sh"
a=$(pid_of SIM-A); read -r _ af _ < "$FAKE_RDIR/frun-SIM-A.pid"
st stop
grep -q "^stopped" "$TMP/out" && ! kill -0 "$a" 2>/dev/null && ! kill -0 "$af" 2>/dev/null \
  && ok "stops this device's frun.py and its flutter" || no "stops this device's frun.py and its flutter" "$(cat "$TMP/out")"
kill -0 "$(pid_of SIM-B)" 2>/dev/null && ok "and leaves the other device's run alone" || no "and leaves the other device's run alone" "SIM-B is gone"
st stop; grep -q "nothing was running on SIM-A" "$TMP/out" && ok "a second stop says nothing was running" || no "a second stop says nothing was running" "$(cat "$TMP/out")"
( cd "$P" && timeout 10 bash "$BIN/watch.sh" ) > "$TMP/out" 2>&1; rc=$?
[ $rc = 2 ] && grep -q "bin/start.sh first" "$TMP/out" && ok "watch.sh with no run exits 2" || no "watch.sh with no run exits 2" "rc=$rc $(cat "$TMP/out")"
DEV=SIM-B st stop

echo "the branch on a shared checkout"
git -C "$P" switch -q main
git -C "$B" switch -q main 2>/dev/null || git -C "$B" checkout -q -f main
echo "theirs" >> "$B/README"; echo "// synced before" >> "$B/lib/main.dart"; echo synced > "$B/assets/logo.png"
git -C "$P" switch -q feature
st start --build; rc=$?
[ $rc = 1 ] && grep -q "uncommitted changes" "$TMP/out" && grep -q "README" "$TMP/out" && ! grep -q "lib/main.dart" "$TMP/out" \
  && ok "uncommitted work outside WATCH_DIR stops the checkout, listing it" || no "uncommitted work outside WATCH_DIR stops the checkout" "rc=$rc $(cat "$TMP/out")"
is "and the build checkout stays where it was" "main" "$(git -C "$B" rev-parse --abbrev-ref HEAD)"
grep -q theirs "$B/README" && ok "with the work intact" || no "with the work intact" "README changed"
git -C "$B" checkout -q -- README
st start --build; rc=$?
[ $rc = 0 ] && [ "$(git -C "$B" rev-parse --abbrev-ref HEAD)" = feature ] \
  && [ "$(cat "$B/assets/logo.png")" = "$(cat "$P/assets/logo.png")" ] \
  && ok "changes only inside WATCH_DIR and WATCH_ASSETS do not stop it, and both are synced" || no "changes only inside WATCH_DIR do not stop it" "rc=$rc $(cat "$TMP/out")"
echo "readme 2" > "$P/README"; git -C "$P" -c user.name=t -c user.email=t@t commit -qam two
st start --build; rc=$?
[ $rc = 0 ] && [ "$(git -C "$B" rev-parse HEAD)" = "$(git -C "$P" rev-parse HEAD)" ] && [ "$(cat "$B/README")" = "readme 2" ] \
  && ok "a new commit on the branch already checked out there fast-forwards it" \
  || no "a new commit on the branch already checked out there fast-forwards it" "rc=$rc $(cat "$TMP/out")"
echo theirs > "$B/other.txt"; git -C "$B" add other.txt; git -C "$B" -c user.name=t -c user.email=t@t commit -qm theirs
st start --build; rc=$?
[ $rc = 1 ] && grep -q "has commits this checkout does not" "$TMP/out" && [ -f "$B/other.txt" ] \
  && ok "a commit made there is not overwritten" || no "a commit made there is not overwritten" "rc=$rc $(cat "$TMP/out")"
st stop

echo "a phone (PLATFORM=ios-device)"
ph(){ ( cd "$P" && PLATFORM=ios-device DEV=PHONE-1 bash "$BIN/$1.sh" "${@:2}" ) >"$TMP/out" 2>&1; }
rm -f "$FAKE_RDIR/phone.calls"
MDOLD="$TMP/md-old"; cp -r "$MD" "$MDOLD"; sed -i '/^  device-check)/,/exit 0 ;;$/d' "$MDOLD/runners/flutter/framework.sh"
( cd "$P" && FHRM_MAESTRO_DRIVE="$MDOLD" PLATFORM=ios-device DEV=PHONE-1 bash "$BIN/start.sh" --build --no-branch ) >"$TMP/out" 2>&1; rc=$?
[ $rc = 1 ] && grep -q "no phone hot-reload support" "$TMP/out" && [ ! -e "$FAKE_RDIR/phone.calls" ] \
  && ok "a maestro-drive without the phone commands is refused, saying to update it" || no "an old maestro-drive is refused" "rc=$rc $(cat "$TMP/out")"
FAKE_NO_ROSETTA=1 ph start --build --no-branch; rc=$?
[ $rc = 1 ] && grep -q "ROSETTA IS NOT INSTALLED" "$TMP/out" && grep -q "nothing was changed" "$TMP/out" \
  && [ ! -e "$FAKE_RDIR/phone.calls" ] && [ ! -e "$FAKE_RDIR/frun-PHONE-1.pid" ] \
  && ok "device-check refusing stops it before the build, saying why" || no "device-check refusing stops it" "rc=$rc $(cat "$TMP/out")"
FAKE_BUILD_FAIL=1 ph start --build --no-branch; rc=$?
[ $rc = 1 ] && grep -q "the phone build failed" "$TMP/out" && grep -q "no provisioning profile" "$TMP/out" && [ ! -e "$FAKE_RDIR/frun-PHONE-1.pid" ] \
  && ok "a failed phone build stops it with the build's own error" || no "a failed phone build" "rc=$rc $(cat "$TMP/out")"
rm -f "$FAKE_RDIR/phone.calls"
ph start --build --no-branch; rc=$?
[ $rc = 0 ] && grep -q "^up after" "$TMP/out" && ok "a phone run comes up" || no "a phone run comes up" "rc=$rc $(cat "$TMP/out")"
grep -q -- "build $B --platform ios-device --device PHONE-1 --mode debug --app-id com.example.app --variant dev --target lib/main_dev.dart" "$FAKE_RDIR/phone.calls" \
  && ok "built by maestro-drive: --platform ios-device --device --mode debug" || no "built by maestro-drive" "$(cat "$FAKE_RDIR/phone.calls")"
grep -q "^install PHONE-1 $B/build/ios/iphoneos/Runner.app com.example.app" "$FAKE_RDIR/phone.calls" \
  && ok "the built .app is installed on the phone" || no "the built .app is installed" "$(cat "$FAKE_RDIR/phone.calls")"
grep -q -- "ARGS: run --flavor dev -d PHONE-1 -t lib/main_dev.dart --debug --use-application-binary $B/build/ios/iphoneos/Runner.app" "$FAKE_RDIR/frun-PHONE-1.log" \
  && ok "flutter run gets --use-application-binary with that .app" || no "flutter run gets --use-application-binary" "$(head -2 "$FAKE_RDIR/frun-PHONE-1.log")"
ph reload; grep -q "Reloaded 1 of 1" "$TMP/out" && ok "a phone run reloads" || no "a phone run reloads" "$(cat "$TMP/out")"
( cd "$P" && PLATFORM=ios-device DEV=PHONE-1 WATCH_ALIVE=0 timeout 30 bash "$BIN/watch.sh" > "$TMP/watch.out" 2>&1; echo "rc=$?" >> "$TMP/watch.out" ) & wpid=$!
sleep 1; echo "// phone save" >> "$P/lib/main.dart"; wait "$wpid"
shot=$(sed -n 's/^SHOT: //p' "$TMP/watch.out")
grep -q "rc=0" "$TMP/watch.out" && [ "$(cat "$shot" 2>/dev/null)" = PNG ] \
  && ok "a save on a phone run reloads and screenshots through the phone runner" || no "a save on a phone run" "$(cat "$TMP/watch.out")"
s0=$SECONDS; ph logs 1; f=$(sed -n 's/.* -> //p' "$TMP/out" | head -1)
grep -q "flutter: hello from PHONE-1" "$f" 2>/dev/null && grep -qxF "flutter: [ Easy Localization] [DEBUG] Start" "$f" && grep -q "stopped; 2 app lines" "$TMP/out" \
  && [ $((SECONDS - s0)) -lt 10 ] \
  && ok "logs.sh writes the phone's flutter: lines to a file, cleaned, for the time asked" || no "logs.sh on a phone" "$(cat "$TMP/out")"
pgrep -f "idevicesyslog -u PHONE-1" >/dev/null && no "logs.sh leaves nothing reading" "the reader is still running" \
  || ok "and leaves nothing reading the phone's log"
( cd "$P" && bash "$BIN/logs.sh" 1 ) >"$TMP/out" 2>&1; rc=$?
[ $rc = 1 ] && grep -q "for a phone only" "$TMP/out" && ok "logs.sh on a simulator says where its output is instead" || no "logs.sh on a simulator" "rc=$rc $(cat "$TMP/out")"
ph stop
s0=$SECONDS; FAKE_LLDB=1 LLDB_GRACE=1 START_CHUNK=1 ph start --build --no-branch; rc=$?
[ $rc = 1 ] && grep -q "LLDB is slow" "$TMP/out" && grep -q "LLDB STALL" "$TMP/out" && [ $((SECONDS - s0)) -lt 10 ] \
  && ok "an LLDB stall ends the wait after LLDB_GRACE, named by run-diagnose" || no "an LLDB stall" "rc=$rc $((SECONDS - s0))s $(cat "$TMP/out")"
ph stop
FAKE_ARCH=1 ph start --build --no-branch; rc=$?
[ $rc = 1 ] && grep -q "^failed" "$TMP/out" && grep -q "ROSETTA: Flutter's bundled iproxy" "$TMP/out" \
  && ok "iproxy's wrong architecture fails at once, named by run-diagnose" || no "iproxy's wrong architecture" "rc=$rc $(cat "$TMP/out")"
ph stop

echo "installer — maestro-drive"
"$REPO/install.sh" --yes >"$TMP/out" 2>&1 && ok "installs with maestro-drive present" || no "installs with maestro-drive present" "$(tail -5 "$TMP/out")"
mv "$MD" "$TMP/md-away"
"$REPO/install.sh" --yes >"$TMP/out" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "needs maestro-drive" "$TMP/out" \
  && ok "without maestro-drive the install fails, saying why" || no "without maestro-drive the install fails, saying why" "rc=$rc $(tail -6 "$TMP/out")"
mv "$TMP/md-away" "$MD"
FAKE_MD_VERSION=2 "$REPO/install.sh" --yes >"$TMP/out" 2>&1; rc=$?
[ $rc != 0 ] && grep -q "library version 2" "$TMP/out" \
  && ok "with the wrong library version the install fails, saying why" || no "with the wrong library version the install fails" "rc=$rc $(tail -6 "$TMP/out")"

echo "installer — the skill directory"
"$REPO/uninstall.sh" --yes >/dev/null 2>&1
mkdir -p "$CLAUDE_DIR/skills/flutter-hot-reload-mac"
touch "$CLAUDE_DIR/skills/flutter-hot-reload-mac/stale-hand-copy"
"$REPO/install.sh" --yes >/dev/null 2>&1
[ ! -e "$CLAUDE_DIR/skills/flutter-hot-reload-mac/stale-hand-copy" ] \
  && [ -f "$CLAUDE_DIR/skills/flutter-hot-reload-mac/SKILL.md" ] \
  && ok "installing over a hand copy replaces it" || no "installing over a hand copy replaces it" "$(ls "$CLAUDE_DIR/skills/flutter-hot-reload-mac")"
nx=; for f in start watch reload status stop logs; do [ -x "$CLAUDE_DIR/skills/flutter-hot-reload-mac/bin/$f.sh" ] || nx="$nx $f"; done
[ -z "$nx" ] && ok "the installed scripts are executable" || no "the installed scripts are executable" "not:$nx"
nx=; for f in start watch reload status stop logs; do git -C "$REPO" ls-files -s "skill/bin/$f.sh" | grep -q '^100755' || nx="$nx $f"; done
[ -z "$nx" ] && ok "and carry the bit in git, so the release tarball has it" || no "and carry the bit in git" "not:$nx"
"$REPO/install.sh" --link --yes >/dev/null 2>&1
[ -L "$CLAUDE_DIR/skills/flutter-hot-reload-mac" ] && ok "--link symlinks the skill" || no "--link symlinks the skill" "not a symlink"
"$REPO/uninstall.sh" --yes >/dev/null 2>&1
[ ! -e "$CLAUDE_DIR/skills/flutter-hot-reload-mac" ] && ok "uninstall removes it" || no "uninstall removes it" "still installed"

echo "the real maestro-drive"
MD_SRC=${MD_SRC:-$(cd "$REPO/../../.." 2>/dev/null && pwd)/maestro-drive}
MD_REF=${MD_REF:-main}
if git -C "$MD_SRC" rev-parse -q --verify "$MD_REF" >/dev/null 2>&1; then
  echo "  (checking $MD_SRC at $MD_REF, $(git -C "$MD_SRC" rev-parse --short "$MD_REF"))"
  mdlib=$(git -C "$MD_SRC" show "$MD_REF:skill/bin/lib.sh")
  mdall=$mdlib$'\n'$(git -C "$MD_SRC" show "$MD_REF:skill/bin/config.sh")
  is "its lib.sh sets the library version this needs" "1" \
    "$(sed -n 's/^MAESTRO_DRIVE_LIB_VERSION=\([0-9]*\)$/\1/p' <<<"$mdlib")"
  uses_f=$(sed -n 's/^MD_USES_FUNCS="\(.*\)"$/\1/p' "$BIN/lib.sh")
  uses_v=$(sed -n 's/^MD_USES_VARS="\(.*\)"$/\1/p' "$BIN/lib.sh")
  gone=; for f in $uses_f; do grep -qE "^$f\(\)" <<<"$mdall" || gone="$gone $f"; done
  [ -z "$gone" ] && ok "it defines every function this uses" || no "it defines every function this uses" "missing:$gone"
  gone=; for v in $uses_v; do grep -qE "(^|[^A-Za-z_])$v(=|:=)" <<<"$mdall" || gone="$gone $v"; done
  [ -z "$gone" ] && ok "it sets every variable this uses" || no "it sets every variable this uses" "missing:$gone"
  git -C "$MD_SRC" show "$MD_REF:skill/runners/flutter/framework.sh" | grep -q -- '--env' \
    && ok "its framework.sh describe takes --env" || no "its framework.sh describe takes --env" "no --env"
  git -C "$MD_SRC" show "$MD_REF:skill/runners/flutter/vmservice.sh" | grep -q 'frun-\$DEV.log' \
    && ok "its vmservice.sh reads the per-device frun log" || no "its vmservice.sh reads the per-device frun log" "not found"
  fw=$(git -C "$MD_SRC" show "$MD_REF:skill/runners/flutter/framework.sh")
  gone=; for v in device-check run-diagnose logs build; do grep -q "^$v)" <<<"$fw" || gone="$gone $v"; done
  [ -z "$gone" ] && ok "its framework.sh has the phone commands (device-check, run-diagnose, logs, build)" || no "its framework.sh has the phone commands" "missing:$gone"
  git -C "$MD_SRC" show "$MD_REF:skill/runners/flutter/build.sh" | grep -q -- '--debug)' && grep -q 'artifact ' <<<"$(git -C "$MD_SRC" show "$MD_REF:skill/runners/flutter/build.sh")" \
    && ok "its build.sh takes --debug for a phone and prints the artifact" || no "its build.sh takes --debug" "not found"
else
  echo "  (skipped: no maestro-drive checkout at $MD_SRC; set MD_SRC)"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
