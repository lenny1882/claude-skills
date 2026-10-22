#!/usr/bin/env bash
# Tests for phase-worktrees.
#
# Redirects HOME and CLAUDE_DIR into a temp directory, so the real config is
# never touched. Add cases for the behaviour itself below the installer ones —
# the installer tests come free, the behaviour tests are the point.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d); trap 'git -C "$TMP/proj" worktree prune 2>/dev/null; rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export CLAUDE_DIR="$TMP/claude"; mkdir -p "$CLAUDE_DIR"

pass=0; fail=0
ok(){ printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s\n    %s\n' "$1" "$2"; fail=$((fail+1)); }

. "$REPO/test/installer-tests.sh"

SCRIPT="$REPO/skill/bin/phase-worktrees.sh"
has(){ grep -q "$2" "$1" && ok "$3" || no "$3" "$(head -3 "$1")"; }

echo "script sanity"
bash -n "$SCRIPT" && ok "script parses" || no "script parses" "syntax error"
"$SCRIPT" --help >"$TMP/o" 2>&1 && ok "--help exits clean" || no "--help exits clean" "non-zero exit"
has "$TMP/o" "one git worktree per GSD phase" "--help says what it does"

echo "preflight"
( cd "$TMP" && "$SCRIPT" 1 ) >"$TMP/o" 2>&1
grep -q "not inside a git repository" "$TMP/o" \
  && ok "refuses outside a git repo" || no "refuses outside a git repo" "$(cat "$TMP/o")"

PROJ="$TMP/proj"; mkdir -p "$PROJ"
git -C "$PROJ" init -q
git -C "$PROJ" config user.email t@example.com
git -C "$PROJ" config user.name Test
echo hello > "$PROJ/README.md"
git -C "$PROJ" add -A && git -C "$PROJ" commit -qm init
git -C "$PROJ" branch -m main 2>/dev/null

( cd "$PROJ" && "$SCRIPT" 1 ) >"$TMP/o" 2>&1
grep -q "is this a GSD project" "$TMP/o" \
  && ok "refuses a repo with no .planning/phases" || no "refuses a repo with no .planning/phases" "$(cat "$TMP/o")"

mkdir -p "$PROJ/.planning/phases/01-non-product-requests-hbd20-1786" \
         "$PROJ/.planning/phases/02-plain-phase"
touch "$PROJ/.planning/STATE.md" "$PROJ/.planning/ROADMAP.md"
git -C "$PROJ" add -A && git -C "$PROJ" commit -qm phases

echo "branch naming"
( cd "$PROJ" && "$SCRIPT" --dry-run 1 ) >"$TMP/o" 2>&1
has "$TMP/o" "unit/HBD20-1786-non-product-requests-phase" "a ticket id becomes a unit/ branch"
( cd "$PROJ" && "$SCRIPT" --dry-run 2 ) >"$TMP/o" 2>&1
has "$TMP/o" "gsd/phase-2-plain-phase" "no ticket id falls back to gsd/phase-<n>"
( cd "$PROJ" && "$SCRIPT" --dry-run 9 ) >"$TMP/o" 2>&1
[ -s "$TMP/o" ] && grep -qiv "^$" "$TMP/o" && ok "an unknown phase is rejected" \
  || no "an unknown phase is rejected" "said nothing"
[ ! -d "$TMP/proj-worktrees" ] && ok "--dry-run creates nothing" || no "--dry-run creates nothing" "worktree dir appeared"

echo "create and remove"
( cd "$PROJ" && "$SCRIPT" 1 ) >"$TMP/o" 2>&1
WT="$TMP/proj-worktrees/p1-non-product-requests"
[ -d "$WT" ] && ok "creates the worktree" || no "creates the worktree" "$(tail -3 "$TMP/o")"
[ -d "$WT/.claude" ] && [ ! -L "$WT/.claude" ] \
  && ok ".claude is a real directory, not a symlink" || no ".claude is a real directory, not a symlink" "wrong type — this is the bug the skill exists to avoid"
git -C "$PROJ" branch --list 'unit/*' | grep -q HBD20-1786 \
  && ok "the branch exists" || no "the branch exists" "no unit/ branch"
grep -q '^\.claude/$' "$PROJ/.git/info/exclude" 2>/dev/null \
  && ok ".claude/ added to info/exclude" || no ".claude/ added to info/exclude" "$(cat "$PROJ/.git/info/exclude" 2>/dev/null | tail -2)"

echo "dirty worktrees are protected"
echo scratch > "$WT/uncommitted.txt"
( cd "$PROJ" && "$SCRIPT" --remove 1 ) >"$TMP/o" 2>&1
[ -d "$WT" ] && ok "refuses to remove with uncommitted changes" || no "refuses to remove with uncommitted changes" "removed anyway"
( cd "$PROJ" && "$SCRIPT" --remove --force 1 ) >"$TMP/o" 2>&1
[ ! -d "$WT" ] && ok "--force removes it" || no "--force removes it" "still there"
git -C "$PROJ" branch --list 'unit/*' | grep -q HBD20-1786 \
  && ok "removing keeps the branch" || no "removing keeps the branch" "branch was deleted — committed work would be lost"

echo "installer — the skill directory"
"$REPO/install.sh" --link --yes >/dev/null 2>&1
[ -L "$CLAUDE_DIR/skills/phase-worktrees" ] \
  && ok "--link symlinks the skill" || no "--link symlinks the skill" "not a symlink"
[ -f "$CLAUDE_DIR/skills/phase-worktrees/SKILL.md" ] \
  && ok "SKILL.md resolves through the link" || no "SKILL.md resolves through the link" "missing"
"$REPO/install.sh" --link --yes >/dev/null 2>&1 \
  && ok "reinstalling is safe" || no "reinstalling is safe" "second install failed"
"$REPO/uninstall.sh" --yes >/dev/null 2>&1
[ ! -e "$CLAUDE_DIR/skills/phase-worktrees" ] \
  && ok "uninstall removes it" || no "uninstall removes it" "still installed"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
