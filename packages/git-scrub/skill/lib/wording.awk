# E3, first pass: lines that repeat my typed wording.
#
# Files, in order:
#   1 stop      stop words (C3.3), # lines skipped
#   2 prompts   ms<TAB>session<TAB>text, one typed prompt per line, oldest first;
#               newlines in the text are \036 (C3.1)
#   3 head      every tracked line at HEAD; words on many of its lines don't count (C3.3)
#   4 lines     where<TAB>text
# Variables: runlen (C3.6, default 6), floor (C3.5, default 5).
# Output, one line per candidate hit:
#   where<TAB>category<TAB>detail<TAB>kind<TAB>key<TAB>prompt number
# kind is run, clause or para; a para key is the content words the line shares with the
# typed sentence. lookup.awk then rules out keys Claude or a tool produced
# before that prompt (C3.2).

BEGIN { FS = "\n"; if (!runlen) runlen = 6; if (!floor) floor = 5 }

ARGIND == 2 {
  t = index($0, "\t"); rest = substr($0, t + 1); t2 = index(rest, "\t")
  np++; text = substr(rest, t2 + 1)
  n = words(text, w)
  for (i = 1; i + runlen - 1 <= n; i++) { r = join(w, i, runlen); if (!(r in runs)) runs[r] = np }
  m = clauses(text, cl)
  for (k = 1; k <= m; k++) {
    c = norm(cl[k]); if (c == "") continue
    nc = split(c, x, " ")
    if (nc >= floor && !(c in cls)) { cls[c] = np; clen[nc] = 1; cpre[join(x, 1, floor)] = 1 }
    s = content(cl[k]); if (s != "" && !(s in sentseen)) { sentseen[s] = 1; sraw[++ns] = s; spid[ns] = np }
  }
  next
}
ARGIND == 1 { if ($0 !~ /^#/) { n = split($0, x, /[[:space:]]+/); for (i = 1; i <= n; i++) if (x[i] != "") stop[x[i]] = 1 } next }
ARGIND == 3 { nh++; s = content($0); n = split(s, x, " "); for (i = 1; i <= n; i++) freq[x[i]]++; next }
ARGIND == 4 {
  if (!built) build()
  t = index($0, "\t"); where = substr($0, 1, t - 1); text = substr($0, t + 1)
  check(where, text); next
}

function build(   lim, k, n, x, i, s) {
  built = 1
  lim = int(nh / 300); if (lim < 5) lim = 5
  for (k in freq) if (freq[k] > lim) common[k] = 1
  for (k = 1; k <= ns; k++) {
    n = split(sraw[k], x, " "); s = ""; size[k] = 0
    for (i = 1; i <= n; i++) if (!(x[i] in common)) { set[k, x[i]] = 1; size[k]++ }
    if (size[k] >= 4) for (i = 1; i <= n; i++) if (!(x[i] in common)) idx[x[i]] = idx[x[i]] " " k
  }
}

function words(text, w,   t) { t = tolower(text); gsub(/[^a-z0-9']+/, " ", t); return split(t, w, " ") }
function join(w, i, n,   s, j) { s = w[i]; for (j = 1; j < n; j++) s = s " " w[i + j]; return s }
function norm(text,   w, n) { n = words(text, w); return n ? join(w, 1, n) : "" }

# The commit checker's clause split: code spans and paths removed, then split at
# sentence punctuation, newlines, " - " and ", but ".
function clauses(text, out,   t) {
  t = text
  gsub(/`[^`]*`/, " ", t); gsub(/[^[:space:]\036]*\/[^[:space:]\036]*/, " ", t)
  gsub(/[.!?;:][[:space:]]+/, "&\037", t); gsub(/\036/, "\037", t)
  gsub(/[[:space:]]+-[[:space:]]+/, "\037", t); gsub(/,[[:space:]]+but[[:space:]]+/, "\037", t)
  return split(t, out, "\037")
}

# Content words, sorted and space-joined: not a stop word, 3+ characters, not all
# digits, with a trailing s dropped on words over 4 characters.
function content(text,   w, n, i, x, seen, out, m, s) {
  n = words(text, w); m = 0; delete seen
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

function emit(where, cat, detail, kind, key, pid) { printf "%s\t%s\t%s\t%s\t%s\t%d\n", where, cat, detail, kind, key, pid }

function check(where, text,   w, n, i, r, len, c, m, cl, k, cw, x, nx, cnt, j, list, ids, shared, done, at, np2, q) {
  n = words(text, w); delete done
  for (i = 1; i + runlen - 1 <= n; i++) {
    r = join(w, i, runlen)
    if ((r in runs) && !(("run" r) in done)) { done["run" r] = 1; emit(where, "wording", r, "run", r, runs[r]) }
  }
  # A clause can start only where its first floor words do, and has a length some
  # clause has; the same order as trying every span.
  np2 = 0
  for (i = 1; i + floor - 1 <= n; i++) if (join(w, i, floor) in cpre) at[++np2] = i
  for (len = floor; np2 && len <= n && len <= 40; len++) {
    if (!(len in clen)) continue
    for (q = 1; q <= np2 && (i = at[q]) + len - 1 <= n; q++) {
      c = join(w, i, len)
      if ((c in cls) && !(("cl" c) in done)) { done["cl" c] = 1; emit(where, "wording", c, "clause", c, cls[c]) }
    }
  }
  m = clauses(text, cl)
  for (k = 1; k <= m; k++) {
    nx = split(content(cl[k]), x, " "); delete cw; cwn = 0
    for (i = 1; i <= nx; i++) if (!(x[i] in common)) { cw[x[i]] = 1; cwn++ }
    if (cwn < 4) continue
    delete cnt
    for (j in cw) { split(substr(idx[j], 2), ids, " "); for (i in ids) cnt[ids[i]]++ }
    for (i in cnt)
      if (cnt[i] >= 4 && cnt[i] >= 0.6 * cwn && !(("pa" i) in done)) {
        done["pa" i] = 1; delete sh; ns2 = 0
        for (j in cw) if ((i, j) in set) sh[++ns2] = j
        asort(sh); shared = sh[1]; for (j = 2; j <= ns2; j++) shared = shared " " sh[j]
        emit(where, "close to wording", shared, "para", shared, spid[i])
      }
  }
}
