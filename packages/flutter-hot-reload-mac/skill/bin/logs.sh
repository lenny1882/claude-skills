#!/bin/bash
# The app's print/debugPrint output from a physical iPhone (BACKLOG item 21).
# A phone run's own log carries flutter's output but not the app's: that comes
# from the phone's syslog, which maestro-drive's `framework.sh logs` reads with
# the Flutter SDK's idevicesyslog, keeping the `flutter: ` lines.
#
#   bin/logs.sh            # stream for LOGS_FOR seconds (600), then stop
#   bin/logs.sh 120        # for 120 seconds
#
# Writes to $FLDIR/logs-<udid>.log as it goes, and prints that path first; run
# it with run_in_background and read the file. The stream is bounded on the
# Mac as well, so nothing is left reading the phone's syslog afterwards.
# The [i] keeps pkill from matching the shell that runs this very line.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh" || exit 1

secs=${1:-${LOGS_FOR:-600}}
case $secs in ''|*[!0-9]*) echo "logs: seconds must be a number, not '$secs'" >&2; exit 1 ;; esac
_phone || { echo "logs: for a phone only (PLATFORM=ios-device). A simulator's output is in the run's log: $(_where):$RDIR/frun-<udid>.log" >&2; exit 1; }
_pick_host || exit 1
dev=$(_dev) || exit 1

# The SDK the run uses, as start.sh finds it.
FL=$(_ssh "RDIR='$RDIR' sh '$FRAMEWORK_SH' describe '$REPO' '$APP_ID' --env" 2>/dev/null | sed -n 's/^FLUTTER=//p')
[ -n "$FL" ] || { echo "logs: maestro-drive found no Flutter SDK for $REPO" >&2; exit 1; }

out="$FLDIR/logs-$dev.log"
echo "$(date +%H:%M:%S) app output from $dev for ${secs}s -> $out"
: > "$out"
TMO=$((secs + 30)) _ssh "sh '$FRAMEWORK_SH' logs '$dev' '$FL' & p=\$!
i=0; while [ \$i -lt $secs ] && kill -0 \$p 2>/dev/null; do sleep 1; i=\$((i+1)); done
pkill -f '[i]devicesyslog -u $dev' 2>/dev/null; pkill -P \$p 2>/dev/null; kill \$p 2>/dev/null; wait \$p 2>/dev/null; true" 2>&1 |
  # idevicesyslog writes the app's colour codes and non-ASCII bytes as text:
  # \134^[[90m for a colour, \M-p\M^_ for each byte of an emoji. Both go.
  sed -u -e 's/\\134^\[\[[0-9;]*m//g' -e 's/\\M[-^].//g' >> "$out"
echo "$(date +%H:%M:%S) stopped; $(grep -c 'flutter: ' "$out") app lines in $out"
