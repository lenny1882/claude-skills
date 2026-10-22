#!/bin/bash
# One screenshot of the simulator, pulled here. Prints the local path.
#   bin/shot.sh [/path/to/out.png]
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh" || exit 1

_pick_host || exit 1
dev=$(_dev) || exit 1
out=${1:-$LDIR/shots/$(date +%H%M%S).png}

_ssh "xcrun simctl io $dev screenshot -t png $RSHOT" 2>&1 | grep -v 'No display specified'
scp "${SSH_OPTS[@]}" -q "$MAC_HOST:$RSHOT" "$out" || exit 1
echo "$out"
