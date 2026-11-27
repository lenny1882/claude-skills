# Push, tree, hooks and config lookup tests (E2, E6's tree, E8, C2, C6.2, C6.3, C8.3, C8.6,
# C8.7). Sourced by run-tests.sh after stage1-tests.sh, whose new_repo and paths it uses.

settings_id=$'public=0\nidentity=Test <test@example.invalid>'

echo "push (E2, C2.1, C2.2, C8.6)"
SRC=$TMP/e8-remote.git; rm -rf "$SRC"; git init -q --bare "$SRC"
R=$TMP/e8a
cfg=$(new_repo "$R" "$settings_id")
git -C "$R" remote add origin "$SRC"
(cd "$R" && "$GS" enable) >/dev/null
(cd "$R" && git push -q origin main) > "$TMP/p.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "a push of clean commits by the configured identity goes through" || no "a clean push goes through" "exit $rc: $(cat "$TMP/p.out")"
printf 'The parser reads one line.\n' > "$R/ok.md"; git -C "$R" add ok.md; (cd "$R" && git commit -qm "Add a note")
c=$(git -C "$R" rev-parse HEAD)
/usr/bin/grep -q "^$c	" "$cfg/passed" && ok "a commit that passed its hooks is on the passed list" || no "passed list" "$(cat "$cfg/passed" 2>&1)"
(cd "$R" && "$GS" push "$c" --not origin/main) 2>/dev/null; n1=$(tail -1 "$cfg/log" | gawk '{ print $3 }')
[ "$n1" = 0 ] && ok "a push of a commit that passed its hooks reads no lines, not the pushed tree (C2.1)" || no "a push reads no lines for a passed commit" "$n1 lines"
printf 'trellisfold\n' >> "$cfg/values.txt"
(cd "$R" && "$GS" push "$c" --not origin/main) 2>/dev/null; n2=$(tail -1 "$cfg/log" | gawk '{ print $3 }')
[ "$n2" -gt "$n1" ] && ok "after a value is added to the config, a passed commit is checked again ($n1 then $n2 lines)" \
  || no "a config change rechecks passed commits" "$n1 then $n2 lines"
(cd "$R" && git push -q origin main) >/dev/null 2>&1
git -C "$R" checkout -q -b throwaway
printf 'Deploy to corvane-east-prod at noon.\n' > "$R/bad.md"; git -C "$R" add bad.md; (cd "$R" && git commit -q --no-verify -m "Add bad")
(cd "$R" && git push -q origin throwaway) > "$TMP/p.out" 2>&1; rc=$?
[ "$rc" != 0 ] && /usr/bin/grep -q '\[pattern\]' "$TMP/p.out" && ok "a --no-verify commit adding a pattern match is refused at push" || no "a --no-verify pattern line is refused at push" "exit $rc: $(cat "$TMP/p.out")"
git -C "$R" reset -q --hard main
printf 'A clean line.\n' > "$R/c2.md"; git -C "$R" add c2.md
(cd "$R" && GIT_AUTHOR_EMAIL=someone@example.com git commit -q --no-verify -m "Add c2")
(cd "$R" && git push -q origin throwaway) > "$TMP/p.out" 2>&1; rc=$?
[ "$rc" != 0 ] && /usr/bin/grep -q '\[identity\]' "$TMP/p.out" && ok "a commit by the wrong author is refused at push" || no "wrong author refused at push" "exit $rc: $(cat "$TMP/p.out")"
git -C "$R" checkout -q main
(cd "$R" && git push -q --no-verify origin throwaway) >/dev/null 2>&1
(cd "$R" && git push -q origin :throwaway) > "$TMP/p.out" 2>&1; rc=$?
[ "$rc" = 0 ] && ok "a branch deletion is not checked" || no "a branch deletion is not checked" "exit $rc: $(cat "$TMP/p.out")"
git -C "$R" branch -q -D throwaway

