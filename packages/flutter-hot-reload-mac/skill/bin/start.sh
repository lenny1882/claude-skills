#!/bin/bash
# Put this checkout's branch and working tree where the build reads it, then
# start `flutter run` there against the device, under a pty that later calls
# can send keys to.
#
#   bin/start.sh              # push the branch, sync, launch, wait for the app
#   bin/start.sh --no-branch  # leave the build checkout's branch alone
#   bin/start.sh --build      # rebuild even though the app is already installed
#
# Exits 0 once the app is up, 3 when the app is already installed and --build
# was not given, and 1 for anything else that stopped it.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh" || exit 1

BRANCH_SYNC=1 BUILD=0
for a in "$@"; do
  case $a in
    --no-branch) BRANCH_SYNC=0 ;;
    --build)     BUILD=1 ;;
    *) echo "start: unknown argument $a" >&2; exit 1 ;;
  esac
done
: "${START_WAIT:=600}"   # seconds to wait for the app, all told
: "${START_POLL:=2}"     # seconds between looks at the log, on the Mac
: "${START_CHUNK:=120}"  # seconds one connection waits before the next

[ "${RUNNER:-flutter}" = flutter ] || {
  echo "start: RUNNER=$RUNNER in the conf; this skill hot-reloads Flutter only" >&2; exit 1; }
[ -n "$REPO" ]   || { echo "start: REPO (the checkout the build reads) is not set in .maestro-drive.conf" >&2; exit 1; }
[ -n "$APP_ID" ] || { echo "start: APP_ID is not set in .maestro-drive.conf" >&2; exit 1; }
_pick_host || exit 1
dev=$(_dev) || exit 1
_paths "$dev"

# --- whose device, whose checkout --------------------------------------------
# Another session's label on this device today: launching would terminate the
# app it is driving and replace its build (maestro-drive item 112).
_label_guard "$dev" || exit 1

_ssh "mkdir -p '$RDIR'" >/dev/null || exit 1

