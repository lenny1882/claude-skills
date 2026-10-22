#!/bin/bash
# Shared settings and SSH plumbing. Source this, do not run it.
#
# Settings come from the project's .maestro-drive.conf — the same file
# maestro-drive uses, because it already names the Mac, the simulator and
# the checkout on it. Nothing here writes to that skill's directory.
#
#   1. $MAESTRO_DRIVE_CONF, if set
#   2. .maestro-drive.conf, searched from $PWD upwards
#   3. ~/.maestro-drive.conf
#
# Anything already exported wins over the file:
#   FLAVOR=prod bin/start.sh

_find_conf() {
  if [ -n "${MAESTRO_DRIVE_CONF:-}" ]; then
    [ -r "$MAESTRO_DRIVE_CONF" ] || {
      echo "flutter-hot-reload-mac: \$MAESTRO_DRIVE_CONF=$MAESTRO_DRIVE_CONF is not readable" >&2; return 1; }
    echo "$MAESTRO_DRIVE_CONF"; return
  fi
  local d="$PWD"
  while [ "$d" != "/" ]; do
    [ -r "$d/.maestro-drive.conf" ] && { echo "$d/.maestro-drive.conf"; return; }
    d=$(dirname "$d")
  done
  [ -r "$HOME/.maestro-drive.conf" ] && echo "$HOME/.maestro-drive.conf"
}

CONF=$(_find_conf)
if [ -n "$CONF" ]; then
  # The conf file is plain assignments, so sourcing it would overwrite anything
  # exported for this call — FLAVOR=prod would lose to a FLAVOR=dev line.
  # Note what the environment set, source the file, then put those back. An
  # exported empty value counts: FLAVOR= is how an unflavoured build is asked
  # for. Plain strings rather than an associative array, so macOS's bash 3.2
  # can run it too.
  _keep=""
  for _v in MAC_HOST REPO DEV FLUTTER_BIN FLAVOR TARGET WATCH_DIR; do
    [ -n "${!_v+x}" ] && _keep+="$_v=$(printf '%q' "${!_v}");"
  done
  # shellcheck disable=SC1090
  . "$CONF"
  eval "$_keep"
  unset _v _keep
  PROJECT_DIR=$(cd "$(dirname "$CONF")" && pwd)
else
  PROJECT_DIR=$PWD
fi

# From .maestro-drive.conf.
: "${MAC_HOST:=}"                 # ssh alias(es), first that answers wins
: "${REPO:=}"                     # the checkout ON THE MAC
: "${DEV:=}"                      # simulator UDID; empty = first booted

# Flutter specifics. The defaults match a repo that pins its SDK with fvm and
# builds a flavoured entrypoint — a plain `flutter run` fails on both counts,
# with errors that name neither.
: "${FLUTTER_BIN:=.fvm/flutter/bin/flutter}"
: "${FLAVOR=dev}"                  # no colon: empty means unflavoured, only unset means dev
: "${TARGET:=lib/main_dev.dart}"
: "${WATCH_DIR:=lib}"             # synced and watched, relative to both repos

# Local state: screenshots, the watch marker, the host cache. TMPDIR inside the
# sandbox is the session scratchpad and is writable; /tmp is not.
: "${LDIR:=${TMPDIR:-/tmp}/flutter-hot-reload-mac}"
mkdir -p "$LDIR" "$LDIR/shots"

# Remote state. Fixed paths, so a call can find a run another call started.
RPY=/tmp/frun.py
RFIFO=/tmp/frun.in
RLOG=/tmp/frun.log
RERR=/tmp/frun.err
RSHOT=/tmp/frun-shot.png

# No ControlMaster: it fails in the sandbox with "muxclient socket(): Operation
# not permitted", and each Bash call is its own PID namespace, so the socket
# could not outlive the call anyway. A fresh connect costs ~0.4s.
SSH_OPTS=(
  -o StrictHostKeyChecking=accept-new
  -o BatchMode=yes
  -o ConnectTimeout=15
  -o ServerAliveInterval=30
)

HOST_CACHE="$LDIR/mac-host"

_pick_host() {  # narrows MAC_HOST to one alias that answers
  local n c cached
  [ -n "$MAC_HOST" ] || { echo "MAC_HOST is not set — see .maestro-drive.conf" >&2; return 1; }
  n=$(printf '%s\n' $MAC_HOST | grep -c .)
  [ "$n" -le 1 ] && return 0
  if [ -r "$HOST_CACHE" ]; then
    cached=$(cat "$HOST_CACHE")
    printf '%s\n' $MAC_HOST | grep -qx -- "$cached" && { MAC_HOST=$cached; return 0; }
  fi
  for c in $MAC_HOST; do
    if timeout 10 ssh -o ConnectTimeout=8 "${SSH_OPTS[@]}" "$c" 'exit 0' >/dev/null 2>&1; then
      MAC_HOST=$c; printf '%s' "$c" > "$HOST_CACHE"; return 0
    fi
  done
  echo "none of these answered: $MAC_HOST" >&2
  return 1
}

_ssh() { _pick_host || return 1; ssh "${SSH_OPTS[@]}" "$MAC_HOST" "$1"; }

_dev() {  # resolve the simulator once
  [ -n "$DEV" ] && { printf '%s' "$DEV"; return 0; }
  DEV=$(_ssh 'xcrun simctl list devices booted' |
        grep -oE '\(([0-9A-F-]{36})\)' | head -1 | tr -d '()')
  [ -n "$DEV" ] || { echo "no booted simulator on $MAC_HOST" >&2; return 1; }
  printf '%s' "$DEV"
}
