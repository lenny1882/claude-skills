#!/usr/bin/env bash
# E3's measured acceptance: false hits over the invented corpus (make-corpus.sh), whose
# 2,000 doc lines quote none of its 200 prompts, so every hit is a false one. Counts each
# rule on its own, at the lengths around its default. Logs to
# ${TMPDIR:-/tmp}/measure-e3.log.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GS="$here/../skill/bin/git-scrub"
exec > >(tee "${TMPDIR:-/tmp}/measure-e3.log") 2>&1
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
export HOME=$T/home CLAUDE_DIR=$T/claude GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME" "$CLAUDE_DIR"
"$here/cases/make-corpus.sh" "$T/corpus"
cp "$T/corpus/history.jsonl" "$CLAUDE_DIR/"; cp -r "$T/corpus/projects" "$CLAUDE_DIR/"
R=$T/repo; git init -q "$R"; printf 'corpus\n' > "$R/README.md"
cp -r "$T/corpus/docs" "$R/docs"   # tracked, as checked lines are, so C3.3's common words apply
git -C "$R" -c user.name=t -c user.email=t@example.invalid add -A
git -C "$R" -c user.name=t -c user.email=t@example.invalid commit -qm base
cfg=$CLAUDE_DIR/skills/git-scrub/state/$(git -C "$R" rev-list --max-parents=0 HEAD); mkdir -p "$cfg"
for f in "$R"/docs/*.md; do gawk -v f="docs/${f##*/}" '{ print f ":" NR "\t" $0 }' "$f"; done > "$T/lines"
echo "corpus: $(wc -l < "$CLAUDE_DIR/history.jsonl") prompts, $(wc -l < "$T/lines") doc lines"

measure() { # label settings
  printf '%s\n' "$2" > "$cfg/settings"
  local out
  out=$(cd "$R" && "$GS" text < "$T/lines" 2>&1)
  printf '%-30s %s\n' "$1" "$(tail -1 "$cfg/log" | sed 's/^[^ ]* text: //')"
  gawk 'match($0, /\]  .*/) { print substr($0, RSTART + 3) }' <<< "$out" | sort | uniq -c | sort -rn | head -4 | sed 's/^/      /'
}
off=$'wording=1\nclause_floor=99\nrun_length=99'
measure "runs of 5, clauses off"  $'wording=1\nclause_floor=99\nrun_length=5'
measure "runs of 6, clauses off"  $'wording=1\nclause_floor=99\nrun_length=6'
measure "runs of 8, clauses off"  $'wording=1\nclause_floor=99\nrun_length=8'
measure "clauses of 4+, runs off" $'wording=1\nclause_floor=4\nrun_length=99'
measure "clauses of 5+, runs off" $'wording=1\nclause_floor=5\nrun_length=99'
measure "clauses of 6+, runs off" $'wording=1\nclause_floor=6\nrun_length=99'
measure "paraphrase only"         "$off"
measure "defaults (6, 5, paraphrase)" $'wording=1'
