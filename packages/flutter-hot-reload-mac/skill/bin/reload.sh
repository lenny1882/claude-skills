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
# Wait for flutter's answer to THIS key, not a fixed time: count the result
# lines before sending it and wait for the count to grow. A fixed `sleep 4`
# read the log before a 4.5s hot restart on an Android emulator had finished,
# and showed the previous reload's line as if it were the restart's (BACKLOG
# item 20). RELOAD_TMO (default 60) bounds the wait.
PAT='Reloaded .* in |Restarted application|(reload|restart).*(failed|rejected)|^Error|Application finished'
_ssh "n0=\$(grep -cE '$PAT' '$RLOG' 2>/dev/null); n0=\${n0:-0}
printf '%s' '$key' > '$RFIFO'
i=0; n=\$n0
while [ \$n -le \$n0 ] && [ \$i -lt ${RELOAD_TMO:-60} ]; do
  sleep 1; i=\$((i+1)); n=\$(grep -cE '$PAT' '$RLOG' 2>/dev/null); n=\${n:-0}
done
if [ \$n -gt \$n0 ]; then grep -E '$PAT' '$RLOG' | tail -n \$((n-n0)); exit 0; fi
echo 'no answer from flutter after ${RELOAD_TMO:-60}s. Last of its log:' >&2
tail -5 '$RLOG' >&2; exit 1"
