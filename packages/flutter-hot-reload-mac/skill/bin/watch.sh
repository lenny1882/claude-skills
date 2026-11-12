#!/bin/bash
# Watch the local WATCH_DIR, sync each save, hot reload, screenshot.
#
#   bin/watch.sh          # handle ONE save, print SHOT: <path>, exit 0
#   bin/watch.sh --loop   # keep going; screenshots still land in the shots dir
#
# The one-shot default exists because of how the harness works, not because
# it is a nicer design: a background Bash task only notifies Claude when it
# EXITS. Exiting after each save is what lets Claude post the screenshot in the
# conversation. Claude relaunches it straight away; saves inside that gap are
# missed, so save again if nothing comes back.
#
# Exits 2, saying so, when the run it would reload has gone — flutter run
# died or was stopped — rather than syncing into a dead app.
#
# Detection is a local `find -newer` against a marker file, not rsync's own
# comparison: rsync would need a round trip to the Mac every poll.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh" || exit 1

LOOP=0
[ "${1:-}" = "--loop" ] && LOOP=1
: "${WATCH_POLL:=2}"

_pick_host || exit 1
dev=$(_dev) || exit 1
_paths "$dev"
MARK="$FLDIR/watch-mark-$dev"

[ -n "$(_alive "$dev")" ] || { echo "no run on $dev — bin/start.sh first" >&2; exit 2; }

WPAT='Reloaded .* in |reload.*(failed|rejected)|^Error|Exception'

touch "$MARK"
echo "$(date +%H:%M:%S) watching $PROJECT_DIR/$WATCH_DIR -> $(_where) $dev"

while true; do
  changed=$(cd "$PROJECT_DIR" && find "$WATCH_DIR" -name '*.dart' -newer "$MARK" 2>/dev/null | head -20)
  if [ -n "$changed" ]; then
    touch "$MARK"
    sleep 0.4                       # let the editor finish writing
    _sync >/dev/null 2>&1
    echo "$(date +%H:%M:%S) saved: $(echo "$changed" | tr '\n' ' ')"
    # One round trip: the run is still there, the reload, the frame, the result.
    # It waits for flutter's answer to this reload (see reload.sh), so the frame
    # is taken after the reload and the line shown is this reload's.
    out=$(_ssh "[ -r '$RPID' ] && read p fl r < '$RPID' && kill -0 \"\$p\" 2>/dev/null || { echo RUN-GONE; tail -5 '$RLOG' 2>/dev/null; exit 0; }
n0=\$(grep -cE '$WPAT' '$RLOG' 2>/dev/null); n0=\${n0:-0}
printf 'r' > '$RFIFO'
i=0; n=\$n0
while [ \$n -le \$n0 ] && [ \$i -lt ${RELOAD_TMO:-60} ]; do
  sleep 1; i=\$((i+1)); n=\$(grep -cE '$WPAT' '$RLOG' 2>/dev/null); n=\${n:-0}
done
sh '$PLATFORM_SH' screenshot '$dev' '$RSHOT'
if [ \$n -gt \$n0 ]; then grep -E '$WPAT' '$RLOG' | tail -n \$((n-n0)); else echo 'no answer from flutter after ${RELOAD_TMO:-60}s'; fi")
    if printf '%s\n' "$out" | grep -qx RUN-GONE; then
      echo "the run on $dev has gone. Last of its log:"
      printf '%s\n' "$out" | grep -vx RUN-GONE
      echo "bin/start.sh to start it again."
      exit 2
    fi
    shot="$FLDIR/shots/$(date +%H%M%S).png"
    _pull "$RSHOT" "$shot" || echo "screenshot could not be fetched"
    printf '%s\n' "$out"
    echo "SHOT: $shot"
    [ "$LOOP" = 1 ] || exit 0
  fi
  sleep "$WATCH_POLL"
done