echo "tree (C6.2, C6.3)"
printf 'Quillon Varga reviewed it.\n' >> "$R/ok.md"
(cd "$R" && "$GS" tree) > /dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && ok "X2 (C6.2): a value only in the working copy is not found by tree" || no "X2 (C6.2): tree reads the commit" "exit $rc"
git -C "$R" checkout -q ok.md
mkdir -p "$R/notes"; printf 'Ask Varga about it.\n' > "$R/notes/harbour plan.md"; git -C "$R" add notes; (cd "$R" && git commit -q --no-verify -m "Add plan")
(cd "$R" && "$GS" tree) 2> "$TMP/t.err" >/dev/null; rc=$?
[ "$rc" = 1 ] && /usr/bin/grep -q 'notes/harbour plan.md:1  \[real value\]  Varga' "$TMP/t.err" \
  && ok "X3 (C6.3): a value in a path with a space is found" || no "X3 (C6.3): a spaced path is read whole" "exit $rc: $(cat "$TMP/t.err")"
git -C "$R" reset -q --hard HEAD~1

echo "hooks chained (C8.7)"
R=$TMP/e8b; cfg=$(new_repo "$R" 'public=0')
export MARKS=$TMP/marks; mkdir -p "$MARKS"
printf '#!/bin/sh\necho ran >> "$MARKS/own-pre-commit"\n' > "$R/.git/hooks/pre-commit"; chmod 755 "$R/.git/hooks/pre-commit"
before=$(sha1sum < "$R/.git/hooks/pre-commit")
(cd "$R" && "$GS" enable) >/dev/null; rm -f "$MARKS/own-pre-commit"
printf 'x\n' > "$R/x.md"; git -C "$R" add x.md; (cd "$R" && git commit -qm x)
[ -s "$MARKS/own-pre-commit" ] && ok "the repo's own pre-commit still runs" || no "the repo's own pre-commit still runs" "no marker"
(cd "$R" && "$GS" disable) >/dev/null
[ "$(sha1sum < "$R/.git/hooks/pre-commit")" = "$before" ] && [ ! -e "$R/.git/hooks/pre-push" ] \
  && ok "disable puts .git/hooks back as it was" || no "disable restores .git/hooks" "$(ls "$R/.git/hooks")"
R=$TMP/e8c; cfg=$(new_repo "$R" 'public=0')
mkdir -p "$R/.githooks"
printf '#!/bin/sh\necho ran >> "$MARKS/own-pre-push"\n' > "$R/.githooks/pre-push"
printf '#!/bin/sh\necho ran >> "$MARKS/own-post-checkout"\n' > "$R/.githooks/post-checkout"
chmod 755 "$R/.githooks/"*; git -C "$R" add .githooks; git -C "$R" commit -qm hooks; git -C "$R" config core.hooksPath .githooks
git -C "$R" remote add origin "$SRC"
(cd "$R" && "$GS" enable) >/dev/null; rm -f "$MARKS/own-pre-push" "$MARKS/own-post-checkout"
(cd "$R" && git push -q origin main:hooks) >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ -s "$MARKS/own-pre-push" ] && ok "with core.hooksPath, the push check and the repo's own pre-push both run" || no "core.hooksPath pre-push chain" "exit $rc"
git -C "$R" checkout -q -b other
[ -s "$MARKS/own-post-checkout" ] && ok "the repo's other hooks in core.hooksPath still run" || no "other core.hooksPath hooks still run" "no marker"
printf 'Ask Varga.\n' > "$R/v.md"; git -C "$R" add v.md; (cd "$R" && git commit -qm v) >/dev/null 2>&1; rc=$?
[ "$rc" != 0 ] && ok "with core.hooksPath, a commit adding a value is refused" || no "core.hooksPath pre-commit" "exit $rc"
git -C "$R" reset -q; rm -f "$R/v.md"
(cd "$R" && "$GS" disable) >/dev/null
[ "$(git -C "$R" config core.hooksPath)" = .githooks ] && [ ! -d "$R/.git/scrub-hooks" ] && [ -z "$(git -C "$R" status --porcelain)" ] \
  && ok "disable puts core.hooksPath back and leaves the tracked hooks unchanged" || no "disable restores core.hooksPath" "$(git -C "$R" config core.hooksPath)"

