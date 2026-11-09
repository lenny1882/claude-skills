#!/usr/bin/env bash
# Tests for compare.
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
SBS="$REPO/skill/bin/side-by-side.py"
W="$TMP/sbs"; mkdir -p "$W"
sbs(){ python3 "$SBS" "$W/a" "$W/b" "$@"; }
maxw(){ python3 -c 'import sys,unicodedata as u
print(max(sum(2 if u.east_asian_width(c) in "WF" else 1 for c in l.rstrip("\n")) for l in sys.stdin))'; }

printf 'same\nold\n' >"$W/a"; printf 'same\nnew\n' >"$W/b"
out=$(sbs)
printf '%s\n' "$out" | grep -q '^same  *| same$' && ok "unchanged line marked |" || no "unchanged line marked |" "$out"
printf '%s\n' "$out" | grep -q '^old  *\* new$' && ok "changed line marked *" || no "changed line marked *" "$out"
[ "$(printf '%s\n' "$out" | head -1 | cut -c49-51)" = " | " ] && ok "gutter at columns 49-51" || no "gutter at columns 49-51" "$out"

printf 'a\nb\nc\n' >"$W/a"; printf 'a\nINSERTED\nb\nc\n' >"$W/b"
out=$(sbs)
printf '%s\n' "$out" | grep -q '^  *> INSERTED$' && ok "right-only line marked >" || no "right-only line marked >" "$out"
printf '%s\n' "$out" | grep -q '^c  *| c$' && ok "lines after an insert stay level" || no "lines after an insert stay level" "$out"
printf 'a\nGONE\nb\n' >"$W/a"; printf 'a\nb\n' >"$W/b"
printf '%s\n' "$(sbs)" | grep -q '^GONE  *<$' && ok "left-only line marked <" || no "left-only line marked <" "$(sbs)"

long="This is a much longer line that will certainly need to wrap across more than one row of the column."
printf '%s\nafter\n' "$long" >"$W/a"; printf 'short\nafter\n' >"$W/b"
out=$(sbs)
[ "$(printf '%s\n' "$out" | maxw)" -le 99 ] && ok "no row wider than 99" || no "no row wider than 99" "$out"
printf '%s\n' "$out" | grep -q '^after  *| after$' && ok "row after a wrapped line stays level" || no "row after a wrapped line stays level" "$out"
left=$(printf '%s\n' "$out" | cut -c1-48 | sed 's/ *$//' | head -3 | paste -sd' ')
[ "$left" = "$long" ] && ok "wrapped text is verbatim" || no "wrapped text is verbatim" "$left"

printf '%s\n' "$(printf 'x%.0s' $(seq 1 120))" >"$W/a"; printf 'y\n' >"$W/b"
[ "$(sbs | cut -c1-48 | tr -d ' \n' | wc -c)" = 120 ] && ok "unbroken word split, nothing lost" || no "unbroken word split, nothing lost" "$(sbs)"

printf '日本語のテキストはそれぞれ二列分の幅を取るので折り返しの計算に気をつける必要がある\n' >"$W/a"; printf 'x\n' >"$W/b"
[ "$(sbs | maxw)" -le 99 ] && ok "wide characters counted as two" || no "wide characters counted as two" "$(sbs)"
printf '\tindented\n' >"$W/a"; printf '\tindented\n' >"$W/b"
sbs | grep -q '^    indented  *|     indented$' && ok "tabs become spaces" || no "tabs become spaces" "$(sbs)"

out=$(sbs --left-label "Draft 1" --right-label "Draft 2")
printf '%s\n' "$out" | head -1 | grep -q '^Draft 1  *Draft 2$' && ok "labels head the columns" || no "labels head the columns" "$out"
printf 'a\r\nb\r\n' >"$W/a"; printf 'a\nb\n' >"$W/b"
! sbs | grep -q '\*' && ok "CRLF and LF compare equal" || no "CRLF and LF compare equal" "$(sbs)"

grep -qx 'name: side-by-side' "$REPO/aliases/side-by-side/SKILL.md" \
  && grep -qx 'disable-model-invocation: true' "$REPO/aliases/side-by-side/SKILL.md" \
  && grep -q 'skills/compare/SKILL.md' "$REPO/aliases/side-by-side/SKILL.md" \
  && ok "/side-by-side points at compare" || no "/side-by-side points at compare" "frontmatter"
grep -qx 'name: compare' "$REPO/skill/SKILL.md" && grep -qx 'disable-model-invocation: true' "$REPO/skill/SKILL.md" \
  && ok "compare is typed-only" || no "compare is typed-only" "frontmatter"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
