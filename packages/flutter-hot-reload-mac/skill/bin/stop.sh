#!/bin/bash
# Stop the run on the Mac and clear its files. The app stays installed on the
# simulator; the simulator stays booted.
#
# This cannot stop the local watcher — that is a harness background task, and
# only TaskStop ends it. bin/status.sh will still show the run as gone, and the
# watcher's next save attempt fails harmlessly.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh" || exit 1

_ssh "pkill -f frun.py; pkill -f 'flutter_tools.snapshot run'; sleep 1
rm -f $RFIFO $RPY $RSHOT $RERR
pgrep -f 'frun.py|flutter_tools.snapshot run' >/dev/null && echo 'still running' || echo 'stopped'"
