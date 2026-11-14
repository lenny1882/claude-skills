# git-scrub — requirements

What `git-scrub` has to do. **Draft, 14 Nov 2026: not yet approved.** Numbers are never reused. An item that is overturned stays, marked with the date and
what replaced it.

Three tiers, in this order:

1. **Experience requirements** (E): what I see and do.
2. **Component requirements** (C): what each part must do so that an experience
   requirement holds, under the requirement it serves. C1.4 is the fourth component of E1.
3. **Pure component requirements** (P): things no experience requirement implies but the
   package still needs.

The definition of done is at the end. Open decisions that block an item are in
`BACKLOG.md` and cited by item number where they apply.

## Where this comes from

`git-scrub` replaces two checkers that exist today, and must do everything both do (E11):

- **The commit checker**: a Python script kept in one public repo's `.git/hooks/sanitise/`,
  run from `pre-commit` and `commit-msg`. Stage 1 is local: real values, 8-word runs and
  close paraphrases of my typed prompts, new activity figures and session-record labels.
  Stage 2 sends what passed stage 1 to `claude -p` with a list of categories. It also has
  `tree` and `history` audit modes.
- **The push checker**: a bash script in a private repo, run from `pre-push`. It checks
  the pushed tip's tree and every new commit's added lines and message against a list of
  extended regular expressions kept outside the repo, checks every new commit's author and
  committer, and has a subcommand that checks GitHub shows the repo as private.

Neither is named more closely here: this package is public, and so is this file.

Settled in the 14 Nov 2026 discussion: all bash, with git, gawk, jq and coreutils (P1);
literal values matched exactly as the commit checker matches them (C1.3); the four faults
found in the commit checker fixed, not copied (C4.2, C6.2, C6.3, C6.4); a package in
claude-skills named `git-scrub`.

---

## A. Stopping it going in

### E1. A commit holding a forbidden value is refused before it exists

I run `git commit` in a repo with git-scrub on. If an added line or the message holds a
value from that repo's forbidden list, the commit is not made, and I'm told the file, line,
category and value.
*Acceptance: in a test repo with a values list of three invented names, one ERE pattern and
one allowlist entry: a commit adding each name (in a file, and in the message), a line
matching the pattern, and each built-in label (C1.4) is refused, exit 1, with the location
and category printed; the same commit with the allowlisted value is made; a clean commit is
made with no output beyond one log line. No commit object is created for a refused commit.*

- **C1.1 Two hooks, one check.** `pre-commit` checks the staged diff's added lines with
  their new line numbers; `commit-msg` checks the message, skipping `#` lines. Both call the
  same `git scrub` subcommands (`staged`, `message FILE`), which can also be run by hand.
- **C1.2 Value sources come from per-repo config.** A repo's config names any number of
  sources, each one of:
  - a file of literal values, one per line (`#` and blank lines skipped);
  - a file of extended regular expressions, matched case-insensitively (the push checker's
    format, read unchanged);
  - a JSON file and a jq expression giving strings (how the commit checker reads its
    build-inputs file and a Slack export's `users.json`, `channels.json`, `groups.json`,
    `mpims.json` and `dms.json`), marked as either whole values or people's names.

  The commit checker's filtering rules are kept: values under 4 characters, over 80, or
  holding a newline are dropped; a single dictionary word (from `/usr/share/dict`) is not
  flagged on its own; a URL or path is dropped unless named; people's names are flagged
  whole and by each part of 5 characters or more that isn't a dictionary word or on the
  common-names list; a source can be marked "always", so its values are flagged even when
  they are words.
- **C1.3 Literal values match exactly as the commit checker matches them.** A value matches
  case-insensitively where the characters either side are not ASCII letters or digits.
  Where a longer value fails that test at a position, shorter values at the same position
  are still tried. *Acceptance: the differential test (D3) gives the same "real value"
  findings as the commit checker over the planted cases `foo-bar`, `foo_bar`, `xfoo`,
  `client.io`, an email-shaped value, and a value that is a prefix of a longer one.*
- **C1.4 Built-in labels.** Every repo gets these, case-sensitive as the commit checker has
  them: redaction labels (`[... removed]`), session ordinals ("sixth session"), `(R)`,
  Claude session links and ids, UUIDs, `/tmp/claude-<uid>` paths, email addresses, Slack
  ids, the Atlassian cloud domain. A repo's config can add labels and turn built-ins off.
  The commit checker's repo-only labels (a surname, a local export path) move to that
  repo's config.
- **C1.5 An allowlist per repo.** One value per line, case-insensitive; a listed value is
  never flagged by any stage-1 check.
- **C1.6 The locale is set by the script.** It sets `LC_ALL=C.UTF-8` itself, so a hook
  started from an IDE with no `LANG` matches accented names the same as a terminal does.
  *Acceptance: a value `José` is found in a line holding `JOSÉ` with `env -i` running the
  hook.*

### E2. A push is refused if anything it sends holds a forbidden value or the wrong identity

