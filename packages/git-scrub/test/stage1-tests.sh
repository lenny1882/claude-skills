# Stage 1 tests (E1, C1, E5, C7.5) over the planted-case set. Sourced by run-tests.sh,
# which sets REPO, TMP, HOME, CLAUDE_DIR and the ok/no counters.

GS="$REPO/skill/bin/git-scrub"
CASES="$REPO/test/cases"
STATE="$CLAUDE_DIR/skills/git-scrub/state"
git config --global user.name "Test" ; git config --global user.email "test@example.invalid"
git config --global init.defaultBranch main

# A test repo with one base commit and its config folder filled from test/cases/sources.
# $1: the repo's path; $2: settings lines.
new_repo() {
  local r=$1 id cfg
  rm -rf "$r"; git init -q "$r"; git -C "$r" symbolic-ref HEAD refs/heads/main
  mkdir -p "$r/base"; gawk -F'\t' '$1 == "BASE" { print $4 }' "$CASES/cases.tsv" > "$r/base/README.md"
  git -C "$r" add -A; git -C "$r" commit -qm base
  id=$(git -C "$r" rev-list --max-parents=0 HEAD); cfg=$STATE/$id
  rm -rf "$cfg"; mkdir -p "$cfg"; cp -r "$CASES/sources/." "$cfg/"
  sed -i "s#@EXPORT@#/data/exports/slack-archive#" "$cfg/build-inputs.json"
  printf '%s\n' "$2" > "$cfg/settings"
  echo "$cfg"
}

# Categories found per case id, from git-scrub's findings on stderr.
by_case() {
  gawk '/^  cases\// { split($1, a, "[/.]"); id = a[2]; match($0, /\[[^]]*\]/); c = substr($0, RSTART + 1, RLENGTH - 2)
         if (!((id SUBSEP c) in seen)) { seen[id SUBSEP c] = 1; got[id] = (id in got ? got[id] "," : "") c } }
       END { for (i in got) print i "\t" got[i] }'
}

same_set() { # a b: the same comma-separated categories, in any order
  [ "$(tr ',' '\n' <<< "$1" | sort | paste -sd,)" = "$(tr ',' '\n' <<< "$2" | sort | paste -sd,)" ]
}

stage1_rows() { # the file rows stage 1 alone decides
  gawk -F'\t' 'NR > 1 && $3 ~ /^cases\// && $2 !~ /^(C3|E3|E4)/ && $5 !~ /sweep|wording/' "$CASES/cases.tsv"
}

echo "stage 1 (E1, C1, E5) over the planted cases"
R=$TMP/r1
cfg=$(new_repo "$R" $'public=1\nfigures=1\nwording=0')
mkdir -p "$R/cases"
stage1_rows | gawk -F'\t' -v ex="/data/exports/slack-archive" -v r="$R" '{ t = $4; gsub(/@EXPORT@/, ex, t); print t > (r "/" $3) }'
git -C "$R" add cases
(cd "$R" && "$GS" staged) 2> "$TMP/staged.err" >/dev/null; rc=$?
[ "$rc" = 1 ] && ok "staged exits 1 on findings" || no "staged exits 1 on findings" "exit $rc"
by_case < "$TMP/staged.err" > "$TMP/got.tsv"
while IFS=$'\t' read -r id req where text expect checker note; do
  got=$(gawk -F'\t' -v i="$id" '$1 == i { print $2 }' "$TMP/got.tsv"); got=${got:-pass}
  same_set "$got" "$expect" && ok "$id ($req): $expect" || no "$id ($req): $expect" "got: $got"
done < <(stage1_rows)

for id in M1 M2 M3; do
  expect=$(gawk -F'\t' -v i="$id" '$1 == i { print $5 }' "$CASES/cases.tsv")
  text=$(gawk -F'\t' -v i="$id" '$1 == i { print $4 }' "$CASES/cases.tsv")
  printf '%s\n' "$text" > "$TMP/msg"
  got=$(cd "$R" && "$GS" message "$TMP/msg" 2>&1 >/dev/null | gawk 'match($0, /\[[^]]*\]/) { print substr($0, RSTART + 1, RLENGTH - 2) }' | sort -u | paste -sd,)
  got=${got:-pass}
  same_set "$got" "$expect" && ok "$id: $expect" || no "$id: $expect" "got: $got"
done

echo "stage 1 scenarios"
printf '%s\n' "Ask JOSÉ FERREIRA today." > "$R/cases/B8.md"; git -C "$R" add cases/B8.md
got=$(cd "$R" && env -i PATH="$PATH" HOME="$HOME" TMPDIR="${TMPDIR:-/tmp}" CLAUDE_DIR="$CLAUDE_DIR" "$GS" staged 2>&1 | /usr/bin/grep -c 'B8.md:1  \[real value\]  JOSÉ FERREIRA')
[ "$got" = 1 ] && ok "B8 (C1.6): JOSÉ FERREIRA found under env -i" || no "B8 (C1.6): JOSÉ FERREIRA found under env -i" "matches: $got"
git -C "$R" rm -q --cached cases/B8.md

