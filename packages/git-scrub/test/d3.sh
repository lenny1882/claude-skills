#!/usr/bin/env bash
# D3: git-scrub against the commit checker, on this machine only.
#
#   test/d3.sh PUBLIC-REPO
#
# PUBLIC-REPO is the local clone holding the commit checker at
# .git/hooks/sanitise/check.py, its categories, allowlist and build inputs. They are read
# where they are and never copied into this repo. Both checkers run in temp clones, so
# nothing is written to PUBLIC-REPO. Compares locations and categories only, never
# values. Logs to ${TMPDIR:-/tmp}/d3.log; the full lists of differing locations go to
# ${TMPDIR:-/tmp}/d3-detail.tsv, mode 0600.
#
# Part 1, the planted set: every case row's categories from each checker against the
# manifest's expect and checker columns. Part 2, the public repo's HEAD tree and full
# history: findings that match, and those only one checker gives, by category; the new
# wording rules' and identity findings are listed apart.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUB=$(cd "${1:?usage: test/d3.sh PUBLIC-REPO}" && pwd)
HOOK=$PUB/.git/hooks/sanitise
[ -f "$HOOK/check.py" ] || { echo "no commit checker at $HOOK/check.py" >&2; exit 2; }
GS=$here/../skill/bin/git-scrub
CASES=$here/cases
umask 077
export LC_ALL=C   # sort and comm agree on order
log=${TMPDIR:-/tmp}/d3.log; detail=${TMPDIR:-/tmp}/d3-detail.tsv
exec > >(tee "$log") 2>&1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
: > "$detail"
pass=0; fail=0
ok(){ printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s\n    %s\n' "$1" "$2"; fail=$((fail+1)); }
norm() { sed -E 's/\tclose to [^\t]+ wording$/\tclose to wording/; /\tclose to wording$/!s/\t[^\t]+ wording$/\twording/'; }

echo "commit checker: check.py sha1 $(sha1sum < "$HOOK/check.py" | cut -c1-40), categories.md sha1 $(sha1sum < "$HOOK/categories.md" | cut -c1-40)"
echo "git-scrub: $(git -C "$here/.." log -1 --format=%h -- . 2>/dev/null)"

# A checker hook directory in a temp repo: the real script and categories by symlink,
# so the paths it derives from its own location point at the temp repo.
hookdir() { # REPO ALLOW
  mkdir -p "$1/.git/hooks/sanitise"
  ln -s "$HOOK/check.py" "$1/.git/hooks/sanitise/check.py"
  ln -s "$HOOK/categories.md" "$1/.git/hooks/sanitise/categories.md"
  cp "$2" "$1/.git/hooks/sanitise/allow.txt"
}
checker_log() { # REPO: where<TAB>category for every stage-1 finding in its log
  gawk '/^[0-9-]+ [0-9:]+ stage 1 / { sub(/^[0-9-]+ [0-9:]+ stage 1 /, ""); m = match($0, / \[[^]]*\] /); if (m) print substr($0, 1, RSTART - 1) "\t" substr($0, RSTART + 2, RLENGTH - 4) }' \
    "$1/.git/sanitise.log" 2>/dev/null | norm
}
set_of() { tr ',' '\n' <<< "$1" | sort -u | paste -sd,; }

echo
echo "part 1: the planted set"
(
  export HOME=$T/home; mkdir -p "$HOME"
  export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid
  export CLAUDE_DIR=$HOME/.claude GIT_SCRUB_STATE=$T/state SWEEP_SKIP=1
  P0=$(cd "$HOOK" && python3 -c 'import check; print(check.PROMPT_DIRS[0])')   # under the temp HOME
  mkdir -p "$P0" "$CLAUDE_DIR/projects"
  cp -r "$CASES/prompts/projects/-work-proj-a/." "$P0/"
  cp -r "$CASES/prompts/projects/." "$CLAUDE_DIR/projects/"
  cp "$CASES/prompts/history.jsonl" "$CLAUDE_DIR/history.jsonl"
  # The export folder is named relative to the repo, so its path holds no /tmp/claude-<uid>
  # for the scratch-path label to find (V12).
  R=$T/planted; git init -q "$R"; hookdir "$R" "$CASES/sources/allow.txt"
  mkdir -p "$R/slack-exports"; cp -r "$CASES/sources/slack/." "$R/slack-exports/"
  sed "s#@EXPORT@#slack-exports#" "$CASES/sources/build-inputs.json" > "$R/build-inputs.json"
  printf 'build-inputs.json\nslack-exports/\n' > "$R/.gitignore"; mkdir -p "$R/base" "$R/cases"
  gawk -F'\t' '$1 == "BASE" { print $4 }' "$CASES/cases.tsv" > "$R/base/README.md"
  git -C "$R" add -A; git -C "$R" commit -qm base
  cfg=$GIT_SCRUB_STATE/$(git -C "$R" rev-list --max-parents=0 HEAD); mkdir -p "$cfg"
  cp -r "$CASES/sources/." "$cfg/"; sed -i "s#@EXPORT@#slack-exports#" "$cfg/build-inputs.json"
  printf 'public=1\nfigures=1\nwording=1\n' > "$cfg/settings"
  (cd "$R" && gawk -F'\t' -v ex="slack-exports" 'NR > 1 && $3 ~ /^cases\// { t = $4; gsub(/@EXPORT@/, ex, t); print t > $3 }' "$CASES/cases.tsv")
  git -C "$R" add cases
  (cd "$R" && python3 .git/hooks/sanitise/check.py staged --no-model) >/dev/null 2>&1
  checker_log "$R" | gawk -F'\t' '$1 ~ /^cases\// { split($1, a, "[/.]"); print a[2] "\t" $2 }' | sort -u > "$T/p-checker"
  (cd "$R" && GIT_SCRUB_FINDINGS=$T/p-gs.raw "$GS" staged) >/dev/null 2>&1
  gawk -F'\t' '$1 ~ /^cases\// { split($1, a, "[/.]"); print a[2] "\t" $2 }' "$T/p-gs.raw" | sort -u > "$T/p-gs"
) || true
got() { gawk -F'\t' -v i="$2" '$1 == i { print $2 }' "$1" | paste -sd,; }
same=0; intended=0
while IFS=$'\t' read -r id req where text expect checker note; do
  [ "$checker" = - ] || [ "$expect" = sweep ] && continue
  g=$(set_of "$(got "$T/p-gs" "$id")"); c=$(set_of "$(got "$T/p-checker" "$id")")
  g=${g:-pass}; c=${c:-pass}
  if [ "$g" = "$(set_of "$expect")" ] && [ "$c" = "$(set_of "$checker")" ]; then
    if [ "$expect" = "$checker" ]; then same=$((same + 1)); else intended=$((intended + 1)); fi
  else
    no "$id ($req)" "git-scrub $g (expected $expect); commit checker $c (expected $checker)"
  fi
done < <(gawk -F'\t' 'NR > 1 && $3 ~ /^cases\//' "$CASES/cases.tsv")
ok "planted rows: $same give the same findings from both, $intended differ as the manifest says"

echo
echo "part 2: the public repo's HEAD tree and full history"
C=$T/pub-checker; G=$T/pub-gs
git clone -q --no-local "$PUB" "$C"; git clone -q --no-local "$PUB" "$G"
for r in "$C" "$G"; do git -C "$r" for-each-ref --format='%(refname:short)' refs/remotes/origin | /usr/bin/grep -v 'HEAD$' \
  | while read -r b; do git -C "$r" branch -q --track "${b#origin/}" "$b" 2>/dev/null; done; done
hookdir "$C" "$HOOK/allow.txt"; ln -s "$PUB/build-inputs.json" "$C/build-inputs.json"
export GIT_SCRUB_STATE=$T/state2 SWEEP_SKIP=1
cfg=$GIT_SCRUB_STATE/$(git -C "$G" rev-list --max-parents=0 HEAD | sort | head -1); mkdir -p "$cfg"
ex=$(jq -r '.slack_export // empty' "$PUB/build-inputs.json")
{
  printf '%s\twhole\t[paths(strings) as $p | select(all($p[]; type != "string" or ((startswith("_") | not) and (IN("note", "status", "kind", "audience") | not)))) | getpath($p)] | .[]\n' "$PUB/build-inputs.json"
  printf '%s\talways\t.anonymiser_additions_candidates.names[]?\n' "$PUB/build-inputs.json"
  printf '%s\talways\t.slack_export // empty\n' "$PUB/build-inputs.json"
  if [ -n "$ex" ] && [ -d "$ex" ]; then
    [ -f "$ex/users.json" ] && printf '%s\twhole\t.[].id // empty\n%s\tpeople\t.[] | (.name, .real_name, .profile.real_name, .profile.display_name, .profile.first_name, .profile.last_name) | strings\n' "$ex/users.json" "$ex/users.json"
    for f in channels groups mpims dms; do [ -f "$ex/$f.json" ] && printf '%s\twhole\t.[] | (.id, .name) | strings\n' "$ex/$f.json"; done
  fi
} > "$cfg/sources.tsv"
(cd "$HOOK" && python3 - <<'PY'
import check
own = {"the owner's surname", "the owner's name", "Slack export path"}
for p, n in check.LABELS:
    if n in own:
        print("%s\tsensitive\t%s" % (n, p))
PY
) > "$cfg/labels.tsv"
(cd "$HOOK" && python3 -c 'import check; print("\n".join(sorted(check.COMMON | check.KEEP)))') > "$cfg/common.txt"
cp "$HOOK/allow.txt" "$cfg/allow.txt"
printf 'public=1\nwording=1\n' > "$cfg/settings"
for mode in tree history; do
  rm -f "$C/.git/sanitise.log"
  (cd "$C" && python3 .git/hooks/sanitise/check.py "$mode" --no-model) >/dev/null 2>&1
  checker_log "$C" | sort -u > "$T/$mode-checker"
  (cd "$G" && GIT_SCRUB_FINDINGS=$T/$mode-gs.raw "$GS" "$mode") >/dev/null 2>&1
  sed -E 's/^[0-9a-f]{12} //' "$T/$mode-gs.raw" 2>/dev/null | sort -u > "$T/$mode-gs"
  apart='wording|identity'
  m=$(comm -12 "$T/$mode-checker" "$T/$mode-gs" | wc -l)
  oc=$(comm -23 "$T/$mode-checker" "$T/$mode-gs" | /usr/bin/grep -v -E "	($apart)" | wc -l)
  og=$(comm -13 "$T/$mode-checker" "$T/$mode-gs" | /usr/bin/grep -v -E "	(close to )?($apart)" | wc -l)
  echo "  $mode: $m findings from both; outside the new wording rules, $oc only from the commit checker and $og only from git-scrub"
  for side in checker gs; do
    comm -$([ $side = checker ] && echo 23 || echo 13) "$T/$mode-checker" "$T/$mode-gs" | cut -f2 | sort | uniq -c | sort -rn \
      | sed "s/^/      only $side: /"
  done
  { comm -23 "$T/$mode-checker" "$T/$mode-gs" | sed "s/^/$mode only-checker\t/"; comm -13 "$T/$mode-checker" "$T/$mode-gs" | sed "s/^/$mode only-git-scrub\t/"; } >> "$detail"
  [ "$oc" = 0 ] && [ "$og" = 0 ] && ok "$mode: the same findings outside the new wording rules" || no "$mode: findings differ outside the new wording rules" "see $detail"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
