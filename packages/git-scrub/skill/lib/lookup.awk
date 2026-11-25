# E3, second pass (C3.2): which candidate keys Claude, a tool or a subagent produced.
#
# Files, in order:
#   1 keys      kind<TAB>key, as wording.awk wrote them
#   2 stop      stop words, # lines skipped
#   3 produced  text Claude, its tools and subagents produced before the prompt, one
#               string per line, newlines as \036
# Output: kind<TAB>key for each key the produced text holds. A run or clause is held
# when its words appear in a row; a paraphrase is held when one produced clause holds
# every content word the line shares with the typed sentence.

BEGIN { FS = "\n" }
ARGIND == 1 { t = index($0, "\t"); kind[++nk] = substr($0, 1, t - 1); key[nk] = substr($0, t + 1); next }
ARGIND == 2 { if ($0 !~ /^#/) { n = split($0, x, /[[:space:]]+/); for (i = 1; i <= n; i++) if (x[i] != "") stop[x[i]] = 1 } next }
ARGIND == 3 {
  t = tolower($0); gsub(/[^a-z0-9']+/, " ", t); stream = stream " " t
  m = clauses($0, cl)
  for (k = 1; k <= m; k++) { s = content(cl[k]); if (s != "" && !(s in seen)) { seen[s] = 1; sent[++nsent] = " " s " " } }
  next
}
END {
  gsub(/ +/, " ", stream); stream = stream " "
  for (i = 1; i <= nk; i++)
    if (kind[i] == "para" ? holds(key[i]) : index(stream, " " key[i] " ") > 0) print kind[i] "\t" key[i]
}

function holds(key,   n, w, j, c, all) {
  n = split(key, w, " ")
  for (j = 1; j <= nsent; j++) {
    all = 1; for (c = 1; c <= n && all; c++) if (!index(sent[j], " " w[c] " ")) all = 0
    if (all) return 1
  }
  return 0
}

function clauses(text, out,   t) {
  t = text
  gsub(/`[^`]*`/, " ", t); gsub(/[^[:space:]\036]*\/[^[:space:]\036]*/, " ", t)
  gsub(/[.!?;:][[:space:]]+/, "&\037", t); gsub(/\036/, "\037", t)
  gsub(/[[:space:]]+-[[:space:]]+/, "\037", t); gsub(/,[[:space:]]+but[[:space:]]+/, "\037", t)
  return split(t, out, "\037")
}
function content(text,   w, n, i, x, seen, out, m, s, t) {
  t = tolower(text); gsub(/[^a-z0-9']+/, " ", t); n = split(t, w, " "); m = 0
  for (i = 1; i <= n; i++) {
    x = w[i]
    if ((x in stop) || length(x) < 3 || x ~ /^[0-9]+$/) continue
    if (x ~ /s$/ && length(x) > 4) x = substr(x, 1, length(x) - 1)
    if (!(x in seen)) { seen[x] = 1; out[++m] = x }
  }
  if (!m) return ""
  asort(out); s = out[1]; for (i = 2; i <= m; i++) s = s " " out[i]
  return s
}
