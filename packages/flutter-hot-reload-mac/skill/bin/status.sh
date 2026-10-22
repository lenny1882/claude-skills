#!/bin/bash
# Is anything running, and what did it last do?
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh" || exit 1

_pick_host || exit 1
echo "mac:      $MAC_HOST"
echo "repo:     $REPO"
_ssh "cd '$REPO' && echo \"branch:   \$(git rev-parse --abbrev-ref HEAD) \$(git log -1 --format=%h)\"
if pgrep -f frun.py >/dev/null; then echo 'run:      alive'; else echo 'run:      not running'; fi
echo 'last:'
grep -E 'Reloaded .* in |Restarted application|Flutter run key commands|exited' $RLOG 2>/dev/null | tail -3 | sed 's/^/  /'"
echo "shots:    $LDIR/shots"
