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
mkdir -p "$MD/bin" "$MD/runners/flutter" "$MD/runners/ios"
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
PLATFORM_SH="$RMODS/ios/platform.sh"; FRAMEWORK_SH="$RMODS/flutter/framework.sh"
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
[ "$1" != installed-info ] || [ "${FAKE_INSTALLED:-0}" = 1 ]
SH
cat > "$MD/runners/flutter/framework.sh" <<'SH'
#!/bin/sh
[ "$1" = describe ] || exit 2
[ -n "${FAKE_UNDECIDED:-}" ] && { echo "flavour NOT DECIDED: dev, uat" >&2; exit 1; }
printf 'FLUTTER=%s\nFLAVOR=%s\nTARGET=%s\nGEM_HOME=%s\n' "$FAKE_FLUTTER" "${FAKE_FLAVOR-dev}" "${FAKE_TARGET-lib/main_dev.dart}" "${FAKE_GEM:-}"
SH
cat > "$MD/runners/flutter/build.sh" <<'SH'
#!/bin/sh
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
echo "Flutter run key commands."
while IFS= read -r -n1 c; do
  case $c in
    r) echo "Reloaded 1 of 1 libraries in 312ms" ;;
    R) echo "Restarted application in 900ms" ;;
    q) echo "Application finished."; exit 0 ;;
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
export START_POLL=0.3 START_TRIES=40 WATCH_POLL=0.2
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
git init -q "$P"; mkdir -p "$P/lib"
echo "void main() {}" > "$P/lib/main.dart"; echo readme > "$P/README"
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

echo "start.sh — a run"
echo "// edited" >> "$P/lib/main.dart"
st start --build; rc=$?
[ $rc = 0 ] && grep -q "^up" "$TMP/out" && ok "starts and waits for the app" || no "starts and waits for the app" "rc=$rc $(cat "$TMP/out")"
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
st reload restart; grep -q "Restarted application" "$TMP/out" && ok "restart sends R" || no "restart sends R" "$(cat "$TMP/out")"
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
echo "theirs" >> "$B/README"; echo "// synced before" >> "$B/lib/main.dart"
git -C "$P" switch -q feature
st start --build; rc=$?
[ $rc = 1 ] && grep -q "uncommitted changes" "$TMP/out" && grep -q "README" "$TMP/out" && ! grep -q "lib/main.dart" "$TMP/out" \
  && ok "uncommitted work outside WATCH_DIR stops the checkout, listing it" || no "uncommitted work outside WATCH_DIR stops the checkout" "rc=$rc $(cat "$TMP/out")"
is "and the build checkout stays where it was" "main" "$(git -C "$B" rev-parse --abbrev-ref HEAD)"
grep -q theirs "$B/README" && ok "with the work intact" || no "with the work intact" "README changed"
git -C "$B" checkout -q -- README
st start --build; rc=$?
[ $rc = 0 ] && [ "$(git -C "$B" rev-parse --abbrev-ref HEAD)" = feature ] \
  && ok "changes only inside WATCH_DIR do not stop it" || no "changes only inside WATCH_DIR do not stop it" "rc=$rc $(cat "$TMP/out")"
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
else
  echo "  (skipped: no maestro-drive checkout at $MD_SRC; set MD_SRC)"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
