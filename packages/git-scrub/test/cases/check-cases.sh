#!/usr/bin/env bash
# Checks the planted-case set is well formed and covers what BACKLOG item 6 asks for:
# the manifest's shape, each requirement and built-in label having a case, every
# fixture parsing, every JSON source's jq expression running, and the corpus being
# the same bytes on every build. Logs to ${TMPDIR:-/tmp}/check-cases.log.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log="${TMPDIR:-/tmp}/check-cases.log"
exec > >(tee "$log") 2>&1
pass=0; fail=0
ok(){ printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s\n    %s\n' "$1" "$2"; fail=$((fail+1)); }
m="$here/cases.tsv"

echo "manifest"
bad=$(gawk -F'\t' 'NF != 7 { print NR }' "$m" | paste -sd' ')
[ -z "$bad" ] && ok "every row has 7 fields" || no "every row has 7 fields" "lines: $bad"
[ "$(head -1 "$m")" = "$(printf 'id\treq\twhere\ttext\texpect\tchecker\tnote')" ] \
  && ok "header" || no "header" "$(head -1 "$m")"
dup=$(tail -n +2 "$m" | cut -f1 | sort | uniq -d | paste -sd' ')
[ -z "$dup" ] && ok "ids are unique" || no "ids are unique" "$dup"
dup=$(tail -n +2 "$m" | cut -f3 | /usr/bin/grep '^cases/' | sort | uniq -d | paste -sd' ')
[ -z "$dup" ] && ok "case files are unique" || no "case files are unique" "$dup"
empty=$(gawk -F'\t' 'NR > 1 && ($4 == "" || $5 == "" || $6 == "") { print $1 }' "$m" | paste -sd' ')
[ -z "$empty" ] && ok "text, expect and checker are filled" || no "text, expect and checker are filled" "$empty"

echo "coverage"
for r in C1.1 C1.2 C1.3 C1.4 C1.5 C1.6 C3.1 C3.2 C3.3 C3.5 C3.6 C4.2 C4.4 C6.2 C6.3 C6.4 C7.5 E1 E3 E4 E5; do
  gawk -F'\t' -v r="$r" 'NR > 1 { n = split($2, a, ","); for (i = 1; i <= n; i++) if (a[i] == r) f = 1 } END { exit !f }' "$m" \
    && ok "a case for $r" || no "a case for $r" "no row names it"
done
for l in "redaction label" "session ordinal" "(R) recommendation marker" "Claude session link or id" \
         "session or object uuid" "Claude scratch path" "Atlassian domain" "email address" "Slack id" \
         "the owner's name" "the owner's surname" "Slack export path" \
         "dated attribution" "answered-question log" "release history"; do
  gawk -F'\t' -v l="$l" 'NR > 1 { n = split($5, a, ","); for (i = 1; i <= n; i++) if (a[i] == l) f = 1 } END { exit !f }' "$m" \
    && ok "a case for the label: $l" || no "a case for the label: $l" "no row expects it"
done
for k in pass "close to wording" wording; do
  if gawk -F'\t' -v k="$k" 'NR > 1 && $2 ~ /^C3|^E3/ && index("," $5 ",", "," k ",") { f = 1 } END { exit !f }' "$m"; then
    ok "a wording case expecting: $k"
  else
    no "a wording case expecting: $k" "none"
  fi
done
n=$(gawk -F'\t' 'NR > 1 && $5 != $6 && $6 != "-" { c++ } END { print c + 0 }' "$m")
[ "$n" -ge 12 ] && ok "rows where the checkers differ as intended: $n" || no "rows where the checkers differ" "only $n"

echo "fixtures"
for f in "$here"/sources/*.json "$here"/sources/slack/*.json; do
  jq -e . "$f" >/dev/null 2>&1 && ok "parses: ${f#"$here"/}" || no "parses: ${f#"$here"/}" "jq failed"
done
while IFS= read -r f; do
  bad=$(jq -c . "$f" 2>&1 >/dev/null | head -1)
  [ -z "$bad" ] && ok "every line parses: ${f#"$here"/}" || no "every line parses: ${f#"$here"/}" "$bad"
done < <(find "$here/prompts" -name '*.jsonl' | sort)
while IFS=$'\t' read -r file kind expr; do
  out=$(jq -r "$expr" "$here/sources/$file" 2>&1) && [ -n "$out" ] || [ "$file" = slack/mpims.json ] \
    && ok "jq source runs: $file ($kind)" || no "jq source runs: $file ($kind)" "$out"
done < <(/usr/bin/grep -v '^#' "$here/sources/sources.tsv")
np=$(gawk -F'\t' 'NR > 1 && $2 ~ /^C3|^E3/ && $3 ~ /^cases\// && $5 ~ /wording/ { c++ } END { print c + 0 }' "$m")
nh=$(wc -l < "$here/prompts/history.jsonl")
[ "$nh" -ge 10 ] && ok "prompt log holds $nh prompts for $np wording cases" || no "prompt log" "$nh entries"
pasted=$(jq -r 'select(.pastedContents | length > 0) | .display' "$here/prompts/history.jsonl" | /usr/bin/grep -c '\[Pasted text #1')
[ "$pasted" -ge 1 ] && ok "a prompt with pasted text keeps it out of display" || no "pasted prompt" "none"
[ -n "$(find "$here/prompts/projects" -path '*/subagents/*.jsonl')" ] && ok "a subagent transcript" || no "a subagent transcript" "none"

echo "corpus"
t=$(mktemp -d); trap 'rm -rf "$t"' EXIT
if "$here/make-corpus.sh" "$t/a" && "$here/make-corpus.sh" "$t/b"; then
  diff -r -q "$t/a" "$t/b" >/dev/null && ok "the same bytes on every build" || no "the same bytes on every build" "builds differ"
  n=$(wc -l < "$t/a/history.jsonl"); [ "$n" = 200 ] && ok "200 prompts" || no "200 prompts" "$n"
  n=$(cat "$t/a"/docs/*.md | wc -l); [ "$n" = 2000 ] && ok "2,000 doc lines" || no "2,000 doc lines" "$n"
  jq -c . "$t/a/history.jsonl" "$t/a/projects/-work-corpus/s-c1.jsonl" >/dev/null 2>&1 \
    && ok "corpus JSON parses" || no "corpus JSON parses" "jq failed"
else
  no "corpus builds" "make-corpus.sh failed"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
