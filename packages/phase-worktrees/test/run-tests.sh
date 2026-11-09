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

mkdir -p "$PROJ/.planning/phases/01-new-settings-page-abc-123" \
         "$PROJ/.planning/phases/02-plain-phase"
touch "$PROJ/.planning/STATE.md" "$PROJ/.planning/ROADMAP.md"
git -C "$PROJ" add -A && git -C "$PROJ" commit -qm phases

echo "branch naming"
( cd "$PROJ" && "$SCRIPT" --dry-run 1 ) >"$TMP/o" 2>&1
has "$TMP/o" "unit/ABC-123-new-settings-page-phase" "a ticket id becomes a unit/ branch"
( cd "$PROJ" && "$SCRIPT" --dry-run 2 ) >"$TMP/o" 2>&1
has "$TMP/o" "gsd/phase-2-plain-phase" "no ticket id falls back to gsd/phase-<n>"
( cd "$PROJ" && "$SCRIPT" --dry-run 9 ) >"$TMP/o" 2>&1
[ -s "$TMP/o" ] && grep -qiv "^$" "$TMP/o" && ok "an unknown phase is rejected" \
  || no "an unknown phase is rejected" "said nothing"
[ ! -d "$PROJ/.worktrees" ] && ok "--dry-run creates nothing" || no "--dry-run creates nothing" "worktree dir appeared"

echo "create and remove"
mkdir -p "$PROJ/.claude"; echo '{"permissions":{"allow":["Bash(make test)"]}}' >"$PROJ/.claude/settings.local.json"
( cd "$PROJ" && "$SCRIPT" 1 ) >"$TMP/o" 2>&1
WT="$PROJ/.worktrees/p1-new-settings-page"
[ -d "$WT" ] && ok "creates the worktree" || no "creates the worktree" "$(tail -3 "$TMP/o")"
[ -L "$WT/.claude" ] && [ "$(readlink "$WT/.claude")" = "$PROJ/.claude" ] \
  && ok "with nothing under .claude/ tracked, .claude links to the main checkout's" \
  || no "with nothing under .claude/ tracked, .claude links to the main checkout's" "$(ls -ld "$WT/.claude" 2>&1)"
[ -z "$(git -C "$WT" status --porcelain)" ] \
  && ok "the symlinked .claude does not show in the worktree's git status" || no "the symlinked .claude does not show in the worktree's git status" "$(git -C "$WT" status --porcelain | head -3)"
grep -qx '/.claude' "$PROJ/.git/info/exclude" \
  && ok "/.claude added to info/exclude for the symlink" || no "/.claude added to info/exclude for the symlink" "$(tail -4 "$PROJ/.git/info/exclude")"
git -C "$PROJ" branch --list 'unit/*' | grep -q ABC-123 \
  && ok "the branch exists" || no "the branch exists" "no unit/ branch"
grep -q '^\.claude/$' "$PROJ/.git/info/exclude" 2>/dev/null \
  && ok ".claude/ added to info/exclude" || no ".claude/ added to info/exclude" "$(cat "$PROJ/.git/info/exclude" 2>/dev/null | tail -2)"
grep -qx '/.worktrees/' "$PROJ/.git/info/exclude" 2>/dev/null \
  && ok "the worktree root added to info/exclude" || no "the worktree root added to info/exclude" "$(tail -4 "$PROJ/.git/info/exclude" 2>/dev/null)"
[ -z "$(git -C "$PROJ" status --porcelain)" ] \
  && ok "git status in the main checkout stays clean" || no "git status in the main checkout stays clean" "$(git -C "$PROJ" status --porcelain | head -3)"
( cd "$PROJ" && "$SCRIPT" 2 ) >"$TMP/o" 2>&1
[ "$(grep -cx '/.worktrees/' "$PROJ/.git/info/exclude")" = 1 ] && [ "$(grep -cx '.claude/' "$PROJ/.git/info/exclude")" = 1 ] \
  && ok "a second run adds no duplicate exclude lines" || no "a second run adds no duplicate exclude lines" "$(cat "$PROJ/.git/info/exclude")"
( cd "$PROJ" && "$SCRIPT" --remove 2 ) >"$TMP/o" 2>&1

echo "dirty worktrees are protected"
echo scratch > "$WT/uncommitted.txt"
( cd "$PROJ" && "$SCRIPT" --remove 1 ) >"$TMP/o" 2>&1
[ -d "$WT" ] && ok "refuses to remove with uncommitted changes" || no "refuses to remove with uncommitted changes" "removed anyway"
( cd "$PROJ" && "$SCRIPT" --remove --force 1 ) >"$TMP/o" 2>&1
[ ! -d "$WT" ] && ok "--force removes it" || no "--force removes it" "still there"
grep -q 'make test' "$PROJ/.claude/settings.local.json" 2>/dev/null \
  && ok "removing it leaves the main checkout's .claude alone" || no "removing it leaves the main checkout's .claude alone" "main .claude/settings.local.json gone or changed"