printf '%s\n' $'public=0\nfigures=1' > "$cfg/settings"
got=$(cd "$R" && "$GS" staged 2>&1 | by_case | gawk -F'\t' '$1 ~ /^L1[456]$/' | wc -l)
[ "$got" = 0 ] && ok "L17 (C4.4): the three public labels pass in a repo not marked public" || no "L17 (C4.4): public labels off" "$got of L14-L16 still found"
printf '%s\n' $'public=0\nfigures=0' > "$cfg/settings"
got=$(cd "$R" && "$GS" staged 2>&1 | by_case | gawk -F'\t' '$1 ~ /^N[14]$/' | wc -l)
[ "$got" = 0 ] && ok "E5: figures are opt-in" || no "E5: figures are opt-in" "$got of N1, N4 found with figures=0"

echo "E1 acceptance: commits through the hooks"
R=$TMP/r2
cfg=$(new_repo "$R" $'public=1\nfigures=1\nwording=0')
out=$(cd "$R" && "$GS" enable 2>&1); rc=$?
[ "$rc" = 0 ] && ok "enable" || no "enable" "exit $rc: $out"
head0=$(git -C "$R" rev-parse HEAD)
try_commit() { # file line message -> exit code of git commit
  printf '%s\n' "$2" > "$R/$1"; git -C "$R" add "$1"
  (cd "$R" && git commit -qm "$3") > "$TMP/commit.out" 2>&1
}
try_commit notes.md "Quillon Varga reviewed it." "Add notes"; rc=$?
[ "$rc" != 0 ] && [ "$(git -C "$R" rev-parse HEAD)" = "$head0" ] \
  && ok "a commit adding a value is refused and makes no commit" || no "a commit adding a value is refused" "exit $rc"
/usr/bin/grep -q 'notes.md:1  \[real value\]  Quillon Varga' "$TMP/commit.out" \
  && ok "the refusal names the file, line, category and value" || no "the refusal names the location" "$(head -3 "$TMP/commit.out")"
try_commit notes.md "Deploy to corvane-east-prod at noon." "Add notes"; rc=$?
[ "$rc" != 0 ] && ok "a commit adding a pattern match is refused" || no "a commit adding a pattern match is refused" "exit $rc"
try_commit notes.md "Raise it at corvane.atlassian.net today." "Add notes"; rc=$?
[ "$rc" != 0 ] && ok "a commit adding a built-in label is refused" || no "a commit adding a built-in label is refused" "exit $rc"
try_commit notes.md "A clean line." "Add Quillon Varga to reviewers"; rc=$?
[ "$rc" != 0 ] && [ "$(git -C "$R" rev-parse HEAD)" = "$head0" ] \
  && ok "a commit whose message holds a value is refused" || no "a commit whose message holds a value is refused" "exit $rc"
try_commit notes.md "Join zephlin-core for updates." "Add notes"; rc=$?
[ "$rc" = 0 ] && ok "the same commit with the allowlisted value is made" || no "the allowlisted commit is made" "exit $rc: $(cat "$TMP/commit.out")"
try_commit clean.md "The parser reads one line at a time." "Add the parser note"; rc=$?
[ "$rc" = 0 ] && [ ! -s "$TMP/commit.out" ] && ok "a clean commit is made with no output" || no "a clean commit is made with no output" "exit $rc: $(cat "$TMP/commit.out")"
n=$(tail -1 "$cfg/log" | /usr/bin/grep -c ': 1 line(s), 0 finding(s)$')
[ "$n" = 1 ] && ok "the clean commit wrote one log line" || no "the clean commit wrote one log line" "$(tail -2 "$cfg/log")"
/usr/bin/grep -q -i -E 'varga|zephlin|corvane' "$cfg/log" && no "the log holds no matched value (E9)" "a value is in $cfg/log" || ok "the log holds no matched value (E9)"

echo "C8.4: no config fails closed"
R=$TMP/r3; rm -rf "$R"; git init -q "$R"; printf 'x\n' > "$R/a"; git -C "$R" add a; git -C "$R" commit -qm a
(cd "$R" && "$GS" staged) >/dev/null 2>"$TMP/nocfg.err"; rc=$?
[ "$rc" = 2 ] && /usr/bin/grep -q 'no config found' "$TMP/nocfg.err" && ok "a repo with no config exits 2 and says why" || no "no config exits 2" "exit $rc: $(cat "$TMP/nocfg.err")"
