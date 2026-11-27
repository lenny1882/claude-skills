# Undoes jq's @tsv on one string per line, from field skip+1 on (fields before it are
# copied as they are): \\ is a backslash, \t a tab, \r a carriage return, and \n
# becomes \036, as produced() writes newlines. jq 1.6's gsub takes time that grows
# much faster than the string, so produced() escapes with @tsv and this file decodes.
# Run in the C locale.
BEGIN { if (skip == "") skip = 0 }
{
  head = ""; s = $0
  for (f = 0; f < skip; f++) { i = index(s, "\t"); head = head substr(s, 1, i); s = substr(s, i + 1) }
  # Split at each backslash: an empty piece is an escaped backslash, followed by plain
  # text; any other piece starts with the escape's letter.
  n = split(s, p, "\\"); out = p[1]
  for (j = 2; j <= n; j++) {
    if (p[j] == "") { out = out "\\" p[++j]; continue }
    c = substr(p[j], 1, 1)
    out = out (c == "n" ? "\036" : c == "t" ? "\t" : c == "r" ? "\r" : c) substr(p[j], 2)
  }
  print head out
}
