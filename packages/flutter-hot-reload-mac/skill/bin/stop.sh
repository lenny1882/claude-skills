#!/bin/bash
# Stop this device's run and clear its files. Other devices' runs, and other
# sessions', are left alone. The app stays installed; the simulator stays booted.
#
#   bin/stop.sh            # the run on DEV, or the first booted device
#   DEV=<udid> bin/stop.sh # a named one
#
# This cannot stop the local watcher — that is a harness background task, and
# only TaskStop ends it. Its next save finds the run gone and exits 2.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh" || exit 1

_pick_host || exit 1
dev=$(_dev) || exit 1
_paths "$dev"

# frun.py's SIGTERM handler stops flutter (its own process group) before it
# exits. If frun.py is wedged, the group is killed directly after ten seconds.
_ssh "if [ -r '$RPID' ] && read p fl r < '$RPID'; then
  kill \"\$p\" 2>/dev/null
  i=0; while kill -0 \"\$p\" 2>/dev/null && [ \$i -lt 10 ]; do sleep 1; i=\$((i+1)); done
  kill -9 \"\$p\" 2>/dev/null; kill -9 -\"\$fl\" 2>/dev/null
fi
rm -f '$RFIFO' '$RPID' '$RSHOT' '$RERR'
if [ -n \"\${p:-}\" ] && { kill -0 \"\$p\" 2>/dev/null || kill -0 \"\$fl\" 2>/dev/null; }; then echo 'still running'
elif [ -n \"\${p:-}\" ]; then echo 'stopped'
else echo 'nothing was running on $dev'; fi"
