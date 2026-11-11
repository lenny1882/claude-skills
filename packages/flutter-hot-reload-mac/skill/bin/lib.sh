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
for _v in WATCH_DIR BUILD_FLAVOR BUILD_TARGET FLAVOR TARGET FLUTTER_BIN DEV; do
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

# Copy WATCH_DIR from this checkout to the one the build reads. Across ssh,
# rsync with maestro-drive's ssh options to the alias it picked. Where the
# filesystem is shared, a local rsync — or nothing, when REPO is this checkout.
_sync() {
  local src="$PROJECT_DIR/$WATCH_DIR/"
  if _fs_shared; then
    [ "$PROJECT_DIR" -ef "$REPO" ] && return 0
    rsync -a --delete "$src" "$REPO/$WATCH_DIR/"
  else
    _pick_host || return 1
    rsync -az --delete -e "ssh ${SSH_OPTS[*]}" "$src" "$MAC_HOST:$REPO/$WATCH_DIR/"
  fi
}

# Is the run on this device alive? Prints its pid line when it is.
_alive() {  # _alive <udid>
  _paths "$1"
  _ssh "[ -r '$RPID' ] && read p f r < '$RPID' && kill -0 \"\$p\" 2>/dev/null && echo \"\$p \$f \$r\""
}
