#!/usr/bin/env bash
# Tests for owl.
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

pass=0; fail=0
ok(){ printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s\n    %s\n' "$1" "$2"; fail=$((fail+1)); }

. "$REPO/test/installer-tests.sh"

echo "behaviour"
# The skill is instructions, so its behaviour is what SKILL.md tells Claude to
# do. These check the frontmatter Claude Code reads and that each instruction
# the backlog item asked for is still there — a rewrite that drops one passes
# every installer test.
S="$REPO/skill/SKILL.md"
fm=$(awk 'NR==1 && $0=="---" {on=1; next} on && $0=="---" {exit} on' "$S")
# Matched with line breaks and runs of spaces folded to one space, so a phrase
# the text happens to wrap across two lines still counts as present.
flat(){ tr '\n' ' ' | tr -s ' '; }
body=$(flat < "$S")
has(){ case "$body" in *"$(printf '%s' "$2" | flat)"*) ok "$1" ;; *) no "$1" "SKILL.md has no: $2" ;; esac; }

[ "$(printf '%s\n' "$fm" | sed -n 's/^name: //p')" = "owl" ] \
  && ok "frontmatter name matches the directory, so /owl resolves" \
  || no "frontmatter name matches the directory" "got: $(printf '%s\n' "$fm" | grep '^name:')"
printf '%s\n' "$fm" | grep -q '^description: .\{40,\}' \
  && ok "frontmatter has a real description" || no "frontmatter has a real description" "missing or short"
printf '%s\n' "$fm" | grep -qx 'disable-model-invocation: true' \
  && ok "typed-only: Claude never loads it uninvited" || no "typed-only" "no disable-model-invocation: true"
grep -qE '<(What|The|One) ' "$S" \
  && no "no template placeholders left" "$(grep -nE '<(What|The|One) ' "$S" | head -1)" \
  || ok "no template placeholders left"
has "names Claude's Bash as a place to run" "Claude's Bash"
has "names ! in Claude Code as a place to run" '`!` in Claude Code'
has "names the user's own terminal as a place to run" "the user's own terminal"
for field in Where Command Needs Capture Expect; do has "each step gives $field" "**$field**"; done
has "covers short-lived or single-use keys" "short-lived or single-use key"
has "excludes long-standing accounts" "Long-standing accounts"
has "runs the steps rather than asking" "do not ask whether to start"
has "ends on one line for the user" "single command left for the user, on one line"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
