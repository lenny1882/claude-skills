#!/usr/bin/env bash
# Tests for flutter-hot-reload-mac.
#
# Redirects HOME and CLAUDE_DIR into a temp directory, so the real config is
# never touched. Add cases for the behaviour itself below the installer ones —
# the installer tests come free, the behaviour tests are the point.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export CLAUDE_DIR="$TMP/claude"; mkdir -p "$CLAUDE_DIR"

pass=0; fail=0
ok(){ printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s\n    %s\n' "$1" "$2"; fail=$((fail+1)); }

. "$REPO/test/installer-tests.sh"

# Everything here talks to the Mac over SSH, so ssh is replaced by a stub on
# PATH that logs its arguments and answers from environment variables:
#   SSH_OK_HOSTS  hosts that answer the 'exit 0' reachability probe
#   SSH_FIFO_RC   exit code for 'test -p <fifo>'
# Anything else succeeds silently, except 'simctl list', which prints one
# booted simulator. start/watch/shot/status/stop are parse-checked only: their
# behaviour is SSH sequencing against a real Mac, and stubbing it that deeply
# would test the stubs.
BIN="$REPO/skill/bin"
STUB="$TMP/stub"; mkdir -p "$STUB"
export STUB_LOG="$TMP/ssh.log"; : > "$STUB_LOG"
cat > "$STUB/ssh" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >> "$STUB_LOG"
host="${@: -2:1}"; cmd="${@: -1}"
case "$cmd" in
  'exit 0') case " ${SSH_OK_HOSTS:-} " in *" $host "*) exit 0 ;; *) exit 255 ;; esac ;;
  *'simctl list'*) echo "    iPhone 16 Pro (C61983AE-1974-4ACD-8087-8FD849CF89B1) (Booted)" ;;
  'test -p'*) exit "${SSH_FIFO_RC:-1}" ;;
esac
exit 0
SH
chmod +x "$STUB/ssh"
export PATH="$STUB:$PATH"
export TMPDIR="$TMP"      # lib.sh keeps its local state under TMPDIR
unset MAESTRO_DRIVE_CONF DEV MAC_HOST FLAVOR TARGET FLUTTER_BIN WATCH_DIR LDIR

# q <dir> <snippet> — source lib.sh from <dir>, then run <snippet>. The
# environment passes through, so VAR=x q ... sets it for that call only.
q(){ ( cd "$1" && bash -c '. "$1" >/dev/null && eval "$2"' _ "$BIN/lib.sh" "$2" ) 2>"$TMP/qerr"; }
is(){ # is <description> <expected> <actual>
  [ "$2" = "$3" ] && ok "$1" || no "$1" "expected '$2', got '$3'"; }