# Another live run building from the same checkout. A checkout and the sync
# below would move HEAD and overwrite WATCH_DIR under it. A second branch at the
# same time needs a second checkout: REPO in a conf profile.
# ls rather than a glob: the remote shell may be zsh, where an unmatched glob is
# an error that stops the script.
others=$(_ssh "for n in \$(ls '$RDIR' 2>/dev/null | grep '^frun-.*\\.pid\$'); do
  read p fl r < '$RDIR'/\$n || continue
  kill -0 \"\$p\" 2>/dev/null || continue
  [ \"\$r\" = '$REPO' ] || continue
  u=\${n#frun-}; u=\${u%.pid}; [ \"\$u\" = '$dev' ] || echo \"\$u\"
done
pgrep -f '[/]tmp/frun.py' >/dev/null 2>&1 && echo LEGACY   # [/]: not this script's own text
true")
if printf '%s\n' "$others" | grep -qx LEGACY; then
  echo "start: a flutter-hot-reload-mac 1.0 run is live on $(_where) (/tmp/frun.py)." >&2
  echo "  1.0 shares one fifo and log for every device. Stop it from the session that" >&2
  echo "  started it, or 'pkill -f /tmp/frun.py' on that machine if it is yours." >&2
  exit 1
fi
others=$(printf '%s\n' "$others" | grep -v '^$' || true)
if [ -n "$others" ]; then
  echo "start: $REPO is in use by a live run on $(printf '%s ' $others)" >&2
  echo "  A checkout or a sync here would change the code under it. Use a second" >&2
  echo "  checkout for this device: REPO in a .maestro-drive.conf.<name> profile," >&2
  echo "  run with PROFILE=<name>." >&2
  exit 1
fi

# --- already installed? -------------------------------------------------------
# This skill builds from source. A request to drive an app that is already on
# the device is maestro-drive's, and this skill being reached for instead cost
# four sessions in one day (BACKLOG item 16). So an installed app stops here,
# and only an explicit --build goes on.
_mods() {  # push the runner modules this needs, where they are not already
  _fs_shared && return 0
  local m f
  for m in flutter "${PLATFORM:-ios}"; do
    _ssh "mkdir -p '$RMODS/$m'" >/dev/null || return 1
    for f in "$MD_DIR/runners/$m/"*.sh "$MD_DIR/runners/$m/"*.py; do
      [ -r "$f" ] || continue
      _push "$f" "$RMODS/$m/" || return 1
    done
  done
}
_mods || { echo "start: could not copy maestro-drive's runner modules to $(_where)" >&2; exit 1; }

# Installed means installed-info printed something, not that it exited 0: the
# Android module prints nothing and still exits 0 for an app that is not there.
if [ "$BUILD" = 0 ] && [ -n "$(_ssh "sh '$PLATFORM_SH' installed-info '$dev' '$APP_ID'" 2>/dev/null)" ]; then
  if ! _alive "$dev" >/dev/null; then
    echo "start: $APP_ID is already installed on $dev." >&2
    echo "  To drive it — tap, type, navigate, test — that is maestro-drive, not this." >&2
    echo "  To rebuild it from this checkout and hot reload your edits: bin/start.sh --build" >&2
    exit 3
  fi
fi

# --- what to build ------------------------------------------------------------
# maestro-drive works out the SDK, the flavour and the entry file from the
# checkout, and refuses when the flavour cannot be decided. BUILD_FLAVOR and
# BUILD_TARGET override it, as they do for its own build.
if [ -z "$BUILD_FLAVOR$BUILD_TARGET" ]; then
  desc=$(_ssh "RDIR='$RDIR' sh '$FRAMEWORK_SH' describe '$REPO' '$APP_ID' --env") || {
    echo "start: maestro-drive could not decide what to build (above). Set BUILD_FLAVOR in the conf." >&2; exit 1; }
else
  desc=$(_ssh "RDIR='$RDIR' sh '$RMODS/flutter/build.sh' --repo '$REPO' --app-id '$APP_ID' \
    ${BUILD_FLAVOR:+--flavor '$BUILD_FLAVOR'} ${BUILD_TARGET:+--target '$BUILD_TARGET'} --detect --env") || {
    echo "start: maestro-drive refused BUILD_FLAVOR/BUILD_TARGET (above)." >&2; exit 1; }
fi
FL= FV= TG= GH=
while IFS= read -r line; do
  case $line in
    FLUTTER=*)  FL=${line#FLUTTER=} ;;
    FLAVOR=*)   FV=${line#FLAVOR=} ;;
    TARGET=*)   TG=${line#TARGET=} ;;
    GEM_HOME=*) GH=${line#GEM_HOME=} ;;
  esac
done <<< "$desc"
[ "$FHRM_NO_FLAVOR" = 1 ] && FV=
[ -n "$FL" ] || { echo "start: maestro-drive found no Flutter SDK for $REPO" >&2; exit 1; }
: "${TG:=lib/main.dart}"

# --- the branch -----------------------------------------------------------------
same_checkout=0
_fs_shared && [ "$PROJECT_DIR" -ef "$REPO" ] && same_checkout=1
if [ "$BRANCH_SYNC" = 1 ] && [ "$same_checkout" = 0 ]; then
  branch=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD) || exit 1
  there=$(_ssh "git -C '$REPO' rev-parse --abbrev-ref HEAD") || exit 1
  # Uncommitted work outside what this skill syncs is someone's: a checkout
  # would carry it onto another branch or stop halfway, and a fast-forward
  # would refuse or mix it in. WATCH_DIR is expected to differ — the last sync
  # put it there — and the two lock files are build output there.
  # WATCH_ASSETS likewise: the watcher syncs them too.
  excl=; for a in $WATCH_DIR $WATCH_ASSETS; do excl="$excl ':(exclude)$a'"; done
  dirty=$(_ssh "git -C '$REPO' status --porcelain --untracked-files=no -- . \
    $excl ':(exclude)ios/Podfile.lock' ':(exclude)pubspec.lock'")
  if [ -n "$dirty" ]; then
    echo "start: $REPO on $(_where) is on $there with uncommitted changes:" >&2
    printf '%s\n' "$dirty" | sed 's/^/    /' >&2
    echo "  Moving it to $branch would carry them across or stop halfway." >&2
    echo "  Commit or discard them there, or --no-branch to build $there as it is." >&2
    exit 1
  fi
  echo "pushing $branch to $(_where):$REPO"
  # Pushing TO the build checkout is how a branch gets there. Never push FROM it.
  # Into refs/remotes/fhrm/, never refs/heads/: a non-bare repo refuses a push
  # to the branch it has checked out (receive.denyCurrentBranch), which is the
  # branch every restart pushes. The branch itself is then moved there, below.
  dest="$REPO"; _fs_shared || dest="$MAC_HOST:$REPO"
  GIT_SSH_COMMAND="ssh ${SSH_OPTS[*]}" git -C "$PROJECT_DIR" \
    push -q "$dest" "+$branch:refs/remotes/fhrm/$branch" || exit 1
  # WATCH_DIR and the lock files go back to HEAD first — the sync puts this
  # checkout's WATCH_DIR back straight after. A branch that is not a
  # fast-forward of what is there was rewritten here, or committed to there;
  # either way it is not this script's to overwrite.
  moved=$(_ssh "cd '$REPO' || exit 1
for f in $WATCH_DIR $WATCH_ASSETS ios/Podfile.lock pubspec.lock; do git checkout -q -- \"\$f\" 2>/dev/null; done   # one by one: a path that is not there would stop all three
if git rev-parse -q --verify 'refs/heads/$branch' >/dev/null; then
  git merge-base --is-ancestor 'refs/heads/$branch' 'refs/remotes/fhrm/$branch' || { echo NOT-FF; exit 0; }
  [ '$there' = '$branch' ] || git checkout -q '$branch' || { echo CHECKOUT-FAILED; exit 0; }
  git merge -q --ff-only 'refs/remotes/fhrm/$branch' || { echo MERGE-FAILED; exit 0; }
else
  git checkout -q -b '$branch' 'refs/remotes/fhrm/$branch' || { echo CHECKOUT-FAILED; exit 0; }
fi
echo \"on \$(git rev-parse --abbrev-ref HEAD) \$(git log -1 --format=%h)\"") || exit 1
  case $moved in
    on\ *) echo "  $moved" ;;
    NOT-FF)
      echo "start: $branch in $REPO on $(_where) has commits this checkout does not." >&2
      echo "  It was rewritten here (a rebase or amend) or committed to there. Neither is" >&2
      echo "  this script's to overwrite. Look there, or --no-branch to build it as it is." >&2
      exit 1 ;;
    *) echo "start: could not move $REPO on $(_where) to $branch ($moved)" >&2; exit 1 ;;
  esac
