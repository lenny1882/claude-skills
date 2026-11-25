# Stage 1 (E1, C1, E5, C7.5): values, labels, figures and message lines.
#
# Files, in order, each named on the command line (an empty file where unused):
#   1 values    kind<TAB>value, kind one of whole, people, always (C1.2)
#   2 dict      dictionary words, one per line
#   3 common    common words (built-in, then the repo's own), # lines skipped
#   4 allow     allowlist (C1.5), # lines skipped
#   5 labels    name<TAB>case<TAB>gawk ERE; case is sensitive or insensitive
#   6 msglines  message-line EREs (C7.5), used only when mode is message
#   7 head      every tracked line at HEAD, for figures (E5)
#   8 lines     where<TAB>text, the lines to check
# Variables: mode (staged, message, tree, history, identity, text, redact), figures (1 to check them).
# Output: where<TAB>category<TAB>matched text, one line per finding. In redact mode, each
# line's text instead, with every value and label match replaced by [removed] (C4.1).

BEGIN { FS = "\n" }

ARGIND == 1 { t = index($0, "\t"); rawkind[++nraw] = substr($0, 1, t - 1); rawval[nraw] = substr($0, t + 1); next }
ARGIND == 2 { dict[tolower($0)] = 1; next }
ARGIND == 3 { if ($0 !~ /^#/) { n = split(tolower($0), w, /[[:space:]]+/); for (i = 1; i <= n; i++) if (w[i] != "") common[w[i]] = 1 } next }
ARGIND == 4 { v = $0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", v); if (v != "" && v !~ /^#/) allow[tolower(v)] = 1; next }
ARGIND == 5 {
  if ($0 ~ /^#/ || $0 == "") next
  split($0, f, "\t"); lname[++nl] = f[1]; lcase[nl] = (f[2] == "insensitive")
  re = f[3]; for (i = 4; i in f; i++) re = re "\t" f[i]
  gsub(/\\b/, "\\y", re)                    # \b is a backspace in gawk; read it as a boundary
  lre[nl] = re; next
}
ARGIND == 6 { if ($0 != "" && $0 !~ /^#/) msgre[++nm] = $0; next }
ARGIND == 7 { head = head "\n" $0; next }
ARGIND == 8 {
  if (!built) build()
  t = index($0, "\t"); where = substr($0, 1, t - 1); text = substr($0, t + 1)
  if (mode == "redact") { print redact(text); next }
  check(where, text); next
}

END { if (!built) build() }

function usable(v,   lv) {
  gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
  lv = tolower(v)
  if (v == "" || length(v) < 4 || length(v) > 80) return ""
  if (lv in common) return ""
  if (v ~ /^(http|\/)/) return ""
  return v
}

function addval(v) { if (!(tolower(v) in allow)) vals[tolower(v)] = 1 }

function build(   i, v, k, n, parts, p, j, lv) {
  built = 1
  for (i = 1; i <= nraw; i++) {
    k = rawkind[i]; v = rawval[i]
    if (k == "always") {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", v)
      if (!(tolower(v) in common) && length(v) >= 3) addval(v)
      continue
    }
    v = usable(v); if (v == "") continue
    if (!(v ~ /^[A-Za-z]+$/ && (tolower(v) in dict))) addval(v)
    if (k == "people") {
      n = split(v, parts, /[[:space:]._-]+/)
      for (j = 1; j <= n; j++) {
        p = parts[j]; lv = tolower(p)
        if (length(p) >= 5 && !(lv in common) && !(lv in dict)) addval(p)
      }
    }
  }
  # Longest first, so a longer value is tried before a shorter one at the same place.
  n = 0; for (v in vals) order[++n] = v
  nv = asort(order, order, "bylen")
  activity = "(messages?|commits?|reactions?|repos?|repositories|conversations?|dms?|" \
    "channels?|prs?|pull requests?|issues?|notes?|sessions?|transcripts?|" \
    "prompts?|threads?|clones?|emoji|replies|members?|people|colleagues?)"
}

function bylen(i1, v1, i2, v2) {
  if (length(v1) != length(v2)) return length(v2) - length(v1)
  return v1 < v2 ? -1 : (v1 > v2)
}

function alnum(c) { return c ~ /^[A-Za-z0-9]$/ }
function wordc(c) { return c ~ /^[A-Za-z0-9_]$/ }

function out(where, cat, s) { printf "%s\t%s\t%s\n", where, cat, s }

function redact(text,   lt, i, v, L, p, k, s, e, cut, n, re, a, out, pos) {
  lt = tolower(text); delete cut
  for (i = 1; i <= nv; i++) {
    v = order[i]; L = length(v); p = 1
    while ((k = index(substr(lt, p), v)) > 0) {
      s = p + k - 1
      if (!(s > 1 && alnum(substr(lt, s - 1, 1))) && !alnum(substr(lt, s + L, 1))) for (e = s; e < s + L; e++) cut[e] = 1
      p = s + 1
    }
  }
  for (i = 1; i <= nl; i++) {
    re = lre[i]; IGNORECASE = lcase[i]; pos = 1
    while (pos <= length(text) && match(substr(text, pos), re)) {
      a = pos + RSTART - 1; for (e = a; e < a + RLENGTH; e++) cut[e] = 1
      pos = a + (RLENGTH > 0 ? RLENGTH : 1)
    }
    IGNORECASE = 0
  }
  out = ""; n = length(text)
  for (e = 1; e <= n; e++) {
    if (e in cut) { if (!((e - 1) in cut)) out = out "[removed]"; continue }
    out = out substr(text, e, 1)
  }
  return out
}

function check(where, text,   lt, i, v, p, k, s, best, pos, cands, a, L, m, re, sub_, ok, anchored, n, d, w0) {
  # Values (C1.3): case-insensitive, no ASCII letter or digit either side; where the
  # longest value fails at a position, shorter ones there are still tried.
  lt = tolower(text); delete best
  for (i = 1; i <= nv; i++) {
    v = order[i]; L = length(v); p = 1
    while ((k = index(substr(lt, p), v)) > 0) {
      s = p + k - 1
      if (!(s > 1 && alnum(substr(lt, s - 1, 1))) && !alnum(substr(lt, s + L, 1)) && !(s in best)) best[s] = L
      p = s + 1
    }
  }
  pos = 1; n = asorti(best, cands, "@ind_num_asc")
  for (i = 1; i <= n; i++) {
    s = cands[i] + 0
    if (s < pos) continue
    m = substr(text, s, best[s])
    if (!(tolower(m) in allow)) out(where, "real value", m)
    pos = s + best[s]
  }
  # Labels (C1.4): every match, as finditer gives them. Not on an identity line, which
  # always holds an email address.
  for (i = 1; i <= nl && mode != "identity"; i++) {
    re = lre[i]; IGNORECASE = lcase[i]; anchored = (re ~ /^\^/); pos = 1
    while (pos <= length(text) + 1) {
      sub_ = substr(text, pos)
      if (!match(sub_, re)) break
      a = pos + RSTART - 1; m = substr(text, a, RLENGTH)
      ok = 1
      if (re ~ /^\\y/ && a > 1 && wordc(substr(text, a - 1, 1)) && wordc(substr(text, a, 1))) ok = 0
      if (anchored && a > 1) ok = 0
      if (ok && lname[i] == "Slack id" && substr(m, 2) !~ /[0-9]/) ok = 0
      if (ok && !(tolower(m) in allow)) out(where, lname[i], m)
      if (anchored) break
      pos = ok ? a + (RLENGTH > 0 ? RLENGTH : 1) : a + 1
    }
    IGNORECASE = 0
  }
  # Message lines (C7.5).
  if (mode == "message")
    for (i = 1; i <= nm; i++) if (text ~ msgre[i]) out(where, "message line", text)
  # Figures (E5): 3+ digits, comma-grouped or a percentage, near an activity word, not a
  # year, not already at HEAD.
  if (figures && (mode == "staged" || mode == "message" || mode == "text")) {
    pos = 1
    while (match(substr(text, pos), /[0-9]+/)) {
      a = pos + RSTART - 1
      if (a > 1 && substr(text, a - 1, 1) ~ /[A-Za-z0-9_.]/) { pos = a + RLENGTH; continue }
      sub_ = substr(text, a); m = ""
      if (match(sub_, /^[0-9]{1,3}(,[0-9]{3})+/) && substr(sub_, RLENGTH + 1, 1) !~ /^[A-Za-z0-9_]$/) m = substr(sub_, 1, RLENGTH)
      else if (match(sub_, /^[0-9]{3,}/) && substr(sub_, RLENGTH + 1, 1) !~ /^[A-Za-z0-9_]$/) m = substr(sub_, 1, RLENGTH)
      else if (match(sub_, /^[0-9]+(\.[0-9]+)?%/) && substr(sub_, RLENGTH + 1, 1) !~ /^[A-Za-z0-9_]$/) m = substr(sub_, 1, RLENGTH)
      if (m == "") { match(sub_, /^[0-9]+/); pos = a + RLENGTH; continue }
      d = m; gsub(/[,%]/, "", d)
      k = (a - 60 > 1 ? a - 60 : 1); w0 = substr(text, k, a + length(m) + 59 - k + 1)
      IGNORECASE = 1; k = (w0 ~ activity); IGNORECASE = 0
      if (d !~ /^(19|20)[0-9][0-9]$/ && k && !index(head, m) && !(tolower(m) in allow)) out(where, "new activity figure", m)
      pos = a + length(m)
    }
  }
}
