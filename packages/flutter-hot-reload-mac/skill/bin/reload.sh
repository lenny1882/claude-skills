#!/bin/bash
# Send a key to this device's running `flutter run` and show what it did.
#
#   bin/reload.sh          # r — hot reload
#   bin/reload.sh restart  # R — hot restart (state is lost, use after a
#                          #     change to initState, a global, or a provider)
#   bin/reload.sh q        # quit the app, leaving the run alive
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh" || exit 1

case "${1:-reload}" in
  reload|r)   key=r ;;
  restart|R)  key=R ;;
  q|quit)     key=q ;;
  *)          key=$1 ;;
esac

_pick_host || exit 1
dev=$(_dev) || exit 1
_paths "$dev"
_ssh "test -p '$RFIFO'" || { echo "no run is listening on $dev — bin/start.sh first" >&2; exit 1; }
# Waits for flutter's answer to THIS key, not a fixed time, and shows any
# error the key added to the log — see _key_script in lib.sh. A fixed `sleep 4`
# once read the log before a 4.5s hot restart on an Android emulator had
# finished (BACKLOG item 20).
_ssh "$(_key_script "$key")"
