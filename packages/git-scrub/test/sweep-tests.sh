# Model sweep tests (E4, C4.1 to C4.4). Sourced by run-tests.sh after stage1-tests.sh,
# whose new_repo and paths it uses. Most use the fake claude; the ones labelled
# "(real claude)" call the real one, with the real HOME for its login.

echo "sweep with the fake claude (C4.1 to C4.3)"
R=$TMP/sw1; cfg=$(new_repo "$R" $'public=1\nwording=1')
mkdir -p "$R/cases"; printf 'The parser reads one line at a time and writes a report.\n' > "$R/cases/C0.md"
printf '{"display":"Quillon Varga wants the parser report kept short","pastedContents":{},"project":"/work/proj-a","sessionId":"s-z","timestamp":1767600000000}\n' >> "$CLAUDE_DIR/history.jsonl"
git -C "$R" add cases; rm -f "$TMP/calls" "$TMP/last-prompt"
(cd "$R" && "$GS" staged) >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ -s "$TMP/calls" ] && ok "a clean line goes to the sweep, which answers CLEAN" || no "a clean line is swept" "exit $rc"
/usr/bin/grep -q 'Quillon\|Varga' "$TMP/last-prompt" && no "no stage-1 value is in the prompt" "a value was sent" || ok "no stage-1 value is in the prompt, even in the owner's wording"
/usr/bin/grep -q '\[removed\] wants the parser report kept short' "$TMP/last-prompt" && ok "the owner's related wording is sent with its value removed" || no "related wording sent redacted" "not found"
/usr/bin/grep -q 'Codenames of unreleased features' "$TMP/last-prompt" && /usr/bin/grep -q 'Narrative and commentary' "$TMP/last-prompt" \
  && ok "the prompt holds the repo's categories and the public ones" || no "categories in the prompt" "missing"
/usr/bin/grep -q 'This repository is public' "$TMP/last-prompt" && ok "the public instruction is sent in a public repo" || no "public instruction" "missing"
printf 'public=0\n' > "$cfg/settings"; (cd "$R" && "$GS" staged) >/dev/null 2>&1
/usr/bin/grep -q 'This repository is public\|Narrative and commentary' "$TMP/last-prompt" && no "no public part outside a public repo" "sent" || ok "no public part outside a public repo"
printf 'public=1\n' > "$cfg/settings"
(cd "$R" && FAKE_CLAUDE_ANSWER='FINDING\tcases/C0.md:1\t2\tan unreleased codename' "$GS" staged) 2> "$TMP/sw.err" >/dev/null; rc=$?
[ "$rc" = 1 ] && /usr/bin/grep -q 'cases/C0.md:1  \[sweep: 2\]  an unreleased codename' "$TMP/sw.err" && ok "a sweep finding blocks with exit 1 and its location" || no "a sweep finding blocks" "exit $rc: $(cat "$TMP/sw.err")"
(cd "$R" && FAKE_CLAUDE_ANSWER='I am not sure' "$GS" staged) 2> "$TMP/sw.err" >/dev/null; rc=$?
[ "$rc" = 2 ] && /usr/bin/grep -q 'cases/C0.md:1 .. cases/C0.md:1  \[sweep: batch could not be checked\]' "$TMP/sw.err" \
  && ok "X1 (C4.2): an unusable answer blocks with exit 2 and names the batch's lines" || no "X1 (C4.2): unusable answer exits 2" "exit $rc: $(cat "$TMP/sw.err")"
(cd "$R" && FAKE_CLAUDE_RC=1 FAKE_CLAUDE_ANSWER='' "$GS" staged) >/dev/null 2>&1; rc=$?
[ "$rc" = 2 ] && ok "X1 (C4.2): a claude that exits 1 blocks with exit 2" || no "X1: a failing claude exits 2" "exit $rc"
seq 1 450 | gawk '{ print "Line " $1 " of the parser notes." }' > "$R/cases/long.md"; git -C "$R" add cases/long.md; rm -f "$TMP/calls"
(cd "$R" && FAKE_CLAUDE_ANSWER='garbled' "$GS" staged) 2> "$TMP/sw.err" >/dev/null; rc=$?
[ "$(wc -l < "$TMP/calls")" = 2 ] && [ "$(/usr/bin/grep -c 'could not be checked' "$TMP/sw.err")" = 2 ] \
  && ok "451 lines go in two batches, and the second runs after the first fails" || no "batches of 400" "calls $(wc -l < "$TMP/calls"): $(cat "$TMP/sw.err")"
