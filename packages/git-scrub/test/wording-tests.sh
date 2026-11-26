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

echo "C3.2's order: the prompt's own session first"
# O1 is held in its own session and in another; O2 only in another. A fake jq records
# which transcripts produced() reads.
cp "$CLAUDE_DIR/history.jsonl" "$TMP/history.keep"; cp "$CLAUDE_DIR/projects/-work-proj-a/s-a1.jsonl" "$TMP/s-a1.keep"
o1='The ferry timetable changes twice before the winter storms arrive.'
o2='Every lantern on the quay is checked against the harbour ledger.'
for t in "$o1" "$o2"; do
  jq -nc --arg t "$t" '{type: "assistant", isSidechain: false, sessionId: "s-b1", timestamp: "2026-01-06T09:00:00.000Z", message: {role: "assistant", content: [{type: "text", text: $t}]}}'
done > "$TMP/s-b1.jsonl"; mkdir -p "$CLAUDE_DIR/projects/-work-proj-b"; mv "$TMP/s-b1.jsonl" "$CLAUDE_DIR/projects/-work-proj-b/s-b1.jsonl"
jq -nc --arg t "$o1" '{type: "assistant", isSidechain: false, sessionId: "s-a1", timestamp: "2026-01-06T08:59:00.000Z", message: {role: "assistant", content: [{type: "text", text: $t}]}}' >> "$CLAUDE_DIR/projects/-work-proj-a/s-a1.jsonl"
n=0; for t in "$o1" "$o2"; do n=$((n + 1))
  jq -nc --arg t "yes, ${t,}" --argjson ts $((1767690000000 + n * 60000)) '{display: $t, pastedContents: {}, project: "/work/proj-a", sessionId: "s-a1", timestamp: $ts}' >> "$CLAUDE_DIR/history.jsonl"
done
mkdir -p "$TMP/jqbin"; realjq=$(command -v jq)
# It keeps its file arguments, and the lines it reads on stdin when it has none.
printf '#!/bin/sh\nprintf "%%s\\n" "$@" >> "%s"\ncase "$*" in *.jsonl*) exec "%s" "$@" ;; esac\ntee -a "%s" | "%s" "$@"\n' "$TMP/jq.args" "$realjq" "$TMP/jq.stdin" "$realjq" > "$TMP/jqbin/jq"; chmod 755 "$TMP/jqbin/jq"
read_s() { /usr/bin/grep -q "$1\\.jsonl\$" "$TMP/jq.args" || /usr/bin/grep -q "\"sessionId\":\"$1\"" "$TMP/jq.stdin"; }   # SESSION: did jq read any of it
# A fake grep records every search over the whole transcript folder.
printf '#!/bin/sh\ncase "$*" in *"/projects/"*) echo x >> "%s" ;; esac\nexec /usr/bin/grep "$@"\n' "$TMP/grep.calls" > "$TMP/jqbin/grep"; chmod 755 "$TMP/jqbin/grep"
printf 'public=1\n' > "$cfg/settings"
o() { # ID TEXT: categories found for that one file, with the transcripts read in jq.args
  git -C "$R" rm -q --cached -r --ignore-unmatch cases; printf '%s\n' "$2" > "$R/cases/$1.md"; git -C "$R" add "cases/$1.md"; : > "$TMP/jq.args"; : > "$TMP/jq.stdin"; : > "$TMP/grep.calls"
  (cd "$R" && PATH="$TMP/jqbin:$PATH" GIT_SCRUB_GREP=$TMP/jqbin/grep "$GS" staged) 2>&1 | by_case | gawk -F'\t' -v i="$1" '$1 == i { print $2 }'
}
got=$(o O1 "$o1")
[ -z "$got" ] && ok "O1 (C3.2): held in its own session, so not reported" || no "O1 (C3.2): not reported" "got: $got"
read_s s-b1 && no "O1 (C3.2): no other session's transcript is read" "s-b1.jsonl was read" || ok "O1 (C3.2): no other session's transcript is read"
[ -s "$TMP/grep.calls" ] && no "O1 (C3.2): no search over every transcript" "$(wc -l < "$TMP/grep.calls") run" || ok "O1 (C3.2): no search over every transcript"
got=$(o O2 "$o2")
[ -z "$got" ] && ok "O2 (C3.2): held only in another session, so not reported" || no "O2 (C3.2): not reported" "got: $got"
read_s s-b1 && ok "O2 (C3.2): the other session's transcript is read" || no "O2 (C3.2): the other session's transcript is read" "s-b1.jsonl not read"
git -C "$R" rm -q --cached -r --ignore-unmatch cases
mv "$TMP/history.keep" "$CLAUDE_DIR/history.jsonl"; mv "$TMP/s-a1.keep" "$CLAUDE_DIR/projects/-work-proj-a/s-a1.jsonl"; rm -rf "$CLAUDE_DIR/projects/-work-proj-b"

echo "C3.2's paraphrase search: only files holding every word of the key"
# P1 paraphrases a typed sentence. s-c1 holds a clause of Claude's with every shared
# word; s-d1 holds only some of them, so it can never rule P1 out and is never read.
cp "$CLAUDE_DIR/history.jsonl" "$TMP/history.keep"
p1='Before any fog rolls in, the pilot signals the trawler from the harbour.'
mkdir -p "$CLAUDE_DIR/projects/-work-proj-c" "$CLAUDE_DIR/projects/-work-proj-d"
a() { jq -nc --arg s "$1" --arg t "$2" '{type: "assistant", isSidechain: false, sessionId: $s, timestamp: "2026-01-07T09:00:00.000Z", message: {role: "assistant", content: [{type: "text", text: $t}]}}'; }
a s-c1 'The pilot signals the trawler in the harbour when fog rolls in.' > "$CLAUDE_DIR/projects/-work-proj-c/s-c1.jsonl"
a s-d1 'The pilot and the trawler met in the harbour.' > "$CLAUDE_DIR/projects/-work-proj-d/s-d1.jsonl"
jq -nc '{display: "the harbour pilot should signal the trawler before the fog rolls in", pastedContents: {}, project: "/work/proj-a", sessionId: "s-a1", timestamp: 1767780000000}' >> "$CLAUDE_DIR/history.jsonl"
mv "$CLAUDE_DIR/projects/-work-proj-c" "$TMP/proj-c.off"
got=$(o P1 "$p1")
[ "$got" = "close to wording" ] && ok "P1 (C3.3): with no transcript holding it, reported as a paraphrase" || no "P1 (C3.3): reported as a paraphrase" "got: ${got:-pass}"
mv "$TMP/proj-c.off" "$CLAUDE_DIR/projects/-work-proj-c"
got=$(o P1 "$p1")
[ -z "$got" ] && ok "P1 (C3.2): held in another session, so not reported" || no "P1 (C3.2): not reported" "got: $got"
read_s s-c1 && ok "P1 (C3.2): the transcript holding every word is read" || no "P1 (C3.2): s-c1 read" "s-c1.jsonl not read"
read_s s-d1 && no "P1 (C3.2): a transcript holding only some words is not read" "s-d1.jsonl was read" || ok "P1 (C3.2): a transcript holding only some words is not read"
git -C "$R" rm -q --cached -r --ignore-unmatch cases
mv "$TMP/history.keep" "$CLAUDE_DIR/history.jsonl"; rm -rf "$CLAUDE_DIR/projects/-work-proj-c" "$CLAUDE_DIR/projects/-work-proj-d"
