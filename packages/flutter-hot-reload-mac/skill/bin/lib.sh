#!/bin/bash
# Shared setup. Source this, do not run it.
#
# Everything about reaching the device — the conf file, the transport, picking
# a Mac alias, ssh with its retry and timeout, which simulator — is
# maestro-drive's. This sources maestro-drive's bin/lib.sh, the way rrcd
# sources rrc's rrc-lib.sh, and refuses any library version but the one it was
# written against. What is left here is this skill's own: its settings and its
# per-device paths.
#
# maestro-drive is found at $FHRM_MAESTRO_DRIVE if set, else
# $CLAUDE_DIR/skills/maestro-drive. Never PATH.
#
# Anything already exported wins over the conf, for this skill's own settings:
#   WATCH_DIR=lib/src bash bin/start.sh

NEEDS_MD_LIB=1

# What this skill uses from maestro-drive. The library version covers the
# functions; the variables are listed so test/run-tests.sh can check a
# maestro-drive checkout still sets every one of them.
MD_USES_FUNCS="_pick_host _ssh _push _pull _dev _label_guard _fs_shared _where"
MD_USES_VARS="MAESTRO_DRIVE_CONF_FOUND PROJECT_DIR TRANSPORT MAC_HOST REPO APP_ID DEV RDIR RMODS LDIR SSH_OPTS PLATFORM_SH FRAMEWORK_SH"

: "${CLAUDE_DIR:=$HOME/.claude}"
MD_DIR=${FHRM_MAESTRO_DRIVE:-$CLAUDE_DIR/skills/maestro-drive}
MD_LIB=$MD_DIR/bin/lib.sh
if [ ! -f "$MD_LIB" ]; then
  echo "flutter-hot-reload-mac: needs maestro-drive, and $MD_LIB is missing: install maestro-drive" >&2
  exit 1
fi

# maestro-drive's conf loader sources the file directly. A conf written by its
# init.sh uses ': "${X:=v}"' lines, which an exported value already beats; a
# hand-written one may use plain X=v lines, which would not. So note what the
# environment set for this skill's settings, and put it back afterwards. An
# exported empty value counts. Plain strings, so macOS's bash 3.2 can run it.
_keep=""
for _v in WATCH_DIR WATCH_ASSETS WATCH_REBUILD BUILD_FLAVOR BUILD_TARGET FLAVOR TARGET FLUTTER_BIN DEV; do
  [ -n "${!_v+x}" ] && _keep+="$_v=$(printf '%q' "${!_v}");"
done
# shellcheck disable=SC1090
. "$MD_LIB"
eval "$_keep"
unset _v _keep

if [ "${MAESTRO_DRIVE_LIB_VERSION:-}" != "$NEEDS_MD_LIB" ]; then
  echo "flutter-hot-reload-mac: $MD_LIB is library version ${MAESTRO_DRIVE_LIB_VERSION:-none}, and this needs $NEEDS_MD_LIB: update maestro-drive and flutter-hot-reload-mac together" >&2
  exit 1
fi

# --- this skill's settings ---------------------------------------------------
# Synced and watched, relative to both checkouts.
: "${WATCH_DIR:=lib}"
# Also synced and watched, hot restarted rather than reloaded; space-separated.
# Empty for none.
: "${WATCH_ASSETS=assets}"
# Watched, never synced: a change here needs a rebuild (watch.sh's REBUILD).
: "${WATCH_REBUILD=pubspec.yaml ios android}"

# 1.0's names for the flavour and entry file. maestro-drive's are BUILD_FLAVOR
# and BUILD_TARGET, and two names for one setting in one conf is how the two
# skills came to build different apps from it. Read the old ones for one
# version, saying so.
if [ -n "${FLAVOR+x}" ] && [ -z "${BUILD_FLAVOR:-}" ]; then
  echo "flutter-hot-reload-mac: FLAVOR is 1.0's name; using it as BUILD_FLAVOR. Rename it in the conf." >&2
  BUILD_FLAVOR=$FLAVOR
  # 1.0 read FLAVOR= as "unflavoured". maestro-drive has no spelling for that:
  # an unflavoured project is one it finds no flavours in.
  [ -z "$FLAVOR" ] && FHRM_NO_FLAVOR=1
fi
if [ -n "${TARGET:-}" ] && [ -z "${BUILD_TARGET:-}" ]; then
  echo "flutter-hot-reload-mac: TARGET is 1.0's name; using it as BUILD_TARGET. Rename it in the conf." >&2
  BUILD_TARGET=$TARGET
fi
if [ -n "${FLUTTER_BIN:-}" ]; then
  echo "flutter-hot-reload-mac: FLUTTER_BIN is ignored since 2.0; maestro-drive finds the SDK from the checkout." >&2
fi
: "${BUILD_FLAVOR:=}" "${BUILD_TARGET:=}" "${FHRM_NO_FLAVOR:=}"

# Local state: screenshots, the watch marker.
FLDIR="$LDIR/flutter-hot-reload-mac"
mkdir -p "$FLDIR/shots"

# frun.py on the device's machine. Across ssh it is pushed beside the scratch;
# where the filesystem is shared it runs from this skill's own directory, and
# nothing is copied anywhere — $RHELP is then maestro-drive's checkout, not a
# place to write.
FHRM_SKILL=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
if _fs_shared; then RPY="$FHRM_SKILL/remote/frun.py"; else RPY="$RDIR/frun.py"; fi

