#!/bin/bash
# What is running, on which device, from which checkout, and what it last did.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
# shellcheck disable=SC1091
. "$HERE/lib.sh" || exit 1

_pick_host || exit 1
echo "where:    $(_where)"
echo "repo:     $REPO"
_ssh "echo \"branch:   \$(git -C '$REPO' rev-parse --abbrev-ref HEAD 2>/dev/null) \$(git -C '$REPO' log -1 --format=%h 2>/dev/null)\"
n=0
for f in \$(ls '$RDIR' 2>/dev/null | grep '^frun-.*\\.pid\$'); do
  read p fl r < '$RDIR'/\$f || continue
  u=\${f#frun-}; u=\${u%.pid}; n=\$((n+1))
  if kill -0 \"\$p\" 2>/dev/null; then s=alive; else s='gone (stale pid file)'; fi
  echo \"run:      \$u  \$s  from \$r\"
  grep -E 'Reloaded .* in |Restarted application|Flutter run key commands|exited' '$RDIR'/frun-\$u.log 2>/dev/null | tail -3 | sed 's/^/            /'
done
[ \$n -gt 0 ] || echo 'run:      none'"
echo "shots:    $FLDIR/shots"
