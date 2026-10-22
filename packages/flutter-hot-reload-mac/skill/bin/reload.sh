#!/bin/bash
# Send a key to the running `flutter run` and show what it did.
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

_ssh "test -p $RFIFO" || { echo "no run is listening on $RFIFO — bin/start.sh first" >&2; exit 1; }
_ssh "printf '%s' '$key' > $RFIFO; sleep 4
grep -E 'Reloaded .* in |Restarted application|reload.*(failed|rejected)|^Error' $RLOG | tail -3"
