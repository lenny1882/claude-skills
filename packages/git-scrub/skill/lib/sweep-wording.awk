# C4.1: the typed clauses a sweep batch is shown, so it can spot a reworded quote. Only
# clauses sharing 2+ content words with the batch, most shared first, at most 100, since
# every prompt ever typed would not fit in one call.
#
# Files, in order: 1 stop words; 2 the batch, where<TAB>text; 3 prompts,
# ms<TAB>session<TAB>text with newlines as \036.
# Output: one clause per line, unredacted; stage1.awk's redact mode then replaces values.

BEGIN { FS = "\n" }
ARGIND == 1 { if ($0 !~ /^#/) { n = split($0, x, /[[:space:]]+/); for (i = 1; i <= n; i++) if (x[i] != "") stop[x[i]] = 1 } next }
ARGIND == 2 { t = index($0, "\t"); n = split(content(substr($0, t + 1)), x, " "); for (i = 1; i <= n; i++) want[x[i]] = 1; next }
ARGIND == 3 {
  t = index($0, "\t"); r = substr($0, t + 1); t = index(r, "\t"); text = substr(r, t + 1)
  m = clauses(text, cl)
  for (k = 1; k <= m; k++) {
    c = cl[k]; gsub(/^[[:space:]]+|[[:space:]]+$/, "", c); if (c == "" || (c in seen)) continue
    n = split(content(c), x, " "); s = 0; for (i = 1; i <= n; i++) if (x[i] in want) s++
    if (s >= 2) { seen[c] = 1; score[c] = s }
  }
  next
}
END { n = asorti(score, order, "byscore"); for (i = 1; i <= n && i <= 100; i++) print order[i] }
function byscore(i1, v1, i2, v2) {
  if (score[i1] != score[i2]) return score[i2] - score[i1]
  return i1 < i2 ? -1 : (i1 > i2)
}
function clauses(text, out,   t) {
  t = text
  gsub(/`[^`]*`/, " ", t); gsub(/[^[:space:]\036]*\/[^[:space:]\036]*/, " ", t)
  gsub(/[.!?;:][[:space:]]+/, "&\037", t); gsub(/\036/, "\037", t)
  gsub(/[[:space:]]+-[[:space:]]+/, "\037", t); gsub(/,[[:space:]]+but[[:space:]]+/, "\037", t)
  return split(t, out, "\037")
}
function content(text,   w, n, i, x, seen2, out, m, s, t) {
  t = tolower(text); gsub(/[^a-z0-9']+/, " ", t); n = split(t, w, " "); m = 0
  for (i = 1; i <= n; i++) {
    x = w[i]
    if ((x in stop) || length(x) < 3 || x ~ /^[0-9]+$/) continue
    if (x ~ /s$/ && length(x) > 4) x = substr(x, 1, length(x) - 1)
    if (!(x in seen2)) { seen2[x] = 1; out[++m] = x }
  }
  if (!m) return ""
  asort(out); s = out[1]; for (i = 2; i <= m; i++) s = s " " out[i]
  return s
}
