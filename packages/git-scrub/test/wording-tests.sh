# Wording tests (E3, C3) over the planted cases. Sourced by run-tests.sh after
# stage1-tests.sh, whose new_repo, by_case, same_set and paths it uses.

mkdir -p "$CLAUDE_DIR/projects"
cp "$CASES/prompts/history.jsonl" "$CLAUDE_DIR/history.jsonl"
cp -r "$CASES/prompts/projects/." "$CLAUDE_DIR/projects/"

wording_rows() { gawk -F'\t' 'NR > 1 && $3 ~ /^cases\// && $2 ~ /^(C3|E3)/' "$CASES/cases.tsv"; }

echo "wording (E3, C3) over the planted cases"
R=$TMP/w1
cfg=$(new_repo "$R" $'public=1')
mkdir -p "$R/cases"
wording_rows | gawk -F'\t' -v r="$R" '{ print $4 > (r "/" $3) }'
git -C "$R" add cases
(cd "$R" && "$GS" staged) 2> "$TMP/w.err" >/dev/null; rc=$?
[ "$rc" = 1 ] && ok "staged exits 1 on wording" || no "staged exits 1 on wording" "exit $rc: $(head -3 "$TMP/w.err")"
by_case < "$TMP/w.err" > "$TMP/wgot.tsv"
while IFS=$'\t' read -r id req where text expect checker note; do
  got=$(gawk -F'\t' -v i="$id" '$1 == i { print $2 }' "$TMP/wgot.tsv"); got=${got:-pass}
  same_set "$got" "$expect" && ok "$id ($req): $expect" || no "$id ($req): $expect" "got: $got"
done < <(wording_rows)

echo "wording scenarios"
w() { # settings file -> categories found for that one case file
  printf '%s\n' "$1" > "$cfg/settings"
  (cd "$R" && "$GS" staged) 2>&1 | by_case | gawk -F'\t' -v i="$2" '$1 == i { print $2 }'
}
git -C "$R" rm -q --cached -r cases; git -C "$R" add cases/W4.md cases/W1.md
got=$(w 'public=1' W4); [ "$got" = wording ] && ok "W15 (E3): on by default in a public repo" || no "W15 (E3): on by default in a public repo" "got: ${got:-pass}"
got=$(w 'public=0' W1); [ -z "$got" ] && ok "W16 (E3): off by default elsewhere" || no "W16 (E3): off by default elsewhere" "got: $got"
got=$(w $'public=0\nwording=1' W1); [ "$got" = wording ] && ok "E3: wording=1 turns it on" || no "E3: wording=1 turns it on" "got: ${got:-pass}"
got=$(w $'public=1\nrun_length=8' W1); [ -z "$got" ] && ok "C3.6: run_length=8 lets W1's 6-word run through" || no "C3.6: run_length=8" "got: $got"
mv "$CLAUDE_DIR/history.jsonl" "$CLAUDE_DIR/history.off"
printf 'public=1\n' > "$cfg/settings"
(cd "$R" && "$GS" staged) >/dev/null 2>"$TMP/w2.err"; rc=$?
[ "$rc" = 2 ] && /usr/bin/grep -q 'prompt log' "$TMP/w2.err" && ok "C8.4: wording on with no prompt log exits 2" || no "C8.4: no prompt log exits 2" "exit $rc: $(cat "$TMP/w2.err")"
mv "$CLAUDE_DIR/history.off" "$CLAUDE_DIR/history.jsonl"
/usr/bin/grep -q -i -E 'lamps|flicker|calendar|porter' "$cfg/log" && no "the log holds none of my wording (E9)" "wording found in the log" || ok "the log holds none of my wording (E9)"