echo "config lookup (E8, C8.3, C8.4)"
R=$TMP/e8d; cfg=$(new_repo "$R" 'public=0'); git -C "$R" config uploadpack.allowFilter true
want=$(basename "$cfg")
found() { (cd "$1" && "$GS" id 2>/dev/null) | cut -f1; }
C=$TMP/e8-full; rm -rf "$C"; git clone -q "$R" "$C"
[ "$(found "$C")" = "$want" ] && ok "a fresh full clone finds the config with no enable" || no "a fresh full clone finds the config" "$(found "$C")"
git -C "$C" config --unset scrub.id
git -C "$C" remote set-url origin "https://host.example/renamed/other.git"
[ "$(found "$C")" = "$want" ] && ok "after the remote URL, the repo's name and its host change" || no "after the remote URL changes" "$(found "$C")"
git -C "$C" config --unset scrub.id; git -C "$C" remote add second "git@host2.example:x/y.git"
[ "$(found "$C")" = "$want" ] && ok "with two remotes" || no "with two remotes" "$(found "$C")"
git -C "$C" config --unset scrub.id; git -C "$C" remote remove origin; git -C "$C" remote remove second
[ "$(found "$C")" = "$want" ] && ok "with no remote" || no "with no remote" "$(found "$C")"
git -C "$C" config --unset scrub.id; mv "$C" "$C-moved"
[ "$(found "$C-moved")" = "$want" ] && ok "after the checkout folder is moved" || no "after the checkout folder is moved" "$(found "$C-moved")"
printf 'second\n' > "$R/second.md"; git -C "$R" add second.md; git -C "$R" commit -qm second   # so a depth-1 tip is not the root
S=$TMP/e8-shallow; rm -rf "$S"; git clone -q --depth 1 "file://$R" "$S"
[ "$(found "$S")" = "$want" ] && ok "a shallow clone of depth 1 finds it through a commits-only clone" || no "a shallow clone finds the config" "$(found "$S")"
[ "$(git -C "$S" config scrub.id)" = "$want" ] && ok "the match is written to scrub.id" || no "the match is written to scrub.id" "$(git -C "$S" config scrub.id)"
S2=$TMP/e8-shallow2; rm -rf "$S2"; git clone -q --depth 1 "file://$R" "$S2"
git -C "$S2" remote set-url origin "file://$TMP/e8-gone"
(cd "$S2" && "$GS" staged) >/dev/null 2>"$TMP/s.err"; rc=$?
[ "$rc" = 2 ] && /usr/bin/grep -q 'could not clone' "$TMP/s.err" && ok "with the remote unreachable, a shallow clone's check exits 2 and says why" || no "unreachable remote exits 2" "exit $rc: $(cat "$TMP/s.err")"
git -C "$S2" remote set-url origin "file://$R"
(cd "$S2" && "$GS" staged) >/dev/null 2>"$TMP/s.err"; rc=$?
[ "$rc" = 0 ] && ok "and passes once the remote is reachable" || no "passes once reachable" "exit $rc: $(cat "$TMP/s.err")"
E=$TMP/e8-empty; rm -rf "$E"; git init -q "$E"
id=$(cd "$E" && "$GS" enable | gawk '{ print $NF; exit }')
case $id in new-*) ok "a repo with no commits gets a generated id at enable" ;; *) no "a generated id" "$id" ;; esac
mkdir -p "$STATE/$id"; printf 'public=0\n' > "$STATE/$id/settings"
printf 'first\n' > "$E/f.md"; git -C "$E" add f.md; (cd "$E" && git commit -qm first) >/dev/null 2>&1; rc=$?
root=$(git -C "$E" rev-list --max-parents=0 HEAD)
[ "$rc" = 0 ] && [ -d "$STATE/$root" ] && [ ! -e "$STATE/$id" ] && [ "$(git -C "$E" config scrub.id)" = "$root" ] \
  && ok "its first commit moves the config to the root hash" || no "first commit moves the config" "exit $rc, scrub.id $(git -C "$E" config scrub.id)"

echo "on PATH (P2)"
mkdir -p "$TMP/pathbin" "$CLAUDE_DIR/skills/git-scrub"
cp -r "$REPO/skill/lib" "$CLAUDE_DIR/skills/git-scrub/" 2>/dev/null; cp "$GS" "$TMP/pathbin/git-scrub"
got=$(cd "$TMP/e8d" && PATH="$TMP/pathbin:$PATH" git scrub id 2>&1 | cut -f1)
[ "$got" = "$want" ] && ok "git scrub works from a copy on PATH" || no "git scrub works from a copy on PATH" "$got"
