# E3, second pass (C3.2) for every prompt with no paraphrase key left, in one read of the
# matched transcript strings: the same test as lookup.awk's for a run or clause, each
# prompt's text being the strings from other sessions' files produced before it, in order.
#
# Files, in order:
#   1 jobs      pid<TAB>ms<TAB>kind<TAB>key, one line per key
#   2 own       pid<TAB>file, each prompt's own session files
#   3 strings   file<TAB>ms<TAB>string, as produced_tagged wrote them
# Output: pid<TAB>kind<TAB>key for each key the prompt's text holds.

BEGIN { FS = "\n" }
ARGIND == 1 {
  split($0, x, "\t"); p = x[1]
  if (!(p in pms)) { pms[p] = x[2]; order[++np] = p }
  nk[p]++; kind[p, nk[p]] = x[3]; key[p, nk[p]] = substr($0, length(x[1]) + length(x[2]) + length(x[3]) + 4)
  next
}
ARGIND == 2 { t = index($0, "\t"); own[substr($0, 1, t - 1), substr($0, t + 1)] = 1; next }
ARGIND == 3 {
  t = index($0, "\t"); f = substr($0, 1, t - 1); r = substr($0, t + 1)
  t = index(r, "\t"); ms = substr(r, 1, t - 1); s = tolower(substr(r, t + 1)); gsub(/[^a-z0-9']+/, " ", s)
  n++; file[n] = f; at[n] = ms + 0; text[n] = s
  next
}
END {
  for (o = 1; o <= np; o++) {
    p = order[o]; lim = pms[p] + 0; stream = ""
    for (i = 1; i <= n; i++) if (!((p, file[i]) in own) && at[i] < lim) stream = stream " " text[i]
    gsub(/ +/, " ", stream); stream = stream " "
    for (k = 1; k <= nk[p]; k++) if (index(stream, " " key[p, k] " ") > 0) print p "\t" kind[p, k] "\t" key[p, k]
  }
}
