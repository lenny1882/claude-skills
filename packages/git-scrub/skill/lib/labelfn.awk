# Writes lmatch(i, s), which runs match(s, ...) with label i's ERE as a regex literal, so
# gawk compiles each label once per run rather than once per line it is tried on.
# Input: the labels file stage1.awk reads (name<TAB>case<TAB>gawk ERE), with the same
# skipping, numbering and \b reading. Output: gawk source for stage1.awk's second -f.

BEGIN { FS = "\n"; print "function lmatch(i, s) {" }

$0 ~ /^#/ || $0 == "" { next }

{
  split($0, f, "\t"); re = f[3]; for (i = 4; i in f; i++) re = re "\t" f[i]
  gsub(/\\b/, "\\y", re)
  # A / ends a regex literal; escape every one not already escaped.
  out = ""; esc = 0
  for (i = 1; i <= length(re); i++) {
    c = substr(re, i, 1)
    if (c == "/" && !esc) c = "\\/"
    esc = (substr(re, i, 1) == "\\" && !esc)
    out = out c
  }
  printf "  if (i == %d) return match(s, /%s/)\n", ++n, out
}

END { print "  return 0\n}" }
