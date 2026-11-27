# Write hook tests (E12, C12.1 to C12.4). Sourced by run-tests.sh after
# wording-tests.sh, which put the planted prompt log and transcripts in $CLAUDE_DIR.

echo "write hook (E12)"
R=$TMP/wh1; cfg=$(new_repo "$R" $'public=1'); (cd "$R" && "$GS" enable) >/dev/null
hook() { # SESSION: run the hook as Claude Code would after a tool call in $R
  printf '{"session_id":"%s","cwd":"%s","hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{}}' "$1" "$R" \
    | "$GS" write-hook
}
out=$(hook s1); [ -z "$out" ] && ok "the first call with nothing written says nothing" || no "nothing written, nothing said" "$out"
printf 'We keep the ferry timetable on paper for the night crews at harbour gate.\n' > "$R/notes.md"
out=$(hook s1)
jq -e '.decision == "block"' >/dev/null 2>&1 <<< "$out" && /usr/bin/grep -q 'notes.md:1  \[wording\]' <<< "$(jq -r .reason <<< "$out")" \
  && ok "a Write holding a 6-word typed clause is reported to Claude with file, line and rule" || no "Write with a typed clause" "$out"
/usr/bin/grep -q -i 'ferry timetable' <<< "$out" && no "the report never holds the wording" "it does" || ok "the report never holds the wording"
out=$(hook s1); [ -z "$out" ] && ok "C12.4: an unfixed line is not reported again on the next call" || no "not reported again" "$out"
printf 'The parser reads one line at a time.\n' > "$R/clean.md"; git -C "$R" add clean.md >/dev/null
out=$(hook s1); [ -z "$out" ] && ok "a clean write produces nothing" || no "a clean write produces nothing" "$out"
git -C "$R" commit -qm clean --no-verify
printf 'The parser reads one line at a time.\n(the owner, 11 Nov 2026) chose this.\n' > "$R/clean.md"
out=$(hook s1); /usr/bin/grep -q 'clean.md:2  \[dated attribution\]' <<< "$(jq -r .reason <<< "$out" 2>/dev/null)" \
  && ok "an Edit adding a dated attribution is reported" || no "Edit with a dated attribution" "$out"
cat >> "$R/clean.md" <<'HEREDOC'
The parser was released as 1.2 last spring.
HEREDOC
out=$(hook s1); /usr/bin/grep -q 'clean.md:3  \[release history\]' <<< "$(jq -r .reason <<< "$out" 2>/dev/null)" \
  && ok "a Bash heredoc appending a release line is reported" || no "Bash heredoc release line" "$out"
[ "$(stat -c %a "$R/.git/scrub/seen-s1")" = 600 ] && ok "C12.4: the saved diff is under .git, mode 0600" || no "saved diff mode" "$(stat -c %a "$R/.git/scrub/seen-s1")"
printf '{"session_id":"s1","cwd":"%s","hook_event_name":"SessionEnd"}' "$R" | "$GS" write-hook-end
[ ! -e "$R/.git/scrub/seen-s1" ] && ok "C12.4: the saved diff is removed when the session ends" || no "saved diff removed at session end" "still there"
seq 1 200 | gawk '{ print "Line " $1 " of the parser notes, kept plain." }' > "$R/long.md"
t0=$(date +%s%N); out=$(hook s2); t=$(( ($(date +%s%N) - t0) / 1000000 ))
[ "$t" -lt 1000 ] && ok "a 200-line change is checked in ${t} ms, inside E10's 1 s" || no "200 lines within 1 s" "${t} ms"
printf 'public=0\n' > "$cfg/settings"; printf 'Quillon Varga\n' > "$R/v.md"
first=$(hook s3)
best=99999; for i in 1 2 3 4 5; do t0=$(date +%s%N); out=$(hook s3); t=$(( ($(date +%s%N) - t0) / 1000000 )); [ "$t" -lt "$best" ] && best=$t; done
out="$first$out"
[ -z "$out" ] && [ "$best" -lt 50 ] && ok "in a repo not marked public the hook says nothing, in ${best} ms" || no "not public: nothing within 50 ms" "${best} ms: $out"
R=$TMP/wh2; rm -rf "$R"; git init -q "$R"; printf 'Quillon Varga\n' > "$R/v.md"
first=$(hook s4); best=99999; for i in 1 2 3 4 5; do t0=$(date +%s%N); out=$(hook s4); rc=$?; t=$(( ($(date +%s%N) - t0) / 1000000 )); [ "$t" -lt "$best" ] && best=$t; done
out="$first$out"; [ -z "$out" ] && [ "$rc" = 0 ] && [ "$best" -lt 50 ] && ok "in a repo not enabled the hook says nothing and exits 0, in ${best} ms" || no "not enabled: nothing within 50 ms" "${best} ms, exit $rc: $out"
