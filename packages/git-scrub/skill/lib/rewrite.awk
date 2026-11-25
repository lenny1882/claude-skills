# E7, C7.1: rewrites a `git fast-export` stream for `git fast-import`. Run with LC_ALL=C,
# so lengths are bytes.
#
# Variables, each a file:
#   map      value<TAB>placeholder, one per line (C7.2)
#   msgre    message-line EREs; matching lines are deleted from messages (C7.5)
#   drop     paths to drop, one per line; a path ending in / drops a directory
#   ident    "Name <email>" every author and committer becomes; empty keeps them
# Values are replaced case-insensitively where no ASCII letter or digit is either side,
# longest first, in blobs, messages and identities. A binary blob (a NUL in it) is passed
# through unchanged.

BEGIN {
  while ((getline l < map) > 0) {
    if (l ~ /^#/ || l == "") continue
    t = index(l, "\t"); if (!t) continue
    v = tolower(substr(l, 1, t - 1)); if (v == "") continue
    rep[v] = substr(l, t + 1); keys[++nk] = v
  }
  asort(keys, keys, "bylen")
  while ((getline l < msgre) > 0) if (l != "" && l !~ /^#/) mre[++nm] = l
  while ((getline l < drop) > 0) if (l != "" && l !~ /^#/) dp[++nd] = l
  if ((getline idline < ident) <= 0) idline = ""
  kind = ""
}

function bylen(i1, v1, i2, v2) { if (length(v1) != length(v2)) return length(v2) - length(v1); return v1 < v2 ? -1 : (v1 > v2) }
function alnum(c) { return c ~ /^[A-Za-z0-9]$/ }

function replace(s,   ls, i, v, L, p, k, st, best, n, c, out, pos) {
  if (!nk) return s
  ls = tolower(s); delete best
  for (i = 1; i <= nk; i++) {
    v = keys[i]; L = length(v); p = 1
    while ((k = index(substr(ls, p), v)) > 0) {
      st = p + k - 1
      if (!(st > 1 && alnum(substr(ls, st - 1, 1))) && !alnum(substr(ls, st + L, 1)) && !(st in best)) best[st] = v
      p = st + 1
    }
  }
  n = asorti(best, c, "@ind_num_asc"); out = ""; pos = 1
  for (i = 1; i <= n; i++) {
    st = c[i] + 0; if (st < pos) continue
    out = out substr(s, pos, st - pos) rep[best[st]]; pos = st + length(best[st])
  }
  return out substr(s, pos)
}

function dropped(path,   i) {
  if (path ~ /^".*"$/) path = substr(path, 2, length(path) - 2)
  for (i = 1; i <= nd; i++)
    if (path == dp[i] || (dp[i] ~ /\/$/ && index(path, dp[i]) == 1)) return 1
  return 0
}

# Message lines matching a C7.5 pattern are deleted, then any blank lines a deleted
# trailer leaves at the end; the rest is kept as it was, with values replaced.
function message(s,   n, L, i, j, keep, m, K, out) {
  n = split(s, L, "\n"); m = 0
  if (n && L[n] == "") n--
  for (i = 1; i <= n; i++) {
    keep = 1; for (j = 1; j <= nm; j++) if (L[i] ~ mre[j]) keep = 0
    if (keep) K[++m] = L[i]
  }
  while (m > 1 && K[m] == "") m--
  out = ""; for (i = 1; i <= m; i++) out = out K[i] "\n"
  return replace(out)
}

function emit(s) { printf "data %d\n%s", length(s), s }

# A data block: read exactly n bytes, which may end mid-line.
function readdata(n,   got, d, L, need, rest) {
  got = 0; d = ""; pending = ""
  if (n == 0) return ""
  while ((getline L) > 0) {
    need = n - got
    if (length(L) + 1 <= need) { d = d L "\n"; got += length(L) + 1; if (got == n) return d; continue }
    d = d substr(L, 1, need); rest = substr(L, need + 1)
    if (rest != "") pending = rest
    return d
  }
  return d
}

function handle(line,   n, d, w) {
  if (line ~ /^(blob|commit |tag |reset |feature |option |done$|progress )/) {
    kind = (line == "blob") ? "blob" : (line ~ /^commit / ? "commit" : (line ~ /^tag / ? "tag" : ""))
    print line; return
  }
  if (line ~ /^data [0-9]+$/) {
    n = substr(line, 6) + 0; d = readdata(n)
    if (kind == "blob") emit(index(d, "\0") ? d : replace(d))
    else if (kind == "commit" || kind == "tag") emit(message(d))
    else emit(d)
    if (pending != "") { w = pending; pending = ""; handle(w) }
    return
  }
  if (line ~ /^(author|committer|tagger) /) {
    match(line, /^[a-z]+ /); w = substr(line, 1, RLENGTH)
    if (idline != "" && w != "tagger ") { sub(/^[a-z]+ [^<]*<[^>]*> /, "", line); print w idline " " line; return }
    print replace(line); return
  }
  if (line ~ /^M [0-9]+ [^ ]+ /) { n = split(line, a, " "); w = substr(line, length(a[1] a[2] a[3]) + 4); if (!dropped(w)) print line; return }
  if (line ~ /^D /) { if (!dropped(substr(line, 3))) print line; return }
  print line
}

{ handle($0) }
