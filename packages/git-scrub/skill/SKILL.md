---
name: git-scrub
description: Keep forbidden values (names, ids, emails, client names, local paths), the user's own typed wording, and diary-style lines out of a repo's commits and pushes, and scrub them out of its history. Use when the user wants git-scrub turned on or off in a repo, wants to add values, patterns, labels or allowlist entries, asks why a commit or push was refused, wants a repo or its history audited, or wants history rewritten to remove values.
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - AskUserQuestion
---

# git-scrub

`git scrub` does the work; it is on `PATH` once installed. Do not reimplement its
checks by hand: a hand-run grep is not the same check, and misses what it misses.

## Where a repo's config is

`git scrub id` prints the repo's id (its root commit hash) and its config folder,
`~/.claude/skills/git-scrub/state/<id>/`. Every file there is optional:

| File | Holds |
|---|---|
| `settings` | `key=value` lines: `public=1`, `figures=1`, `wording=0/1`, `sweep=0`, `run_length=6`, `clause_floor=5`, `labels_off=name,name`, `prompt_logs=path,path`, and one `identity=Name <email>` line per allowed author |
| `values.txt` | literal values, one per line, flagged even when they are ordinary words |
| `patterns.ere` | extended regular expressions, matched case-insensitively |
| `sources.tsv` | `file<TAB>whole\|people\|always<TAB>jq expression`, for values held in JSON |
| `allow.txt` | values never flagged |
| `labels.tsv` | `name<TAB>sensitive\|insensitive<TAB>ERE`, the repo's own labels |
| `common.txt` | words never flagged on their own |
| `categories.md` | what the model sweep looks for, beyond the built-in public-repo ones |
| `message-lines.ere` | whole commit-message lines that are forbidden, and deleted by `rewrite` |
| `map.tsv`, `drop-paths.txt` | for `rewrite`: `value<TAB>placeholder`, and paths to remove |

These files hold the values themselves. Never copy one into a tracked file, a commit
message, or this conversation: check a value against them with a count, not a print.

## Turning it on

1. `git scrub enable` in the repo. It installs `pre-commit`, `commit-msg`,
   `post-commit` and `pre-push`, chained to the repo's own hooks (in `.git/hooks` or
   `core.hooksPath`), and sets `scrub.id`.
2. If it says there is no config yet, every check refuses (exit 2) until there is.
   Ask the user which values, patterns and identities the repo must keep out, and
   whether it is public, then write the files above.
3. `git scrub history` to see what is already in the history.

`git scrub disable` puts the repo's hooks back exactly; the config is kept.

## A refused commit or push

The refusal names each line as `location  [category]  matched text`. Exit 1 is
findings; exit 2 is a check that could not run (no config, an unreadable prompt log, a
remote a shallow clone needs, a sweep batch the model could not answer).

- A value or label: reword the line, or, if the value is meant to be there, add it to
  `allow.txt` after the user says so.
- `wording` or `close to wording`: the line repeats the user's own typed words. Rewrite
  it in plain technical terms; do not quote the user.
- `sweep: ...`: the model found narrative, an attribution, a decodable placeholder or a
  category from `categories.md`. Rewrite the line to state the requirement or behaviour.
- `SWEEP_SKIP=1` skips the model sweep for one run, only when the user asks.

Never bypass a refusal with `--no-verify`: the push check catches it anyway, and a
bypassed commit is checked again in full at push.

## Auditing and rewriting

- `git scrub tree [COMMIT]` checks every tracked line at a commit (HEAD by default).
- `git scrub history [--sweep]` checks every blob, message and identity ever committed.
- `git scrub history --map` writes a starting `map.tsv` from the findings. Have the user
  choose each placeholder: one the text around it gives back hides nothing.
- `git scrub rewrite` rewrites the whole history in place after a bundle backup in
  `.git/scrub/`, then lists what only the user can do: force-push, re-clone, ask the host
  to purge, delete the bundle. It never pushes. Run it only when the user asks, on a
  clean tree.

## The part that is easy to get wrong

The write hook (`PostToolUse`) reports, straight after a tool call, a line just written
into an enabled public repo that breaks its rules, naming the file, line and rule but
never the text. The fix is to rewrite that line, not to repeat the matched words back
to find out what they were, and not to move them into a commit message, which is
checked too.
