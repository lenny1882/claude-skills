---
name: compare
description: Compare things already given in the conversation — two drafts, options, files, versions or outputs — laid out side by side as level, hard-wrapped columns in a code fence with both sides verbatim, then name each difference. Use only when the user types /compare or /side-by-side.
disable-model-invocation: true
allowed-tools:
  - Bash
  - Read
  - Write
---

# compare — set things side by side and name the differences

The user typed `/compare` (or `/side-by-side`) to see how things already in
the conversation differ. Lay them out in columns and say what differs. Do not
ask whether to start.

## 1. Find what to compare

What the user named after the command: `/compare the two drafts`,
`/compare F3 F4`, `/compare install.sh with the template`. With nothing named,
it is the two most recent comparable things in the conversation — two drafts,
two versions of one message, an option and its alternative, a before and an
after. If that is not clear, say which two you took in the first line.

For a file, read the file as it is now; for a version from git, use
`git show <ref>:<path>`. For text in the conversation, copy it exactly as it
was given.

## 2. Write each side out verbatim

Write each side to its own file in the scratchpad directory (or `$TMPDIR`),
exactly as given: same words, same line breaks, nothing trimmed, nothing
tidied. The comparison is only as good as this copy. Never shorten a side to
make it fit; the script wraps it instead.

## 3. Lay them out with the script

```bash
python3 "$HOME/.claude/skills/compare/bin/side-by-side.py" LEFT RIGHT \
  --left-label "<name of left>" --right-label "<name of right>"
```

It prints 99 columns (48 + 3 + 48), with unchanged lines level with their
twins even when lines were added or removed above them. The gutter marks each
row: `|` same, `*` changed, `<` only on the left, `>` only on the right. Put
its output in a code fence, unchanged. Do not lay columns out by hand, and do
not use a markdown table: its cells wrap to different heights and the rows
stop being level.

**More than two.** Compare each against the first, one fence per pair, unless
the user named the pairs. Three columns at this width are too narrow to read.

**Too long to be useful.** For a long file, lay out only the hunks that differ,
each with a few unchanged lines around it, and say which lines each fence
covers. Do not lay out hundreds of unchanged lines.

## 4. Name each difference

After the fence, list every difference, one line each, in the order they
appear. Name what changed and what it changes: "Draft 2 adds the admin export
to what breaks", not "line 1 differs". Group whitespace-only and punctuation-
only differences into one line at the end.

Then stop. No verdict on which is better unless the user asked for one.

## The part that is easy to get wrong

- **Retyping a side from memory.** A side that was paraphrased, shortened or
  "cleaned up" on the way into the file shows differences that are not there
  and hides ones that are. Copy it.
- **Two blocks one after the other.** That is not side by side. Neither is a
  table. The columns come from the script.
- **A list of differences that restates the fence.** Each line says what the
  difference means, not just where it is.
