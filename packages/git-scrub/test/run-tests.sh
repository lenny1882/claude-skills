#!/usr/bin/env bash
# Tests for git-scrub.
#
# Redirects HOME and CLAUDE_DIR into a temp directory, so the real config is
# never touched. The installer tests come free, from installer-tests.sh, which
# claude-package-kit keeps up to date. This file is the package's own: add the
# behaviour tests below — they are the point.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export CLAUDE_DIR="$TMP/claude"; mkdir -p "$CLAUDE_DIR"
export KIT_SKIP_MACHINE_HOOKS=1   # pre_install and post_install change the real machine, not $HOME

pass=0; fail=0
ok(){ printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s\n    %s\n' "$1" "$2"; fail=$((fail+1)); }

. "$REPO/test/installer-tests.sh"

echo "planted-case set"
if "$REPO/test/cases/check-cases.sh" >/dev/null 2>&1; then
  ok "test/cases is well formed and covers BACKLOG item 6"
else
  no "test/cases is well formed and covers BACKLOG item 6" "see ${TMPDIR:-/tmp}/check-cases.log"
fi

. "$REPO/test/stage1-tests.sh"
. "$REPO/test/wording-tests.sh"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
