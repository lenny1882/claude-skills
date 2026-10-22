#!/bin/bash
# Put this checkout's branch and working tree on the Mac, then start
# `flutter run` there against the simulator.
#
#   bin/start.sh              # push the branch, sync, launch, wait for the app
#   bin/start.sh --no-branch  # leave the Mac's branch alone, just sync + launch
#
# Exits 0 once the app is on the simulator, non-zero if it never got there.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh" || exit 1

BRANCH_SYNC=1
[ "${1:-}" = "--no-branch" ] && BRANCH_SYNC=0

_pick_host || exit 1
dev=$(_dev) || exit 1
[ -n "$REPO" ] || { echo "REPO (the checkout on the Mac) is not set" >&2; exit 1; }

if [ "$BRANCH_SYNC" = 1 ]; then
  branch=$(cd "$PROJECT_DIR" && git rev-parse --abbrev-ref HEAD)
  echo "pushing $branch to $MAC_HOST:$REPO"
  # Pushing TO the Mac is how a branch gets there. Never push FROM it.
  (cd "$PROJECT_DIR" && git push "$MAC_HOST:$REPO" "$branch") || exit 1
  # Podfile.lock and pubspec.lock are build output on the Mac and block the
  # checkout every time. Discarding them is safe; they get rewritten.
  _ssh "cd '$REPO' && git checkout -- ios/Podfile.lock pubspec.lock 2>/dev/null;
        git checkout '$branch' 2>&1 | tail -2" || exit 1
fi

echo "syncing $WATCH_DIR/"
rsync -az --delete -e "ssh ${SSH_OPTS[*]}" \
  "$PROJECT_DIR/$WATCH_DIR/" "$MAC_HOST:$REPO/$WATCH_DIR/" || exit 1

scp "${SSH_OPTS[@]}" -q "$HERE/../remote/frun.py" "$MAC_HOST:$RPY" || exit 1

echo "starting flutter run on $dev (flavor ${FLAVOR:-none}, $TARGET)"
_ssh "pkill -f frun.py; pkill -f 'flutter_tools.snapshot run'; sleep 1
export FRUN_REPO='$REPO' FRUN_DEV='$dev' FRUN_FLUTTER='$FLUTTER_BIN'
export FRUN_FLAVOR='$FLAVOR' FRUN_TARGET='$TARGET'
cd /tmp && nohup /usr/bin/python3 $RPY >$RERR 2>&1 &
sleep 2; echo launched"

# A cold build on a branch the Mac has not built before takes minutes; an
# incremental one takes about 40s. "key commands" is the line flutter prints
# once the app is on the device.
echo -n "waiting for the app"
for _ in $(seq 1 60); do
  if _ssh "grep -q 'key commands' $RLOG 2>/dev/null" ; then echo " — up"; break; fi
  if _ssh "grep -qE 'Error launching|Could not build|exited' $RLOG 2>/dev/null"; then
    echo " — failed"; _ssh "tail -25 $RLOG"; exit 1
  fi
  echo -n "."
  _ssh 'sleep 10' >/dev/null 2>&1
done

_ssh "grep -q 'key commands' $RLOG" || {
  echo; echo "gave up waiting. Last of $RLOG:"; _ssh "tail -25 $RLOG"; exit 1; }

echo "log: $MAC_HOST:$RLOG   commands: printf 'r' > $RFIFO"
