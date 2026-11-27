# history tests (E6, C6.1, C6.5). Sourced by run-tests.sh after stage1-tests.sh, whose
# new_repo and paths it uses.

echo "history (E6, C6.1, C6.5)"
R=$TMP/h1; cfg=$(new_repo "$R" 'public=0')
mkdir -p "$R/notes"
printf 'Ask Varga about it.\n' > "$R/notes/old plan.md"; git -C "$R" add notes; git -C "$R" commit -qm "Add plan"
git -C "$R" rm -q "notes/old plan.md"; git -C "$R" commit -qm "Drop plan"
printf 'trellisfold\n' > "$cfg/values.txt"
printf 'The trellisfold build.\n' > "$R/same.md"; git -C "$R" add same.md; git -C "$R" commit -qm one
cp "$R/same.md" "$R/copy.md"; git -C "$R" add copy.md; git -C "$R" commit -qm two
printf 'x\n' > "$R/other.md"; git -C "$R" add other.md; git -C "$R" commit -qm three
printf 'Marigold\0binary\n' > "$R/blob.bin"; git -C "$R" add blob.bin; git -C "$R" commit -qm bin
printf 'note\n' > "$R/n.md"; git -C "$R" add n.md; git -C "$R" commit -qm "Ask zarnok-tide first"
printf 'y\n' > "$R/y.md"; git -C "$R" add y.md; GIT_AUTHOR_NAME="Quillon Varga" git -C "$R" commit -qm "Add y"
printf 'Deploy zarnok-tide tonight.\n' >> "$R/y.md"   # in the working copy only
(cd "$R" && "$GS" history) 2> "$TMP/h.err" >/dev/null; rc=$?
[ "$rc" = 1 ] && ok "history exits 1 on findings" || no "history exits 1" "exit $rc"
/usr/bin/grep -q 'notes/old plan.md@[0-9a-f]\{8\}:1  \[real value\]  Varga' "$TMP/h.err" && ok "a value in a blob later deleted is found by history" || no "a deleted blob's value" "$(cat "$TMP/h.err")"
(cd "$R" && "$GS" tree) 2>&1 | /usr/bin/grep -q 'old plan' && no "the deleted blob is not found by tree" "found" || ok "the deleted blob is not found by tree"
/usr/bin/grep -q 'tonight' "$TMP/h.err" && no "a working-copy-only value is found by neither" "found by history" || ok "a working-copy-only value is found by neither"
n=$(/usr/bin/grep -c '\[real value\]  trellisfold' "$TMP/h.err")
[ "$n" = 1 ] && ok "C6.1: a blob in three commits and two paths is read once" || no "C6.1: a blob is read once" "$n findings"
/usr/bin/grep -q 'blob.bin' "$TMP/h.err" && no "a binary blob is skipped" "found" || ok "a binary blob is skipped"
/usr/bin/grep -q 'commit [0-9a-f]\{8\}:1  \[real value\]  zarnok-tide' "$TMP/h.err" && ok "a value in a commit message is found" || no "a message value" "$(cat "$TMP/h.err")"
/usr/bin/grep -q 'commit [0-9a-f]\{8\} author  \[real value\]  Quillon Varga' "$TMP/h.err" && ok "a value in an author name is found" || no "an author value" "$(cat "$TMP/h.err")"
R=$TMP/h2; cfg=$(new_repo "$R" 'public=1'); printf 'wording=0\n' >> "$cfg/settings"
printf 'The parser reads one line.\nThe parser reads one line.\n' > "$R/a.md"; git -C "$R" add a.md; git -C "$R" commit -qm "Add a"
rm -f "$TMP/calls"; (cd "$R" && "$GS" history) >/dev/null 2>&1
[ ! -e "$TMP/calls" ] && ok "history does not sweep unless asked" || no "history does not sweep unless asked" "claude called"
(cd "$R" && "$GS" history --sweep) >/dev/null 2>&1; rc=$?
n=$(/usr/bin/grep -c 'The parser reads one line' "$TMP/last-prompt")
[ "$rc" = 0 ] && [ "$n" = 1 ] && ok "C6.5: history --sweep sends each distinct line once" || no "C6.5: each distinct line once" "exit $rc, $n copies"