*Acceptance: the push checker's own two fail-first faults are refused: a commit on a
throwaway branch adding a line matching a pattern, and a commit there made with
`GIT_AUTHOR_EMAIL=someone@example.com`. A push of clean commits by the configured identity
goes through. A branch deletion is not checked.*

- **C2.1 What a push sends.** `pre-push` checks, for each ref: the tip's tree, and each new
  commit's added lines, message, author and committer. New commits are `<tip> --not
  <remote sha>`, or `<tip> --not --remotes` for a new branch. A deleted ref is skipped.
  `git scrub push [<tip> <rev-list args>]` runs the same by hand.
- **C2.2 Identity is per-repo config.** A repo can require one author and committer
  (name and email), or a list of allowed ones, or nothing.
- **C2.3 GitHub visibility check.** `git scrub private` asks the GitHub API anonymously for
  the repo's slug and passes only on 404. It runs only when asked; no hook calls it.

### E3. My own wording doesn't get committed

Opt-in per repo. A line that repeats 8 words in a row from something I typed to Claude, or
closely paraphrases a sentence I typed, is refused.
*Acceptance: with wording on and a test transcript directory: a line holding 8 consecutive
words of a typed prompt is refused as "wording"; a line sharing 4+ content words and 60%+ of
its content words with a typed sentence is refused as "close to wording"; the same 8 words
are not refused when Claude wrote them in an earlier transcript event; text inside
`<pasted_content>` and other tags is never treated as mine.*

- **C3.1 Transcripts.** The directories are the Claude project directory for the repo's
  path (`~/.claude/projects/` plus the path with `/` replaced by `-`), plus any listed in
  config. Files are read in order of their first timestamp.
- **C3.2 What counts as mine.** User events only, not sidechains, not `isMeta`, not skill
  loads or command expansions, with `<pasted_content>` and other tag pairs removed (done in
  jq, which has the back-references and lazy matching this needs). Malformed lines are
  skipped.
- **C3.3 Paraphrase rule.** As the commit checker's: clauses split at sentence punctuation,
  newlines, ` - ` and `, but `; content words exclude the stop list and words under 3
  characters, with a trailing `s` dropped on words over 4; words common across the repo's
  own tracked text don't count.
- **C3.4 The cache.** Rebuilt when any input is newer than it. Kept under the repo's git
  directory, mode 0600. How shingles are stored: BACKLOG item 4.

### E4. A model sweep catches what patterns can't

Lines that pass stage 1 go to `claude -p` with the repo's categories file, and a finding
blocks like a stage-1 one.
*Acceptance: a line planted for each category in a test categories file is reported by the
sweep (run against the real `claude`, logged); a clean diff gets `CLEAN`; a forbidden value
planted in a stage-1 list never appears in the text sent to the model, checked by capturing
the prompt.*

- **C4.1 The call.** `claude -p` with no tools, no session persistence, strict MCP config,
  no setting sources, model `sonnet`, from `$TMPDIR`, 10-minute timeout, batches of 400
  lines. It gets the categories and my anonymised wording list (C3), never a stage-1 value.
- **C4.2 A batch that can't be checked blocks with exit 2.** Its line range is reported and
  the remaining batches still run. *Fixes the commit checker, which returns exit 1.*
- **C4.3 Skipping it.** `SWEEP_SKIP=1` skips stage 2 for one run and the log says so. A
  repo's config can turn the sweep off.

### E5. New activity figures are caught

Opt-in per repo. A number of 3+ digits, a comma-grouped number or a percentage, within 60
characters of an activity word (messages, commits, PRs, sessions and the rest of the commit
checker's list), not a year, and not already anywhere in the tracked text at HEAD, is
refused.
*Acceptance: "1,234 commits" is refused when HEAD doesn't hold `1,234`, and passes when it
does; "in 2025, 40 sessions" passes; "17% of messages" is refused.*

## B. Finding and removing what's already in

### E6. I can audit a whole repo

`git scrub tree [<commit>]` checks every line of every tracked file at a commit;
`git scrub history` checks every blob ever committed, every commit message, and every
author and committer.
*Acceptance: a value planted in a blob that was later deleted is found by `history` and not
by `tree`; a value only in an uncommitted working-copy change is found by neither.*

- **C6.1 History reads blobs once.** Each blob is read once through `git cat-file --batch`,
  however many paths and commits hold it.
- **C6.2 `tree` reads the commit, not the working copy.** *Fixes the commit checker.*
- **C6.3 Paths with spaces and unusual characters are read whole**, using `-z` output.
  *Fixes the commit checker, which splits paths on whitespace.*
- **C6.4 HEAD's text is read once per run.** *Fixes the commit checker, which reads it
  twice.*
- **C6.5 The sweep over history is optional**, and sends each distinct line once.

### E7. I can scrub history

`git scrub rewrite` replaces forbidden values through the whole history, rewrites
identities, and can drop paths, then proves the result is clean. It never pushes.
*Acceptance: in a test repo with values planted in three commits' blobs, one message and
one author: after `rewrite` with a map, `history` finds nothing; every replaced value reads
as its placeholder; the dropped path is in no commit; a `git bundle` of the old history
exists and restores it; a dirty working tree makes `rewrite` refuse before doing anything.*

- **C7.1 The method.** `git fast-export --all | gawk | git fast-import`, rewriting blob
  data, commit messages and identities in one pass. No Python, no Java.
- **C7.2 The replacement map.** One `value<TAB>placeholder` per line, kept with the repo's
  config. `git scrub history --map` writes a starting map from the findings, with
  placeholders numbered by category (`[name-01]`, `[repo-03]`).
- **C7.3 What it won't replace.** Wording, paraphrase and activity-figure findings have no
  placeholder; `rewrite` lists them by commit and path for a hand edit and refuses to call
  the history clean while any remain.
- **C7.4 Before and after.** It refuses on a dirty tree, writes a bundle backup first, and
  finishes by running `history`. Its last output lists what only I can do: force-push every
  rewritten ref, re-clone every other clone, and ask the host (GitHub Support; Bitbucket
  support) to purge cached views and old commits reachable by SHA.

## C. Using it everywhere

### E8. I can put it on any repo with one command

*Acceptance: `git scrub enable` in a repo that already has its own `pre-push` (in
`.git/hooks` or `core.hooksPath`) leaves that hook running as before, and git-scrub's
checks run too; `git scrub disable` puts the repo back as it was.* Hook point and install
model: BACKLOG items 1 and 2.

- **C8.1 Config lives outside every tree.** Nothing that holds a forbidden value is ever in
  a tracked file. Location: BACKLOG item 3.
- **C8.2 The skill.** Covers enabling and disabling, adding values, patterns, labels and
  allowlist entries, reading a block, running an audit, and the rewrite with its outward
  steps. It never runs a force-push or contacts a host.

### E9. A block tells me what and where

*Acceptance: every finding prints location, category and the matched value (stage 1) or
the model's description (stage 2); more than 200 findings print the first 200 and the
count; every run, clean or not, appends to the repo's log and writes
`/tmp/git-scrub-<subcommand>.log`, both mode 0600.*

### E10. It's fast enough to leave on

*Acceptance: with a warm cache, stage 1 on a 200-line staged diff finishes in under 2
seconds, and `tree` over a 2,000-file repo in under 30; the first cache build over 110 MB of
transcripts is timed and recorded. Numbers to be confirmed: BACKLOG item 5.*

### E11. Both existing checkers are replaced with nothing lost

*Acceptance: D3 passes; the public repo's `.git/hooks/sanitise/` and its two hook files are
replaced by git-scrub with its values, categories and allowlist moved to config; the private
repo's push checker becomes a wrapper calling `git scrub push` and `git scrub private` that
keeps its own log lines, check labels and `FAULT=` runs, and its fail-first runs still fail
the named checks.*

---

## Pure component requirements

- **P1 Tools.** bash, git, gawk, jq, coreutils, and GNU grep for ERE files only. No Python,
  ripgrep or ugrep. The tests run with `/usr/bin/grep` named explicitly, since Claude
  Code's Bash tool replaces `grep` with ugrep.
- **P2 Packaging.** Built with claude-package-kit, installed from its release tarball,
  `git-scrub` on `PATH` so `git scrub` works.
- **P3 Invented values only.** Every value, name, path and transcript in this package's
  tests and docs is invented. git-scrub is on in claude-skills itself from its first
  working version.
- **P4 Exit codes.** 0 clean, 1 findings, 2 a check could not run.

---

## Definition of done

**Draft, not yet approved.** The package is done when every item below holds.

- **D1 Where a pass counts.** Every acceptance criterion passes from `test/run-tests.sh` on
  this machine, with `HOME` redirected to a temp directory, except E4's sweep checks, which
  call the real `claude` and say so in their label.
- **D2 Seen failing first.** Each criterion's test has been seen to fail against a fault
  put in on purpose (a planted value, a broken matcher, a `FAULT=<name>` switch), and the
  check named for that fault is the one that fails. The fault and the failing output are
  recorded in `BACKLOG.md` beside the pass.
- **D3 Differential test against the commit checker.** Run on this machine only, reading the
  Python checker from its local path (it holds real values and is never copied into this
  repo). Both run over the planted-case set and over the public repo's full history and
  HEAD tree; findings match line for line, except the four listed fixes (C4.2, C6.2, C6.3,
  C6.4), each shown by a planted case where the outputs differ as intended.
- **D4 A failed check fails the run.** Every test subcommand ends with its pass and fail
  counts and exits 1 on any FAIL.
- **D5 Every run logs.** Every script and test subcommand writes
  `/tmp/<script>-<subcommand>.log` itself.
- **D6 Clean by its own check.** `git scrub history` over claude-skills finds nothing, and
  git-scrub is on there.
- **D7 In use.** Installed from a release tarball into
  `/mnt/sda/User/Programs/claude-tools/git-scrub`, on in both repos of E11 with the old
  checkers gone, with a row in `INVENTORY.md`.
- **D8 Documented.** README, SKILL.md and the claude-skills README row describe what
  shipped; every BACKLOG item is done or moved to a later version with a reason.
- **D9 Lint.** `shellcheck` passes on every script.
