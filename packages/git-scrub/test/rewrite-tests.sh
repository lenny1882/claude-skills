# Rewrite tests (E7, C7.1 to C7.5, and E8's after-a-rewrite case). Sourced by
# run-tests.sh after stage1-tests.sh, whose new_repo and paths it uses.

echo "rewrite (E7, C7.1 to C7.5)"
R=$TMP/rw1; cfg=$(new_repo "$R" $'public=0\nidentity=Scrub Owner <owner@example.invalid>')
printf '^Session-Trace:\n' > "$cfg/message-lines.ere"
printf 'secret/\n' > "$cfg/drop-paths.txt"
printf 'Ask Varga about it.\n' > "$R/a.md"; git -C "$R" add a.md; git -C "$R" commit -qm "Add a"
printf 'Deploy zarnok-tide tonight.\nkeep this line\n' > "$R/b.md"; git -C "$R" add b.md
git -C "$R" commit -qm $'Add b for vell_quor\n\nThe body stays.\n\nSession-Trace: a1b2c3'
mkdir -p "$R/secret"; printf 'plimset.io keys\n' > "$R/secret/k.md"; printf 'See plimset.io.\n' > "$R/c.md"
git -C "$R" add secret c.md; GIT_AUTHOR_NAME="Quillon Varga" git -C "$R" commit -qm $'Add c\n\nSession-Trace: d4e5f6'
(cd "$R" && "$GS" history --map) >/dev/null 2>"$TMP/map.err"
[ -s "$cfg/map.tsv" ] && /usr/bin/grep -q $'^zarnok-tide\t\\[name-' "$cfg/map.tsv" && ok "history --map writes a starting map with numbered placeholders" || no "history --map" "$(cat "$TMP/map.err")"
printf 'Quillon Varga\t<reviewer>\nVarga\t<reviewer>\nzarnok-tide\tclient_a\nvell_quor\tclient_b\nplimset.io\tclient-c.example\n' > "$cfg/map.tsv"
old=$(git -C "$R" rev-list --max-parents=0 HEAD)
SRC=$TMP/rw-remote.git; rm -rf "$SRC"; git init -q --bare "$SRC"; git -C "$R" remote add origin "$SRC"
printf 'dirty\n' >> "$R/a.md"
(cd "$R" && "$GS" rewrite) >/dev/null 2>"$TMP/rw.err"; rc=$?
[ "$rc" = 2 ] && [ "$(git -C "$R" rev-list --max-parents=0 HEAD)" = "$old" ] && ! ls "$R/.git/scrub/"rewrite-*.bundle >/dev/null 2>&1 \
  && ok "a dirty working tree makes rewrite refuse before doing anything" || no "a dirty tree refuses" "exit $rc"
git -C "$R" checkout -q a.md
(cd "$R" && "$GS" rewrite) >/dev/null 2>"$TMP/rw.err"; rc=$?
[ "$rc" = 0 ] && ok "rewrite ends with history finding nothing" || no "rewrite ends clean" "exit $rc: $(head -20 "$TMP/rw.err")"
new=$(git -C "$R" rev-list --max-parents=0 HEAD)
all=$(git -C "$R" log --all -p --format='%an <%ae>|%cn <%ce>|%B')
for v in Varga zarnok-tide vell_quor plimset.io; do
  /usr/bin/grep -q -F "$v" <<< "$all" && no "no trace of $v is left" "still there" || ok "no trace of $v is left"
done
/usr/bin/grep -q 'Ask <reviewer> about it.' <<< "$all" && /usr/bin/grep -q 'Deploy client_a tonight.' <<< "$all" && /usr/bin/grep -q 'Add b for client_b' <<< "$all" \
  && ok "every replaced value reads as its placeholder" || no "values read as placeholders" "$all"
msg=$(git -C "$R" log --all --format=%B)
/usr/bin/grep -q 'Session-Trace' <<< "$msg" && no "no message holds the trailer line" "still there" || ok "no message holds the trailer line"
[ "$(git -C "$R" log -1 --format=%B HEAD~1)" = $'Add b for client_b\n\nThe body stays.' ] && ok "the rest of each message is unchanged" || no "the rest of each message is unchanged" "$(git -C "$R" log -1 --format=%B HEAD~1 | od -c | head -3)"
[ -z "$(git -C "$R" log --all --format= --name-only | /usr/bin/grep '^secret/')" ] && ok "the dropped path is in no commit" || no "the dropped path is in no commit" "still there"
[ "$(git -C "$R" log --all --format='%an <%ae> %cn <%ce>' | sort -u)" = "Scrub Owner <owner@example.invalid> Scrub Owner <owner@example.invalid>" ] \
  && ok "every identity is rewritten to the configured one" || no "identities rewritten" "$(git -C "$R" log --all --format='%an <%ae>' | sort -u)"
b=$(ls "$R/.git/scrub/"rewrite-*.bundle 2>/dev/null | head -1)
[ -n "$b" ] && [ "$(stat -c %a "$b")" = 600 ] && ok "the bundle is in .git/scrub, mode 0600" || no "the bundle in .git/scrub" "$b"
git clone -q "$b" "$TMP/rw-restored" 2>/dev/null
[ "$(git -C "$TMP/rw-restored" rev-list --max-parents=0 HEAD)" = "$old" ] && /usr/bin/grep -q Varga "$TMP/rw-restored/a.md" \
  && ok "the bundle restores the old history" || no "the bundle restores the old history" "root $(git -C "$TMP/rw-restored" rev-list --max-parents=0 HEAD 2>&1)"
(cd "$R" && git push -q --no-verify origin main) >/dev/null 2>&1
[ -z "$(find "$SRC" -name '*.bundle')" ] && [ "$(git -C "$SRC" rev-list --all | wc -l)" = "$(git -C "$R" rev-list --all | wc -l)" ] \
  && ok "a push to a test remote does not send the bundle" || no "the bundle is not pushed" "$(find "$SRC" -name '*.bundle')"
[ "$new" != "$old" ] && [ -d "$STATE/$new" ] && [ ! -e "$STATE/$old" ] && [ "$(git -C "$R" config scrub.id)" = "$new" ] \
  && ok "E8: after a rewrite the config is at the new root hash and scrub.id follows" || no "the config follows the rewrite" "new $new"
/usr/bin/grep -q 'force-push every rewritten ref' "$TMP/rw.err" && /usr/bin/grep -q 'Delete .*bundle' "$TMP/rw.err" \
  && ok "the last output lists the outward steps, the bundle's deletion included" || no "outward steps listed" "$(tail -8 "$TMP/rw.err")"
R=$TMP/rw2; cfg=$(new_repo "$R" $'public=0\nwording=1'); printf 'x\tY\n' > "$cfg/map.tsv"
printf 'the harbour lamps flicker whenever the tide turns early in spring\n' > "$R/q.md"; git -C "$R" add q.md; git -C "$R" commit -qm q
(cd "$R" && "$GS" rewrite) >/dev/null 2>"$TMP/rw2.err"; rc=$?
[ "$rc" = 1 ] && /usr/bin/grep -q 'not clean yet' "$TMP/rw2.err" && /usr/bin/grep -q '\[wording\]' "$TMP/rw2.err" \
  && ok "C7.3: wording has no placeholder, is listed, and the history is not called clean" || no "C7.3: wording listed, not clean" "exit $rc: $(cat "$TMP/rw2.err")"
