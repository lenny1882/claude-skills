#!/usr/bin/env bash
# Tests for one-by-one.
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

echo "behaviour"
# The skill is instructions, so its behaviour is what SKILL.md tells Claude to
# do. These check the frontmatter Claude Code reads and that each instruction
# the backlog item asked for is still there — a rewrite that drops one passes
# every installer test.
S="$REPO/skill/SKILL.md"
fm=$(awk 'NR==1 && $0=="---" {on=1; next} on && $0=="---" {exit} on' "$S")
# Line breaks and runs of spaces folded to one space, so a phrase the text
# happens to wrap across two lines still counts as present.
flat(){ tr '\n' ' ' | tr -s ' '; }
body=$(flat < "$S")
has(){ case "$body" in *"$(printf '%s' "$2" | flat)"*) ok "$1" ;; *) no "$1" "SKILL.md has no: $2" ;; esac; }

[ "$(printf '%s\n' "$fm" | sed -n 's/^name: //p')" = "one-by-one" ] \
  && ok "frontmatter name matches the directory, so /one-by-one resolves" \
  || no "frontmatter name matches the directory" "got: $(printf '%s\n' "$fm" | grep '^name:')"
printf '%s\n' "$fm" | grep -q '^description: .\{40,\}' \
  && ok "frontmatter has a real description" || no "frontmatter has a real description" "missing or short"
printf '%s\n' "$fm" | grep -qx 'disable-model-invocation: true' \
  && ok "typed-only: Claude never loads it uninvited" || no "typed-only" "no disable-model-invocation: true"
grep -qE '<(What|The|One) ' "$S" \
  && no "no template placeholders left" "$(grep -nE '<(What|The|One) ' "$S" | head -1)" \
  || ok "no template placeholders left"
for field in "What it is" Now Options; do has "each item gives $field" "**$field**"; done
has "one item per reply" "Give only the current item"
has "stops after the item" "Do not give the next item, or a preview of it, in the same reply"
has "says where the item sits" '"2 of 5'
has "keeps the original numbering" "Keep the original numbering"
has "checks the current state" "checked rather than remembered"
has "marks the recommended option" "Mark the recommended one"
has "handles skip, next and back" '"skip", "next" or "back"'
has "closing list of every answer" "one closing list"
has "never splits a run of commands" "A run of commands meant to be pasted together"
for n in individually separately; do
  f="$REPO/aliases/$n/SKILL.md"
  grep -qx "name: $n" "$f" && grep -qx 'disable-model-invocation: true' "$f" \
    && grep -q 'skills/one-by-one/SKILL.md' "$f" && ok "/$n points at one-by-one" || no "/$n points at one-by-one" "$f"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