echo "parsing"
for f in "$BIN"/*.sh; do
  bash -n "$f" && ok "bin/$(basename "$f") parses" || no "bin/$(basename "$f") parses" "syntax error"
done
python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' "$REPO/skill/remote/frun.py" \
  && ok "remote/frun.py parses" || no "remote/frun.py parses" "syntax error"

echo "settings"
W="$TMP/work"; mkdir -p "$W/app/lib/deep"
printf 'MAC_HOST=from-explicit\n' > "$TMP/explicit.conf"
is "\$MAESTRO_DRIVE_CONF is used when set" "from-explicit" \
  "$(MAESTRO_DRIVE_CONF="$TMP/explicit.conf" q "$W" 'echo "$MAC_HOST"')"
MAESTRO_DRIVE_CONF="$TMP/nope.conf" q "$W" 'true' >/dev/null
grep -q "nope.conf is not readable" "$TMP/qerr" \
  && ok "an unreadable \$MAESTRO_DRIVE_CONF is named" || no "an unreadable \$MAESTRO_DRIVE_CONF is named" "$(cat "$TMP/qerr")"
printf 'MAC_HOST=from-project\n' > "$W/app/.maestro-drive.conf"
is "the project conf is found from a subdirectory" "from-project $W/app" \
  "$(q "$W/app/lib/deep" 'echo "$MAC_HOST $PROJECT_DIR"')"
printf 'MAC_HOST=from-home\n' > "$HOME/.maestro-drive.conf"
is "~/.maestro-drive.conf is the fallback" "from-home" "$(q "$W" 'echo "$MAC_HOST"')"
rm -f "$HOME/.maestro-drive.conf"
is "with no conf, the project is \$PWD" "$W" "$(q "$W" 'echo "$PROJECT_DIR"')"
is "Flutter defaults" ".fvm/flutter/bin/flutter|dev|lib/main_dev.dart|lib" \
  "$(q "$W" 'echo "$FLUTTER_BIN|$FLAVOR|$TARGET|$WATCH_DIR"')"
is "an exported FLAVOR beats the default" "prod" "$(FLAVOR=prod q "$W" 'echo "$FLAVOR"')"
# lib.sh says "Anything already exported wins over the file". This checks
# that claim as written.
printf 'MAC_HOST=from-project\nFLAVOR=staging\n' > "$W/app/.maestro-drive.conf"
is "an exported FLAVOR beats the conf file" "prod" "$(FLAVOR=prod q "$W/app" 'echo "$FLAVOR"')"
is "so does an exported empty one — an unflavoured build" "[]" "$(FLAVOR= q "$W/app" 'echo "[$FLAVOR]"')"
is "the conf file still applies when nothing is exported" "staging from-project" \
  "$(q "$W/app" 'echo "$FLAVOR $MAC_HOST"')"
printf 'MAC_HOST=from-project\nFLAVOR=\n' > "$W/app/.maestro-drive.conf"
is "FLAVOR= in the conf file means unflavoured, not dev" "[]" "$(q "$W/app" 'echo "[$FLAVOR]"')"

echo "host and simulator"
out=$(q "$W" 'MAC_HOST=; _pick_host; echo "rc=$?"')
[ "$out" = "rc=1" ] && grep -q "MAC_HOST is not set" "$TMP/qerr" \
  && ok "an empty MAC_HOST fails, saying so" || no "an empty MAC_HOST fails, saying so" "$out / $(cat "$TMP/qerr")"
: > "$STUB_LOG"
out=$(q "$W" 'MAC_HOST=solo; _pick_host; rc=$?; echo "$MAC_HOST $rc"')
[ "$out" = "solo 0" ] && [ ! -s "$STUB_LOG" ] \
  && ok "a single host is used without probing" || no "a single host is used without probing" "$out / $(cat "$STUB_LOG")"
mkdir -p "$TMP/ldir-cached"; printf 'mac-b' > "$TMP/ldir-cached/mac-host"
: > "$STUB_LOG"
out=$(LDIR="$TMP/ldir-cached" q "$W" 'MAC_HOST="mac-a mac-b"; _pick_host; echo "$MAC_HOST"')
[ "$out" = "mac-b" ] && [ ! -s "$STUB_LOG" ] \
  && ok "a cached host is used without probing" || no "a cached host is used without probing" "$out / $(cat "$STUB_LOG")"
: > "$STUB_LOG"
out=$(LDIR="$TMP/ldir-fresh" SSH_OK_HOSTS=mac-b q "$W" 'MAC_HOST="mac-a mac-b"; _pick_host; echo "$MAC_HOST"')
[ "$out" = "mac-b" ] && grep -q "mac-a exit 0" "$STUB_LOG" \
  && ok "without a cache, the first host that answers wins" || no "without a cache, the first host that answers wins" "$out / $(cat "$STUB_LOG")"
is "and it is cached" "mac-b" "$(cat "$TMP/ldir-fresh/mac-host" 2>/dev/null)"
is "_dev returns DEV when it is set" "ABC" "$(q "$W" 'DEV=ABC; _dev')"
is "_dev reads the booted simulator otherwise" "C61983AE-1974-4ACD-8087-8FD849CF89B1" \
  "$(q "$W" 'MAC_HOST=solo; DEV=; _dev')"

echo "frun.py"
# frun.py hardcodes /tmp/frun.in and /tmp/frun.log. Run a copy with those two
# paths moved into the temp directory — the sandbox cannot write /tmp, and a
# real run on this machine would be clobbered — and a fake flutter that prints
# the arguments it was given.
sed "s#/tmp/frun#$TMP/frun#g" "$REPO/skill/remote/frun.py" > "$TMP/frun-copy.py"
printf '#!/bin/bash\necho "ARGS: $*"\n' > "$TMP/fake-flutter"; chmod +x "$TMP/fake-flutter"
frun(){ # frun <flavor>
  rm -f "$TMP/frun.log"
  FRUN_REPO="$TMP" FRUN_DEV=UDID1 FRUN_FLUTTER="$TMP/fake-flutter" FRUN_FLAVOR="$1" \
    FRUN_TARGET=lib/main_dev.dart timeout 20 python3 "$TMP/frun-copy.py" >/dev/null 2>&1; }
frun dev
grep -q -- "^\[frun\] .*fake-flutter run --flavor dev -d UDID1 -t lib/main_dev.dart" "$TMP/frun.log" \
  && ok "--flavor goes before -d, not between -d and the UDID" || no "--flavor goes before -d, not between -d and the UDID" "$(head -2 "$TMP/frun.log")"
grep -q -- "ARGS: run --flavor dev -d UDID1 -t lib/main_dev.dart" "$TMP/frun.log" \
  && ok "flutter receives them in that order, through the pty" || no "flutter receives them in that order, through the pty" "$(head -3 "$TMP/frun.log")"
grep -q "flutter run exited" "$TMP/frun.log" \
  && ok "the log records the exit" || no "the log records the exit" "$(tail -2 "$TMP/frun.log")"
frun ""
grep -q -- "ARGS: run -d UDID1 -t lib/main_dev.dart" "$TMP/frun.log" && ! grep -q -- "--flavor" "$TMP/frun.log" \
  && ok "an empty FLAVOR passes no --flavor" || no "an empty FLAVOR passes no --flavor" "$(head -3 "$TMP/frun.log")"

echo "reload.sh"
( cd "$W" && MAC_HOST=solo SSH_FIFO_RC=1 bash "$BIN/reload.sh" ) >/dev/null 2>"$TMP/err"
[ $? -ne 0 ] && grep -q "bin/start.sh first" "$TMP/err" \
  && ok "with no run listening, it says to start one" || no "with no run listening, it says to start one" "$(cat "$TMP/err")"
: > "$STUB_LOG"
( cd "$W" && MAC_HOST=solo SSH_FIFO_RC=0 bash "$BIN/reload.sh" restart ) >/dev/null 2>&1
grep -qF "printf '%s' 'R'" "$STUB_LOG" && ok "restart sends R" || no "restart sends R" "$(cat "$STUB_LOG")"
: > "$STUB_LOG"
( cd "$W" && MAC_HOST=solo SSH_FIFO_RC=0 bash "$BIN/reload.sh" ) >/dev/null 2>&1
grep -qF "printf '%s' 'r'" "$STUB_LOG" && ok "the default sends r" || no "the default sends r" "$(cat "$STUB_LOG")"

echo "installer — the skill directory"
# The copy installed before this package existed is a plain directory.
mkdir -p "$CLAUDE_DIR/skills/flutter-hot-reload-mac"
touch "$CLAUDE_DIR/skills/flutter-hot-reload-mac/stale-hand-copy"
"$REPO/install.sh" --yes >/dev/null 2>&1
[ ! -e "$CLAUDE_DIR/skills/flutter-hot-reload-mac/stale-hand-copy" ] \
  && [ -f "$CLAUDE_DIR/skills/flutter-hot-reload-mac/SKILL.md" ] \
  && ok "installing over a hand copy replaces it" || no "installing over a hand copy replaces it" "$(ls "$CLAUDE_DIR/skills/flutter-hot-reload-mac")"
"$REPO/install.sh" --link --yes >/dev/null 2>&1
[ -L "$CLAUDE_DIR/skills/flutter-hot-reload-mac" ] \
  && ok "--link symlinks the skill" || no "--link symlinks the skill" "not a symlink"
[ -f "$CLAUDE_DIR/skills/flutter-hot-reload-mac/SKILL.md" ] \
  && ok "SKILL.md resolves through the link" || no "SKILL.md resolves through the link" "missing"
"$REPO/install.sh" --link --yes >/dev/null 2>&1 \
  && ok "reinstalling is safe" || no "reinstalling is safe" "second install failed"
"$REPO/uninstall.sh" --yes >/dev/null 2>&1
[ ! -e "$CLAUDE_DIR/skills/flutter-hot-reload-mac" ] \
  && ok "uninstall removes it" || no "uninstall removes it" "still installed"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