git -C "$PROJ" branch --list 'unit/*' | grep -q ABC-123 \
  && ok "removing keeps the branch" || no "removing keeps the branch" "branch was deleted — committed work would be lost"

echo "GSD's own leftovers do not block --remove"
mkconfig(){ printf '{"workflow":{"use_worktrees":true}}' >"$PROJ/.planning/config.json"; git -C "$PROJ" add .planning/config.json; git -C "$PROJ" commit -qm config; }
[ -f "$PROJ/.planning/config.json" ] || mkconfig
git -C "$PROJ" branch -D gsd/phase-2-plain-phase >/dev/null 2>&1   # made before config.json existed
leftovers(){ WT2="$PROJ/.worktrees/p2-plain-phase"
  printf '{"workflow":{"use_worktrees":true,"_auto_chain_active":false}}\n' >"$WT2/.planning/config.json"
  echo '{}' >"$WT2/.planning/HANDOFF.json"; }
( cd "$PROJ" && "$SCRIPT" 2 ) >"$TMP/o" 2>&1; leftovers
( cd "$PROJ" && "$SCRIPT" --remove 2 ) >"$TMP/o" 2>&1
[ ! -d "$WT2" ] && ok "a worktree holding only HANDOFF.json and the auto-chain flag is removed" \
  || no "a worktree holding only HANDOFF.json and the auto-chain flag is removed" "$(cat "$TMP/o")"
( cd "$PROJ" && "$SCRIPT" 2 ) >"$TMP/o" 2>&1; leftovers; echo work >"$WT2/real.txt"
( cd "$PROJ" && "$SCRIPT" --remove 2 ) >"$TMP/o" 2>&1
[ -f "$WT2/real.txt" ] && grep -q '1 uncommitted change' "$TMP/o" \
  && ok "leftovers plus real work still refuses, counting only the real change" \
  || no "leftovers plus real work still refuses, counting only the real change" "$(cat "$TMP/o")"
rm -f "$WT2/real.txt"
printf '{"workflow":{"use_worktrees":false}}\n' >"$WT2/.planning/config.json"
( cd "$PROJ" && "$SCRIPT" --remove 2 ) >"$TMP/o" 2>&1
[ -d "$WT2" ] && ok "a real config.json change still refuses" || no "a real config.json change still refuses" "removed anyway"
( cd "$PROJ" && "$SCRIPT" --remove --force 2 ) >"$TMP/o" 2>&1

echo "a repo that tracks .claude/ gets a copy, not a symlink"
TP="$TMP/tracked"; mkdir -p "$TP/.planning/phases/01-one" "$TP/.claude/commands"
git -C "$TP" init -q; git -C "$TP" config user.email t@example.com; git -C "$TP" config user.name Test
echo '{"model":"x"}' >"$TP/.claude/settings.json"; echo 'do it' >"$TP/.claude/commands/go.md"; touch "$TP/.planning/phases/01-one/x"
git -C "$TP" add -A; git -C "$TP" commit -qm init
echo '{"permissions":{}}' >"$TP/.claude/settings.local.json"
( cd "$TP" && "$SCRIPT" 1 ) >"$TMP/o" 2>&1
TW="$TP/.worktrees/p1-one"
[ -d "$TW/.claude" ] && [ ! -L "$TW/.claude" ] && ok "tracked .claude/: a real directory" || no "tracked .claude/: a real directory" "$(ls -ld "$TW/.claude" 2>&1)"
[ -f "$TW/.claude/commands/go.md" ] && [ -f "$TW/.claude/settings.local.json" ] \
  && ok "tracked files kept and settings.local.json copied" || no "tracked files kept and settings.local.json copied" "$(ls -A "$TW/.claude" 2>&1)"
[ -z "$(git -C "$TW" status --porcelain)" ] \
  && ok "tracked .claude/: worktree git status clean" || no "tracked .claude/: worktree git status clean" "$(git -C "$TW" status --porcelain | head -3)"
( cd "$TP" && "$SCRIPT" --remove 1 ) >"$TMP/o" 2>&1

echo "a root outside the repo"
( cd "$PROJ" && "$SCRIPT" --root "$TMP/outside" 2 ) >"$TMP/o" 2>&1
[ -d "$TMP/outside/p2-plain-phase" ] && ok "--root outside the repo still works" || no "--root outside the repo still works" "$(tail -3 "$TMP/o")"
grep -q 'outside' "$PROJ/.git/info/exclude" \
  && no "an outside root is not excluded" "$(grep outside "$PROJ/.git/info/exclude")" || ok "an outside root is not excluded"
( cd "$PROJ" && "$SCRIPT" --remove 2 ) >"$TMP/o" 2>&1
[ ! -d "$TMP/outside/p2-plain-phase" ] \
  && ok "--remove finds a worktree outside the default root by its branch" \
  || no "--remove finds a worktree outside the default root by its branch" "$(cat "$TMP/o")"

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
