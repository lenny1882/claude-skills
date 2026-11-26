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
REAL_HOME=$HOME; REAL_CLAUDE=${GIT_SCRUB_TEST_CLAUDE-$(command -v claude || true)}   # for E4's live sweep checks only; empty skips them as a FAIL
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

# Every other test gets a fake claude that answers CLEAN, so no test spends usage
# unless it says so in its label. FAKE_CLAUDE_ANSWER and FAKE_CLAUDE_RC change its answer;
# it keeps the last prompt it was sent, for the tests to read.
mkdir -p "$TMP/fakebin"
cat > "$TMP/fakebin/claude" <<'FAKE'
#!/bin/sh
cat > "$FAKE_CLAUDE_DIR/prompt.$$"; mv "$FAKE_CLAUDE_DIR/prompt.$$" "$FAKE_CLAUDE_DIR/last-prompt"
echo x >> "$FAKE_CLAUDE_DIR/calls"
printf '%b\n' "${FAKE_CLAUDE_ANSWER:-CLEAN}"; exit "${FAKE_CLAUDE_RC:-0}"
FAKE
chmod 755 "$TMP/fakebin/claude"; export FAKE_CLAUDE_DIR=$TMP; export PATH="$TMP/fakebin:$PATH"

. "$REPO/test/stage1-tests.sh"
. "$REPO/test/e9-tests.sh"
. "$REPO/test/wording-tests.sh"
. "$REPO/test/write-hook-tests.sh"
. "$REPO/test/e8-tests.sh"
. "$REPO/test/history-tests.sh"
. "$REPO/test/rewrite-tests.sh"
. "$REPO/test/sweep-tests.sh"
. "$REPO/test/uninstall-tests.sh"
. "$REPO/test/private-tests.sh"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
