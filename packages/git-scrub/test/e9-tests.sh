# A block tells me what and where (E9). Sourced by run-tests.sh after stage1-tests.sh.

echo "findings output (E9)"
R=$TMP/e9; cfg=$(new_repo "$R" 'public=0')
seq 1 250 | gawk '{ print "Ask Varga about item " $1 "." }' > "$R/many.md"; git -C "$R" add many.md
(cd "$R" && "$GS" staged) 2> "$TMP/e9.err" >/dev/null; rc=$?
n=$(/usr/bin/grep -c '^  many.md:[0-9]*  \[real value\]  Varga$' "$TMP/e9.err")
[ "$rc" = 1 ] && [ "$n" = 200 ] && /usr/bin/grep -q '^  \.\.\. and 50 more$' "$TMP/e9.err" \
  && ok "250 findings print the first 200, each with location, category and value, and the count of the rest" || no "the 200-finding cap" "exit $rc, $n lines: $(tail -2 "$TMP/e9.err")"
/usr/bin/grep -q ': 250 line(s), 250 finding(s): real value x250$' "$cfg/log" && ok "the repo's log gets the counts" || no "the repo's log gets the counts" "$(tail -1 "$cfg/log")"
l=${TMPDIR:-/tmp}/git-scrub-staged.log
[ "$(stat -c %a "$l")" = 600 ] && [ "$(stat -c %a "$cfg/log")" = 600 ] && ok "both logs are mode 0600" || no "logs mode 0600" "$(stat -c %a "$l") $(stat -c %a "$cfg/log")"
/usr/bin/grep -q Varga "$l" "$cfg/log" && no "neither log holds the value" "found" || ok "neither log holds the value"
git -C "$R" rm -q --cached many.md; printf 'A clean line.\n' > "$R/ok.md"; git -C "$R" add ok.md
(cd "$R" && "$GS" staged) >/dev/null 2>&1
/usr/bin/grep -q ': 1 line(s), 0 finding(s)$' "$l" && ok "a clean run writes its log line too" || no "a clean run logs" "$(cat "$l")"
