#!/bin/bash
# Watch the local WATCH_DIR, sync each save to the Mac, hot reload, screenshot.
#
#   bin/watch.sh          # handle ONE save, print SHOT: <path>, exit 0
#   bin/watch.sh --loop   # keep going; screenshots still land in $LDIR/shots
#
# The one-shot default exists because of how the harness works, not because
# it is a nicer design: a background Bash task only notifies Claude when it
# EXITS. Exiting after each save is what lets Claude post the screenshot in the
# conversation. Claude relaunches it straight away; saves inside that gap are
# missed, so save again if nothing comes back.
#
# Detection is a local `find -newer` against a marker file, not rsync's own
# comparison: rsync would need an SSH round trip every poll.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh" || exit 1

LOOP=0
[ "${1:-}" = "--loop" ] && LOOP=1

_pick_host || exit 1
dev=$(_dev) || exit 1
MARK="$LDIR/watch-mark"
SSH="ssh ${SSH_OPTS[*]}"

touch "$MARK"
echo "$(date +%H:%M:%S) watching $PROJECT_DIR/$WATCH_DIR -> $MAC_HOST"

while true; do
  changed=$(cd "$PROJECT_DIR" && find "$WATCH_DIR" -name '*.dart' -newer "$MARK" 2>/dev/null | head -20)
  if [ -n "$changed" ]; then
    touch "$MARK"
    sleep 0.4                       # let the editor finish writing
    rsync -az --delete -e "$SSH" \
      "$PROJECT_DIR/$WATCH_DIR/" "$MAC_HOST:$REPO/$WATCH_DIR/" >/dev/null 2>&1
    echo "$(date +%H:%M:%S) saved: $(echo "$changed" | tr '\n' ' ')"
    $SSH "$MAC_HOST" "printf 'r' > $RFIFO"
    sleep 3                         # reload lands in ~350ms; the frame follows
    $SSH "$MAC_HOST" "xcrun simctl io $dev screenshot -t png $RSHOT" 2>&1 |
      grep -v 'No display specified'
    shot="$LDIR/shots/$(date +%H%M%S).png"
    scp "${SSH_OPTS[@]}" -q "$MAC_HOST:$RSHOT" "$shot"
    $SSH "$MAC_HOST" "grep -E 'Reloaded .* in |reload.*(failed|rejected)|^Error|Exception' $RLOG | tail -2"
    echo "SHOT: $shot"
    [ "$LOOP" = 1 ] || exit 0
  fi
  sleep 2
done