# Per-device remote paths. One run per device, so two simulators can each have
# one, and a stop kills only its own. maestro-drive's runners/flutter/vmservice.sh
# reads the log at exactly this path.
_paths() {  # _paths <udid>
  RFIFO="$RDIR/frun-$1.in"
  RLOG="$RDIR/frun-$1.log"
  RERR="$RDIR/frun-$1.err"
  RPID="$RDIR/frun-$1.pid"      # "<frun pid> <flutter pid> <repo>"
  RSHOT="$RDIR/frun-$1.png"
}

# Copy a directory (WATCH_DIR by default) from this checkout to the one the
# build reads. Across ssh, rsync with maestro-drive's ssh options to the alias
# it picked. Where the filesystem is shared, a local rsync — or nothing, when
# REPO is this checkout.
_sync() {  # _sync [dir]
  local d=${1:-$WATCH_DIR}
  local src="$PROJECT_DIR/$d/"
  if _fs_shared; then
    [ "$PROJECT_DIR" -ef "$REPO" ] && return 0
    mkdir -p "$REPO/$d" && rsync -a --delete "$src" "$REPO/$d/"
  else
    _pick_host || return 1
    rsync -az --delete -e "ssh ${SSH_OPTS[*]}" "$src" "$MAC_HOST:$REPO/$d/"
  fi
}

# watch.sh's marker for a device: saves newer than it have not been synced.
_mark() { echo "$FLDIR/watch-mark-$1"; }

# Is the run on this device alive? Prints its pid line when it is.
_alive() {  # _alive <udid>
  _paths "$1"
  _ssh "[ -r '$RPID' ] && read p f r < '$RPID' && kill -0 \"\$p\" 2>/dev/null && echo \"\$p \$f \$r\""
}

# What flutter prints once it has answered a key. The wait is for one of these
# and never for an error line: the app's own output can say "Exception" at any
# time, and a compile error on reload ends in "Try again after fixing", not in a
# "Reloaded" line.
RESULT_PAT='Reloaded .* in |Restarted application|(reload|restart).*(failed|rejected)|Try again after fixing|Application finished'
# A remote pipe stage that takes flutter's terminal codes out of log text. A
# carriage return at a line's end goes; one inside a line becomes a line break,
# because flutter's spinner redraws "Performing hot reload..." and then writes
# the next line of output after a carriage return on the same line, and that is
# where every compile error and exception header lands. Colour and cursor codes
# go only with their escape in front, so "[frun]" survives; then any stray
# escape or backspace. One awk, which macOS's awk and gawk both run alike.
CLEAN="awk '{ sub(/\\r\$/, \"\"); gsub(/\\033\\[[0-9;?]*[A-Za-z]/, \"\"); gsub(/\\r/, \"\\n\"); gsub(/[\\033\\010]/, \"\"); print }'"
# Where an error starts in what a key added to the log (BACKLOG item 13).
ERROR_PAT='EXCEPTION CAUGHT BY|Another exception was thrown|Unhandled Exception|: Error: |^Error'

# _key_script <key> [after] — the remote shell for one key: send it to this
# device's fifo, wait (up to RELOAD_TMO, 60 s) for flutter's answer, wait
# RELOAD_SETTLE (1 s) more for what the first frame after it throws, run
# <after> (watch.sh's screenshot), then print the answer and any error the key
# added to the log, up to RELOAD_ERR_LINES (40) lines of it. Exits 1 when
# flutter never answered. Call _paths first.
_key_script() {
  local key=$1 after=${2:-:} tmo=${RELOAD_TMO:-60}
  cat <<EOF
c0=\$(wc -c < '$RLOG' 2>/dev/null | tr -d ' '); c0=\${c0:-0}
n0=\$(grep -cE '$RESULT_PAT' '$RLOG' 2>/dev/null); n0=\${n0:-0}
printf '%s' '$key' > '$RFIFO'
i=0; n=\$n0
while [ \$n -le \$n0 ] && [ \$i -lt $tmo ]; do
  sleep 1; i=\$((i+1)); n=\$(grep -cE '$RESULT_PAT' '$RLOG' 2>/dev/null); n=\${n:-0}
done
[ \$n -gt \$n0 ] && sleep ${RELOAD_SETTLE:-1}
$after
new=\$(tail -c +\$((c0+1)) '$RLOG' | $CLEAN)
rc=0
if [ \$n -gt \$n0 ]; then printf '%s\n' "\$new" | grep -E '$RESULT_PAT' | tail -n \$((n-n0))
else echo 'no answer from flutter after ${tmo}s. Last of its log:'; tail -5 '$RLOG' | $CLEAN; rc=1; fi
printf '%s\n' "\$new" | awk -v max=${RELOAD_ERR_LINES:-40} -v lf='$RLOG' '
  /$ERROR_PAT/ { if (!on) print "error from this key:"; on=1 }
  on && /^(Performing hot|Reloaded .* in |Restarted application|Try again after fixing)/ { next }
  on { c++; if (c <= max) print }
  END { if (c > max) print "... " c-max " more lines in " lf }'
exit \$rc
EOF
}
