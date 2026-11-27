#!/usr/bin/env bash
# Builds E3's measured-acceptance corpus into DIR, the same bytes every run:
#   DIR/history.jsonl                       200 invented typed prompts
#   DIR/projects/-work-corpus/s-c1.jsonl    their transcript, with tool output printed
#                                           before the prompts that paste it back
#   DIR/docs/doc-NN.md                      40 files of 50 lines, 2,000 lines in all
# The docs quote none of the prompts. Both share stock phrases of 4 to 6 words, some
# typed as a clause of their own, and tool output lines, so the false hits counted over
# them mean something.
# usage: make-corpus.sh DIR
set -euo pipefail
dir=${1:?usage: make-corpus.sh DIR}
mkdir -p "$dir/projects/-work-corpus" "$dir/docs"
LC_ALL=C gawk -v dir="$dir" '
BEGIN {
  srand(20261125)
  nw = split("harbour ledger quay barrel lantern rope crane tide gate ferry depot " \
    "porter signal manifest crate pier berth anchor timber cargo winch hull dock " \
    "schedule route ticket platform carriage engine boiler valve gauge pump filter " \
    "parser report config branch build cache script module table field record", N, " ")
  nv = split("checks loads moves lists opens closes counts writes reads keeps sends " \
    "holds marks skips sorts tracks", V, " ")
  na = split("north east old new spare main second quiet late early heavy short", A, " ")
  ns = split("at the end of the day|on the other hand|as a matter of fact|in the " \
    "middle of the night|for the time being|at the same time as|one of the main " \
    "reasons|in the long run|as far as we can tell|it goes without saying that", S, "|")
  nt = split("error: could not open file for reading|warning: config value is out " \
    "of range|build finished with 3 warnings and 0 errors|test suite passed in 4.2 " \
    "seconds|fatal: not a git repository|permission denied while writing the cache", T, "|")
  t0 = 1767603600000
  hist = dir "/history.jsonl"; tr = dir "/projects/-work-corpus/s-c1.jsonl"
  for (i = 1; i <= 200; i++) {
    p = sentence()
    if (i % 8 == 0) p = S[int(rand() * ns) + 1] ". " p      # a stock phrase as its own clause
    else if (i % 4 == 0) p = S[int(rand() * ns) + 1] " " p
    if (i % 5 == 0) {
      out = T[int(rand() * nt) + 1]
      event(tr, "assistant", i * 3, "[{\"type\":\"tool_use\",\"id\":\"tc" i "\",\"name\":\"Bash\",\"input\":{\"command\":\"make\"}}]")
      event(tr, "user", i * 3 + 1, "[{\"type\":\"tool_result\",\"tool_use_id\":\"tc" i "\",\"content\":\"" out "\"}]")
      p = p " and it printed " out
    }
    event(tr, "user", i * 3 + 2, "\"" p "\"")
    printf "{\"display\":\"%s\",\"pastedContents\":{},\"project\":\"/work/corpus\",\"sessionId\":\"s-c1\",\"timestamp\":%d}\n", p, t0 + (i * 3 + 2) * 1000 > hist
  }
  for (f = 1; f <= 40; f++) {
    doc = sprintf("%s/docs/doc-%02d.md", dir, f)
    for (l = 1; l <= 50; l++) {
      r = rand()
      if (r < 0.10) line = "    " T[int(rand() * nt) + 1]
      else if (r < 0.25) line = toupper(substr(x = S[int(rand() * ns) + 1], 1, 1)) substr(x, 2) ", the " sentence() "."
      else line = "The " sentence() "."
      print line > doc
    }
    close(doc)
  }
}
function sentence(   n, s, k) {
  n = 2 + int(rand() * 3); s = A[int(rand() * na) + 1] " " N[int(rand() * nw) + 1]
  for (k = 1; k < n; k++)
    s = s " " V[int(rand() * nv) + 1] " the " A[int(rand() * na) + 1] " " N[int(rand() * nw) + 1]
  return s
}
function event(file, type, sec, content) {
  printf "{\"type\":\"%s\",\"isSidechain\":false,\"sessionId\":\"s-c1\",\"timestamp\":\"%s\",\"message\":{\"role\":\"%s\",\"content\":%s}}\n", type, strftime("%Y-%m-%dT%H:%M:%S.000Z", (t0 / 1000) + sec, 1), type, content > file
}'