git -C "$R" rm -q --cached cases/long.md; rm -f "$TMP/calls"
(cd "$R" && SWEEP_SKIP=1 "$GS" staged) >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ ! -e "$TMP/calls" ] && /usr/bin/grep -q 'stage 2 skipped by SWEEP_SKIP=1' "$cfg/log" \
  && ok "SWEEP_SKIP=1 skips the sweep for one run and the log says so" || no "SWEEP_SKIP=1" "exit $rc"
printf 'public=1\nsweep=0\n' > "$cfg/settings"; rm -f "$TMP/calls"
(cd "$R" && "$GS" staged) >/dev/null 2>&1; [ ! -e "$TMP/calls" ] && ok "sweep=0 turns the sweep off" || no "sweep=0 turns the sweep off" "claude was called"
printf 'Quillon Varga\n' > "$R/cases/V.md"; git -C "$R" add cases/V.md; printf 'public=1\n' > "$cfg/settings"; rm -f "$TMP/calls"
(cd "$R" && "$GS" staged) >/dev/null 2>&1; [ ! -e "$TMP/calls" ] && ok "a stage-1 finding stops the run before the sweep" || no "stage 1 findings skip the sweep" "claude was called"
git -C "$R" rm -q --cached cases/V.md
gawk '!/"sessionId":"s-z"/' "$CLAUDE_DIR/history.jsonl" > "$TMP/h" && cp "$TMP/h" "$CLAUDE_DIR/history.jsonl"

echo "sweep with the real claude (E4, C4.4)"
if [ -z "$REAL_CLAUDE" ]; then
  no "E4 (real claude)" "no claude on PATH"
else
  cat > "$TMP/realbin-claude" <<REAL
#!/bin/sh
exec env HOME="$REAL_HOME" "$REAL_CLAUDE" "\$@"
REAL
  mkdir -p "$TMP/realbin"; mv "$TMP/realbin-claude" "$TMP/realbin/claude"; chmod 755 "$TMP/realbin/claude"
  R=$TMP/sw2; cfg=$(new_repo "$R" $'public=1\nwording=0')
  mkdir -p "$R/cases"
  gawk -F'\t' -v r="$R" 'NR > 1 && $2 ~ /E4|C4.4/ && $3 ~ /^cases\// && $5 == "sweep" { print $4 > (r "/" $3) }' "$CASES/cases.tsv"
  git -C "$R" add cases
  (cd "$R" && PATH="$TMP/realbin:$PATH" "$GS" staged) 2> "$TMP/live.err" >/dev/null; rc=$?
  for id in $(gawk -F'\t' 'NR > 1 && $2 ~ /E4|C4.4/ && $3 ~ /^cases\// && $5 == "sweep" { print $1 }' "$CASES/cases.tsv"); do
    /usr/bin/grep -q "cases/$id.md:1  \[sweep" "$TMP/live.err" && ok "$id (real claude): reported by the sweep" || no "$id (real claude): reported by the sweep" "exit $rc"
  done
  printf '%s\n' "$(gawk -F'\t' '$1 == "S6" { print $4 }' "$CASES/cases.tsv")" > "$TMP/s6"
  (cd "$R" && PATH="$TMP/realbin:$PATH" "$GS" message "$TMP/s6") 2> "$TMP/live6.err" >/dev/null; rc=$?
  [ "$rc" = 1 ] && /usr/bin/grep -q '\[sweep' "$TMP/live6.err" && ok "S6 (real claude): a message describing the edit is reported" || no "S6 (real claude)" "exit $rc: $(cat "$TMP/live6.err")"
  git -C "$R" rm -q --cached -r cases; printf 'The parser reads one line at a time and writes a report.\n' > "$R/cases/C0.md"; git -C "$R" add cases/C0.md
  (cd "$R" && PATH="$TMP/realbin:$PATH" "$GS" staged) 2> "$TMP/live0.err" >/dev/null; rc=$?
  [ "$rc" = 0 ] && ok "C0 (real claude): a clean diff gets CLEAN" || no "C0 (real claude): clean" "exit $rc: $(cat "$TMP/live0.err")"
fi