fi

if [ "$same_checkout" = 0 ]; then
  echo "syncing $WATCH_DIR/"
  _sync || exit 1
  for a in $WATCH_ASSETS; do
    [ -d "$PROJECT_DIR/$a" ] || continue
    echo "syncing $a/"; _sync "$a" || exit 1
  done
fi
# The watcher's marker starts here: what was just synced is not a save to replay.
touch "$(_mark "$dev")"
_fs_shared || _push "$FHRM_SKILL/remote/frun.py" "$RPY" || exit 1

# --- launch ---------------------------------------------------------------------
# This device's own previous run, and only that: other devices' runs, and other
# sessions', are left alone.
old=$(_alive "$dev")
if [ -n "$old" ]; then
  echo "stopping this device's previous run (pid ${old%% *})"
  _ssh "kill ${old%% *} 2>/dev/null; i=0; while kill -0 ${old%% *} 2>/dev/null && [ \$i -lt 10 ]; do sleep 1; i=\$((i+1)); done" >/dev/null
fi

echo "starting flutter run on $dev (flavour ${FV:-none}, $TG)"
_ssh "rm -f '$RLOG'
export FRUN_REPO='$REPO' FRUN_DEV='$dev' FRUN_FLUTTER='$FL'
export FRUN_FLAVOR='$FV' FRUN_TARGET='$TG' FRUN_GEM_HOME='$GH'
export FRUN_FIFO='$RFIFO' FRUN_LOG='$RLOG' FRUN_PID='$RPID'
# setsid where there is one: over maestro-drive's bridge each request runs under
# timeout, which kills its whole process group a call or two later, and nohup
# leaves frun.py in that group. macOS has no setsid; over ssh nohup is enough.
sid=; command -v setsid >/dev/null 2>&1 && sid=setsid
cd '$RDIR' && \$sid nohup python3 '$RPY' > '$RERR' 2>&1 < /dev/null &
sleep 2; echo launched" || exit 1

# A cold build of a branch not built there before takes minutes; an incremental
# one about 40s. "key commands" is the line flutter prints once the app is up.
# The looking happens on the Mac, every START_POLL seconds, so each connection
# waits up to START_CHUNK seconds rather than answering one look (BACKLOG
# item 9): a ten-minute build is five connections, not sixty, and the app being
# up is seen within START_POLL of it.
looks=$(awk -v c="$START_CHUNK" -v p="$START_POLL" 'BEGIN { n = int(c / p); print (n < 1 ? 1 : n) }')
chunk_tmo=$(awk -v c="$START_CHUNK" -v p="$START_POLL" 'BEGIN { print int(c + p + 30) }')
printf 'waiting for the app'
state=wait; t0=$SECONDS
while [ $((SECONDS - t0)) -lt "$START_WAIT" ]; do
  state=$(TMO=$chunk_tmo _ssh "i=0
while :; do
  if grep -q 'key commands' '$RLOG' 2>/dev/null; then echo up; break
  elif grep -qE 'Error launching|Could not build|flutter run exited' '$RLOG' 2>/dev/null; then echo failed; break; fi
  i=\$((i+1)); [ \$i -ge $looks ] && { echo wait; break; }
  sleep $START_POLL
done")
  # No answer at all is a dropped connection, not a verdict on the build.
  [ -n "$state" ] || { state=wait; sleep "$START_POLL"; }
  [ "$state" = wait ] || break
  printf ' %ds' $((SECONDS - t0))
done
echo
case $state in
  up) echo "up after $((SECONDS - t0))s. log: $(_where):$RLOG" ;;
  failed) echo "failed. Last of $RLOG:"; _ssh "tail -25 '$RLOG'; tail -5 '$RERR'"; exit 1 ;;
  *) echo "gave up waiting after $((SECONDS - t0))s. Last of $RLOG:"; _ssh "tail -25 '$RLOG'"; exit 1 ;;
esac
