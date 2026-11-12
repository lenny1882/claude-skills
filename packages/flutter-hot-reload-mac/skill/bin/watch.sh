#!/bin/bash
# Watch the local WATCH_DIR, sync each save, hot reload, screenshot.
#
#   bin/watch.sh          # handle ONE save, print SHOT: <path>, exit 0
#   bin/watch.sh --loop   # keep going; screenshots still land in the shots dir
#
# The one-shot default exists because of how the harness works, not because
# it is a nicer design: a background Bash task only notifies Claude when it
# EXITS. Exiting after each save is what lets Claude post the screenshot in the
# conversation. Claude relaunches it straight away, and a save made in between
# is not lost: the marker the next run compares against is the one this run
# took just before it last looked, so that save is newer than it and the next
# run handles it at once (BACKLOG item 6). start.sh resets the marker after its
# own sync.
#
# What a save does depends on where it is (BACKLOG item 7):
#   WATCH_DIR (lib)            synced, then hot reload (r)
#   WATCH_ASSETS (assets)      synced, then hot restart (R): a reload leaves the
#                              old image in Flutter's image cache
#   WATCH_REBUILD (pubspec.yaml ios android)
#                              not synced: no reload applies it. Listed as
#                              REBUILD: lines, then exit 4 in the one-shot mode.
#                              It reaches the Mac when committed, through
#                              bin/start.sh --build.
# Each is a space-separated list of paths relative to the project; a path that
# is not there is skipped. Files only: a deletion is synced with the next save
# in that directory, not on its own.
#
# Exits 2, saying so, when the run has gone — flutter run died or was
# stopped — rather than syncing into a dead app. It checks before each reload,
# and every WATCH_ALIVE seconds (default 30, 0 for never) between saves, so a
# death is reported when it happens rather than at the next save.
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
: "${WATCH_ALIVE:=30}"   # seconds between checks that the run is alive; 0 for none

_pick_host || exit 1
dev=$(_dev) || exit 1
_paths "$dev"
MARK=$(_mark "$dev")
NEXT="$MARK.next"

[ -n "$(_alive "$dev")" ] || { echo "no run on $dev — bin/start.sh first" >&2; exit 2; }

gone() {  # gone <last of the log>
  echo "the run on $dev has gone. Last of its log:"
  printf '%s\n' "$1"
  echo "bin/start.sh to start it again."
  exit 2
}

# Kept from the last run, so a save made since it exited is still newer.
[ -e "$MARK" ] || touch "$MARK"
checked=$SECONDS
echo "$(date +%H:%M:%S) watching $PROJECT_DIR/$WATCH_DIR -> $(_where) $dev"

# changed <paths...> — files under them newer than the marker. Editor
# droppings and the build output under ios/ and android/ are not saves.
changed() {
  local p have=()
  for p in "$@"; do [ -e "$PROJECT_DIR/$p" ] && have+=("$p"); done
  [ ${#have[@]} -gt 0 ] || return 0
  (cd "$PROJECT_DIR" && find "${have[@]}" \
     \( -name Pods -o -name .symlinks -o -name ephemeral -o -name build -o -name .gradle \
        -o -name .dart_tool -o -name .cxx \) -prune \
     -o -type f -newer "$MARK" ! -name '.*' ! -name '*~' ! -name '*.swp' ! -name '*.tmp' \
        ! -name 'Generated*' ! -name 'GeneratedPluginRegistrant.*' \
        ! -name flutter_export_environment.sh ! -name local.properties -print 2>/dev/null)
}
# Drops the files that are tracked and identical to HEAD: `git checkout -- pubspec.yaml`
# gives the file a new time but nothing a rebuild would pick up. Outside a git
# checkout every file stays.
unchanged_from_head() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    git -C "$PROJECT_DIR" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 \
      && git -C "$PROJECT_DIR" diff --quiet HEAD -- "$f" 2>/dev/null && continue
    printf '%s\n' "$f"
  done
}
list() { printf '%s\n' "$1" | head -20 | tr '\n' ' '; }

while true; do
  if [ -n "$(changed $WATCH_DIR $WATCH_ASSETS $WATCH_REBUILD | head -1)" ]; then
    sleep 0.4                       # let the editor finish writing
    # The new marker is taken before the final look, so a save after it is
    # newer than it and the next look (or the next run) handles it.
    touch "$NEXT"
    code=$(changed $WATCH_DIR)
    assets=$(changed $WATCH_ASSETS)
    rebuild=$(changed $WATCH_REBUILD | unchanged_from_head)
    mv -f "$NEXT" "$MARK"
    # Only files put back to HEAD: nothing to do, keep watching.
    [ -n "$code$assets$rebuild" ] || { sleep "$WATCH_POLL"; continue; }
    [ -n "$code$assets" ] && echo "$(date +%H:%M:%S) saved: $(list "$code$assets")"
    if [ -n "$code$assets" ]; then
      _sync >/dev/null 2>&1
      for a in $WATCH_ASSETS; do
        [ -n "$assets" ] && [ -d "$PROJECT_DIR/$a" ] && _sync "$a" >/dev/null 2>&1
      done
      key=r; [ -n "$assets" ] && key=R
      # One round trip: the run is still there, the key, the frame, the result
      # and any error the key threw (see _key_script in lib.sh).
      out=$(_ssh "[ -r '$RPID' ] && read p fl r < '$RPID' && kill -0 \"\$p\" 2>/dev/null || { echo RUN-GONE; tail -5 '$RLOG' 2>/dev/null | $CLEAN; exit 0; }
$(_key_script $key "sh '$PLATFORM_SH' screenshot '$dev' '$RSHOT'")")
      printf '%s\n' "$out" | grep -qx RUN-GONE && gone "$(printf '%s\n' "$out" | grep -vx RUN-GONE)"
      checked=$SECONDS
      shot="$FLDIR/shots/$(date +%H%M%S).png"
      _pull "$RSHOT" "$shot" || echo "screenshot could not be fetched"
      [ "$key" = R ] && echo "hot restart, for the assets: the app's state was reset"
      printf '%s\n' "$out"
      echo "SHOT: $shot"
    fi
    if [ -n "$rebuild" ]; then
      echo "$(date +%H:%M:%S) changed, and no reload applies it:"
      printf '%s\n' "$rebuild" | head -20 | sed 's/^/REBUILD: /'
      echo "Not synced. Commit it, then bin/start.sh --build rebuilds with it."
      [ "$LOOP" = 1 ] || exit 4
    fi
    [ "$LOOP" = 1 ] || exit 0
  elif [ "$WATCH_ALIVE" -gt 0 ] && [ $((SECONDS - checked)) -ge "$WATCH_ALIVE" ]; then
    # Between saves (BACKLOG item 10). Only an explicit GONE counts: a failed
    # ssh prints neither word, and a Mac that is slow to answer is not a dead run.
    checked=$SECONDS
    st=$(_ssh "if [ -r '$RPID' ] && read p fl r < '$RPID' && kill -0 \"\$p\" 2>/dev/null; then echo ALIVE; else echo GONE; tail -5 '$RLOG' 2>/dev/null | $CLEAN; fi" 2>/dev/null)
    [ "$(printf '%s\n' "$st" | head -1)" = GONE ] && gone "$(printf '%s\n' "$st" | sed 1d)"
  fi
  sleep "$WATCH_POLL"
done
