#!/usr/bin/env bash
# Tests for mate.
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
HOOK="$REPO/hooks/mate-bare-word.sh"
SK="$TMP/hooktest"; mkdir -p "$SK/skills"; ln -s "$REPO/skill" "$SK/skills/mate"
run_hook(){ printf '%s' "$1" | CLAUDE_DIR="$SK" "$HOOK"; }
ctx(){ run_hook "$(jq -n --arg p "$1" '{prompt:$p}')" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }

for p in "mate" "bruv" "dude" "  Mate!  " "DUDE?" "bruv..." $'mate\n'; do
  c=$(ctx "$p")
  case "$c" in *"Name the fault"*) ok "bare word $(printf '%q' "$p") runs the skill" ;;
    *) no "bare word $(printf '%q' "$p") runs the skill" "got: ${c:0:80}" ;; esac
done
c=$(ctx "Bruv"); case "$c" in *'only "bruv"'*) ok "context names the word typed" ;;
  *) no "context names the word typed" "got: ${c:0:80}" ;; esac
case "$(ctx mate)" in *"disable-model-invocation"*) no "frontmatter left out of context" "frontmatter present" ;;
  *) ok "frontmatter left out of context" ;; esac

for p in "mate, why is that?" "thanks mate" "what does /mate do" "matey" "/mate" "dudes" ""; do
  out=$(run_hook "$(jq -n --arg p "$p" '{prompt:$p}')"); rc=$?
  [ "$rc" = 0 ] && [ -z "$out" ] && ok "passes through $(printf '%q' "$p")" \
    || no "passes through $(printf '%q' "$p")" "rc=$rc out=${out:0:80}"
done

out=$(printf 'not json' | CLAUDE_DIR="$SK" "$HOOK"); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "bad input fails open" || no "bad input fails open" "rc=$rc"
out=$(printf '{"prompt":"mate"}' | CLAUDE_DIR="$TMP/nowhere" "$HOOK"); rc=$?
[ "$rc" = 0 ] && [ -z "$out" ] && ok "missing skill fails open" || no "missing skill fails open" "rc=$rc"

for n in bruv dude; do
  f="$REPO/aliases/$n/SKILL.md"
  grep -qx "name: $n" "$f" && grep -qx 'disable-model-invocation: true' "$f" \
    && grep -q 'skills/mate/SKILL.md' "$f" && ok "/$n points at mate" || no "/$n points at mate" "$f"
done
grep -qx 'name: mate' "$REPO/skill/SKILL.md" && grep -qx 'disable-model-invocation: true' "$REPO/skill/SKILL.md" \
  && ok "mate is typed-only" || no "mate is typed-only" "frontmatter"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
