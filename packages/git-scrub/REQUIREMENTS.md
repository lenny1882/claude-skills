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
  ids, the Atlassian cloud domain. A repo's config can add labels, each case-sensitive or
  not, and turn built-ins off. The commit checker's repo-only labels (the owner's first
  name, matched case-sensitively so `/home/<user>` paths pass; a surname; a local export
  path) move to that repo's config. Three more labels are on only in a repo marked public
  (C4.4): a dated attribution (`(Name, 11 Nov 2026`, or `the owner` in place of the name),
  an answered-question log line (`Answered` at the start of a line, after an optional item
  number), and release history (`released as` or `released in` before a version).
  *Overturned 25 Nov 2026: a fourth, a quoted full sentence (`"[A-Z][^"]{10,}[.?!]"`). Over
  the two public repos' recent history it matched code strings, docstrings, installer
  messages and test fixtures almost every time, and found no quote that E3 missed. E3
  reading every project's typed prompts (C3.1) replaces it.*
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
  `git scrub push [<tip> <rev-list args>]` runs the same by hand. Figures (E5) are
  checked at commit only: at push, HEAD already holds the figures being pushed.
- **C2.2 Identity is per-repo config.** A repo can require one author and committer
  (name and email), or a list of allowed ones, or nothing.
- **C2.3 GitHub visibility check.** `git scrub private` asks the GitHub API anonymously for
  the repo's slug and passes only on 404. It runs only when asked; no hook calls it.

### E3. My own wording doesn't get committed

Opt-in per repo, and on by default in a repo marked public (C4.4), where its config can
still turn it off. A line that repeats 6 words in a row from something I typed to Claude,
holds the whole of a clause I typed of 5 words or more, or closely paraphrases a sentence I
typed, is refused, whether it is in quotes or not.
*Acceptance: with wording on, a test prompt log and a test transcript directory: a line holding 6 consecutive
words from the middle of a longer typed clause is refused as "wording", and one holding 5
such words is not; a line holding a whole typed clause of 6
words, unquoted, is refused as "wording", and one of 4 words is not; a line sharing 4+
content words and 60%+ of its content words with a typed sentence is refused as "close to
wording"; the same 6 words or clause are not refused when, earlier than my typing them,
Claude wrote them in its reply, wrote them in a tool call's input (a file it wrote, a
command it ran), a tool printed them, or a subagent wrote them; text in a
prompt's `pastedContents` is never treated as mine; a clause I typed in another
project's session is refused in this repo; in a repo marked public with no wording
setting, the 6-word clause is refused.
Measured: over an invented set of 200 typed prompts and an invented docs tree of 2,000
lines that quotes none of them, the false hits of the 6-word runs and of the 5-word clause
rule (C3.5) are counted, logged and recorded in BACKLOG.md beside the pass, with the run
length and the floor kept or changed on that count.*

- **C3.1 Where my wording comes from.** `~/.claude/history.jsonl`: the `display` field of
  each entry, which holds what I typed in every project, with pasted text kept apart in
  `pastedContents` and never read; the `[Pasted text #N]` markers left in `display` are
  removed. Claude Code never cleans this file, and one pass over it
  takes well under a second. Wording typed in one project's session is often quoted in
  another repo's docs, so every project's prompts count, not just this repo's. Any other
  prompt files listed in config are read the same way.
- **C3.2 What rules wording out.** A run or clause from C3.1 is not mine when it
  appeared, before the prompt's timestamp, in any of: Claude's reply text; a tool call's
  input (a file Claude wrote or edited, a command it ran); a tool's output; a subagent's
  transcript. The transcripts are read only for a line that has already hit at C3.1, and
  only for that run or clause, in this order, stopping at the first that rules it out:
  1. the transcript of the session the prompt was typed in (its `sessionId`), with that
     session's subagent transcripts;
  2. for what step 1 leaves, every other transcript under `~/.claude/projects/`, for
     text copied in from another session: one search for all the runs and clauses left,
     their words with punctuation or escaped newlines between them, and for each
     paraphrase left the lines holding every one of its words; only the lines found are
     read. The search runs in the C locale, as eight greps over an eighth of the files
     each, each into a file of its own so no line is split.

  A run or clause is held when its words appear in a row in that text. A paraphrase is
  held when one clause there holds every content word the line shares with my sentence,
  so a sentence of Claude's I typed back with a word added is not mine. *Differs from the
  commit checker, which rules a sentence out only when Claude wrote the same content words
  exactly.* Malformed lines are skipped. A line with no hit at C3.1 reads no transcript. Text I paste back from a doc Claude wrote,
  from an error message or from a command's output is therefore not my wording. Claude
  Code deletes transcripts after `cleanupPeriodDays`, so Claude text I paste back after its
  transcript is gone can be reported as mine.
- **C3.3 Paraphrase rule.** As the commit checker's: clauses split at sentence punctuation,
  newlines, ` - ` and `, but `; content words exclude the stop list and words under 3
  characters, with a trailing `s` dropped on words over 4; words common across the repo's
  own tracked text don't count. C3.5 uses the same clause split.
- **C3.4 No wording cache.** Each run reads its inputs afresh. git-scrub keeps no copy of
  my wording on disk.
- **C3.6 Run length.** A per-repo setting, 6 words by default. Below 6, a run matches
  ordinary phrasing far more often than it matches a quote: over the two public repos'
  recent commits, runs of 6 caught every quoted line that runs of 5, 4 or 3 caught, and each
  shorter length added only false hits. *Changed from the commit checker's 8, which missed
  a quote broken across a line and a 6-word question; D3 lists it as an intended
  difference.*
- **C3.5 Whole-clause rule.** Each typed clause of 5 words or more, lowercased, with
  punctuation removed and spaces collapsed, except a clause that is not mine under C3.2.
  A line is refused when, normalised the same way, it holds one of them
  as a whole run of words. The floor of 5 is a per-repo setting. *New: the commit checker
  has no such rule, so D3 lists it as an intended difference.*

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
  The wording list is the typed clauses sharing 2 or more content words with the batch,
  most shared first, at most 100, with every value and label match replaced by
  `[removed]`: every prompt ever typed would not fit in one call. It runs only when stage 1
  found nothing, on `staged`, `message` and `tree`, and at push on the new commits that are
  not on the passed list.
  The prompt also carries a fixed instruction, the same as the commit checker's: be strict
  about figures describing the owner's or the company's activity, internal tool or vendor
  names, and wording that reads like a quote or close paraphrase of the owner; in a repo
  marked public, also about any line that is narrative, history, attribution or commentary
  rather than a requirement, behaviour, usage or technical reason. It answers one
  `FINDING<TAB>location<TAB>category<TAB>description` line per finding, never quoting the
  line, or the single word `CLEAN`. The prompt goes to `claude` on stdin, never as an
  argument, which any process can read from `/proc`, and never in a file, which would leave
  the staged lines and my wording on disk.
- **C4.2 A batch that can't be checked blocks with exit 2.** Its line range is reported and
  the remaining batches still run. *Fixes the commit checker, which returns exit 1.*
- **C4.3 Skipping it.** `SWEEP_SKIP=1` skips stage 2 for one run and the log says so. A
  repo's config can turn the sweep off.
- **C4.4 Public-repo rules.** A repo's config can mark it public. That turns on E3 by
  default, C1.4's three public-repo labels at stage 1, the write hook (E12), the public part of C4.1's
  instruction, and a built-in set of categories for the sweep. The sweep is the backstop
  for what stage 1 can't tell apart from other text: a short quoted phrase of the owner's
  in lower case, and reported speech without quotes. The categories:
  - narrative and commentary: how or when something came about, release-by-release
    history, what happened in a run, stories told to justify a rule, opinions about the
    owner or the work, and dates whose only purpose is to say when something was decided;
  - attributions of any kind ("as asked", "I chose", "the owner chose", a name with a
    date), reported speech, question-by-question logs and their answers, and what was
    proposed, offered, rejected or refused and by whom;
  - a commit message that says what the commit did to the text instead of the behaviour
    it gives;
  - a placeholder that the text around it gives back: its length, its spelling, what kind
    of word it is or what else it is used as, or an ordinary word replaced so that the
    sentence decodes it.

  A repo's own categories file still adds to these.
  *Acceptance: with the repo marked public, a planted dated attribution, an `Answered`
  line and a `released as 1.2` line are each refused at stage 1, and a planted undated
  attribution, a planted run story, a planted placeholder whose sentence names what it
  hides, a short lower-case quoted phrase introduced as the owner's, and a line of reported
  speech without quotes are each reported by the sweep; with the repo not marked, none of
  the eight is refused.*

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

- **C6.0 Identities in history.** Each author and committer is checked against the values
  and, where the repo names any, its identities (C2.2), but not the labels, since every
  identity holds an email address.
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
identities, can drop paths, and can delete whole lines from commit messages, then proves
the result is clean. It never pushes.
*Acceptance: in a test repo with values planted in three commits' blobs, one message and
one author, and an invented session trailer in two messages: after `rewrite` with a map
and a message-line pattern, `history` finds nothing; every replaced value reads as its
placeholder; no message holds the trailer line, and the rest of each message is
unchanged; the dropped path is in no commit; a `git bundle` of the old history exists at
`.git/scrub/rewrite-<date>.bundle` and restores it, and a push to a test remote does not
send it; a dirty working tree makes `rewrite` refuse before doing anything.*

- **C7.1 The method.** `git fast-export --all | gawk | git fast-import`, rewriting blob
  data, commit messages and identities in one pass. No Python, no Java.
- **C7.2 The replacement map.** One `value<TAB>placeholder` per line, kept with the repo's
  config. The placeholder is any text, readable ones included (`<user>`, `client_a`).
  `git scrub history --map` writes a starting map from the findings, with placeholders
  numbered by category (`[name-01]`, `[repo-03]`), for me to edit before `rewrite`.
- **C7.2a What else it rewrites.** Every author and committer becomes the repo's first
  `identity` setting, where it has one. Each path in `drop-paths.txt` (a trailing `/`
  drops a directory) is removed from every commit. Values are replaced where no ASCII
  letter or digit is either side, longest first; the stream is read as bytes, so only
  ASCII letters match regardless of case. A binary blob is passed through unchanged.
- **C7.3 What it won't replace.** Wording, paraphrase and activity-figure findings have no
  placeholder; `rewrite` lists them by commit and path for a hand edit and refuses to call
  the history clean while any remain.
- **C7.4 Before and after.** It refuses on a dirty tree, writes a bundle backup first, and
  finishes by running `history`. The bundle goes in `.git/scrub/rewrite-<date>.bundle`,
  mode 0600: git never tracks or pushes a file there, and the old objects stay in
  `.git/objects` through the reflog anyway, so it holds nothing the clone doesn't already.
  Its last output lists what only I can do: force-push every rewritten ref, re-clone every
  other clone, ask the host (GitHub Support; Bitbucket support) to purge cached views and
  old commits reachable by SHA, and delete the bundle once the pushed refs are checked,
  since `git gc` never removes it.
- **C7.5 Message lines to delete.** A repo's config lists extended regular expressions
  for whole message lines, such as session trailers. `rewrite` deletes every matching line
  from every commit message, along with a blank line left trailing. The same patterns are
  forbidden in new commit messages (E1, E2).

## C. Using it everywhere

### E8. I can put it on any repo with one command

*Acceptance: `git scrub enable` in a repo that already has its own `pre-push` (in
`.git/hooks` or `core.hooksPath`) leaves that hook running as before, and git-scrub's
checks run too; `git scrub disable` puts the repo back as it was. With one repo's config
in place, each of these finds it with no command but `git scrub enable`, and with no
`enable` at all for a clone already enabled: a fresh full clone; the same clone after its
remote URL changes from SSH to HTTPS form, after the remote repo is renamed, and after it
moves to another host; a clone with no remote; a clone with two remotes; the checkout
folder moved or renamed; a shallow clone of depth 1 whose tip was made by an enabled
clone; a shallow clone of depth 1 whose tip was made in another repo copy and whose
remote URL is new to git-scrub; a repo after `git scrub rewrite`; a repo with no commits
that then gets its first one. With the remote unreachable, that last shallow clone's
checks refuse with exit 2 and the reason, and pass on the next run once it is reachable.
Uninstalling and reinstalling git-scrub loses no repo's config. A commit that passed at
commit time is not checked again at push while the repo's config is unchanged; a commit
made with `--no-verify` is checked at push; after a value is added to the config, every
commit the push sends is checked again.*

- **C8.1 Config lives outside every tree.** Nothing that holds a forbidden value is ever in
  a tracked file. Each repo's config is a folder at `~/.claude/skills/git-scrub/state/<id>/`,
  the claude-package-kit state path for a skill, which survives installs and upgrades.
  Its files, each optional: `settings` (`key=value` lines: `public`, `figures`,
  `labels_off`, `wording`, `run_length`, `clause_floor`, `prompt_logs`), `values.txt` (literal values, flagged even when they are words),
  `patterns.ere`, `sources.tsv` (`file<TAB>kind<TAB>jq expression`, kind `whole`, `people`
  or `always`, a relative file read from the folder), `allow.txt`, `labels.tsv`
  (`name<TAB>sensitive|insensitive<TAB>ERE`), `common.txt` (words never flagged on their
  own, added to the built-in list), `message-lines.ere`, `map.tsv` and `drop-paths.txt`
  (E7), `log` and `passed` (C8.6).
- **C8.3 A repo's id is its root commit hash.** The first of `git rev-list
  --max-parents=0 HEAD` in sorted order. It does not change with the remote URL, the
  repo's name, its host, the number of remotes, or the checkout's path. Each run looks the
  config up in this order, and the first match writes `scrub.id` into the clone's git
  config:
  1. `scrub.id` in the clone's git config;
  2. the root commit hash, in a full clone;
  3. in a shallow clone, the root commit hash read from a commits-only bare clone of its
     remote (`git clone --bare --filter=tree:0`) in a temporary directory, deleted after;
     the working clone stays shallow. This is the only time git-scrub fetches; it never
     writes to a remote.

  A repo with no commits gets a generated id at `enable`; its first commit moves
  the config folder to the root hash and updates `scrub.id`. `git scrub rewrite` moves the
  folder to the new root hash and updates `scrub.id`.
- **C8.4 No config found fails closed.** In an enabled repo where no step of C8.3 finds a
  config, or step 3 cannot reach the remote, every check refuses with exit 2 and names
  each step it tried and why it failed. It never passes with an empty list. The same goes
  for my wording: with E3 on, if `history.jsonl` or the transcript directory is missing,
  unreadable or empty, as when the encrypted directory holding them is locked, every check
  refuses with exit 2 and names the path.
- **C8.6 Checked at commit and at push.** `git scrub enable` installs `pre-commit`,
  `commit-msg`, `post-commit` and `pre-push`. Each config keeps a list of commits that
  passed `pre-commit` and `commit-msg`, with the hash of the config they passed under:
  each hook leaves a mark under the repo's git directory when it passes, and
  `post-commit` records the new commit only when both marks are for its tree and the
  current config. At push
  (C2.1) the tip's tree is always checked; a new commit is skipped only when it is on
  that list under the config's current hash. Commits made with `--no-verify`, by a rebase
  or a merge, or in a clone without the hooks, are not on it and are checked.
- **C8.7 Enabled per repo, chained to the repo's own hooks.** `git scrub enable` changes
  only the repo it runs in, never the global git config. Where the repo already has a
  hook of the same name, in `.git/hooks` or in its own `core.hooksPath` (a tracked
  `.githooks`, husky, GSD's hooks), git-scrub's hook runs it as well, with the same
  arguments and stdin, and fails if either fails. Where the repo sets `core.hooksPath`,
  `enable` installs into that directory's place without changing the tracked hooks: it
  points `core.hooksPath` at git-scrub's own hook directory for that repo, which calls
  the tracked hooks. `git scrub disable` restores the repo's previous `core.hooksPath`
  and hooks exactly.
- **C8.5 Uninstalling keeps the config.** git-scrub's uninstall refuses to remove `state/`
  while it holds any repo's config, unless given `--keep-state` or a confirmation typed at
  the prompt (the word `delete`; `--yes` does not count, and with no terminal the answer
  is no). It is the manifest's `pre_uninstall`, so it runs before anything is removed.
- **C8.2 The skill.** Covers enabling and disabling, adding values, patterns, labels and
  allowlist entries, reading a block, running an audit, and the rewrite with its outward
  steps. It never runs a force-push or contacts a host's support.

### E9. A block tells me what and where

*Acceptance: every finding prints location, category and the matched value (stage 1) or
the model's description (stage 2); more than 200 findings print the first 200 and the
count; every run, clean or not, appends to the repo's log and writes
`/tmp/git-scrub-<subcommand>.log`, both mode 0600; neither log holds a matched value, my
wording or the model's description, only each finding's location and category and the
run's counts, since the logs sit outside the encrypted directory that holds my session
text. The value and description go to the terminal only.*

### E10. It's fast enough to leave on

*Acceptance, with a 3 MB prompt log (about 11,000 prompts) and a 1 GB transcript
directory: stage 1 on a 200-line staged diff with no wording hit, reading every input
afresh, finishes in under 3 seconds; the same diff with hits, including C3.2's one lookup
pass for all of them, in under 5; the write hook (E12) in under 1 second per tool call;
`tree` over a 2,000-file repo in under 30. The paraphrase rule (C3.3) is timed on its own
and recorded.*

The 3-second budget for a diff with no hit is set by what every run reads afresh (C3.4,
C6.4): the prompt log and HEAD's text alone take about 1.3 s in a repo of 30,000 lines.

Measured for these figures: building 6-word runs and whole clauses from that prompt log
and checking 200 lines against them took 0.65 s, nearly all of it reading the log, so a
1-line change costs about the same as 200 lines.

Measured since, with an 11,470-line prompt log and 997 MB of transcripts in 510 files, on
a 200-line staged diff in a public repo whose HEAD holds about 30,000 text lines, the model
sweep skipped:
- no wording hit: 2.7 s. `wording.awk` takes 1.4 s of it in the C locale (1.9 s in
  `C.UTF-8`, with the same output; in a UTF-8 locale, 1.2 to 1.4 s indexing the prompts and 0.5 to
  0.6 s counting HEAD's words), so it grows with the repo; reading the prompt log 0.6 s; stage 1 0.4 s;
  `git grep` of HEAD's text 0.25 s. Stage 1 stays in `C.UTF-8`: in the C locale it no
  longer matches an accented value in another case (C1.6);
- one 6-word typed run quoted: 3.7 s; a 13-word typed sentence quoted: 4.2 s, both
  before `wording.awk` moved to the C locale. A true hit
  is never ruled out by its own session, so it always pays C3.2's step 2.

C3.2's step 2 search, one case-insensitive regex per run joined into one `grep -E`: in a UTF-8
locale (`en_GB.UTF-8`, and git-scrub's own `C.UTF-8` alike) it took 1.7 s for 1 pattern, 30 s for 5 and 292 s for 15; in the C
locale 0.5 s, 2.1 s and 3.3 s, and 3.6 s for 60, with the same matches. Reading only the
matching lines, from eight greps in parallel, took 0.8 s per prompt for runs of typed
prompts and 0.2 s per run of Claude's text, against 4.4 s and 1.3 s for reading every file
that held a match. Searching newest file first, oldest first or in random order, stopping
once every run is held, saved nothing over the parallel search: a true hit reads every
file in any order.

`tree` over a 2,000-file repo of 308,892 text lines (the tracked files of three public
repos, copied until there were 2,000), the model sweep skipped: 185 s with wording off
and 1,022 s with it on, against 30 s. Of stage 1's time, nearly all is the label check:
over those lines, stage 1 took 1.5 s with no labels, 3.2 s with one, 82.8 s with two and
250.9 s with the 12 built-in ones, because one `match()` call takes each label's regex as
a string in turn and gawk compiles a dynamic regex again whenever the string at a call
site changes. With each label as a regex literal of its own, it took 15.4 s and gave the
same 672 findings. Built that way (`labelfn.awk`), over the same repo rebuilt at 265,067
text lines: `tree` 15.2 s with wording off, against 168.6 s before, and 705 s with it on. With wording on, step 2 parsing its matched transcript lines once
took that to 481 s; escaping transcript strings with jq's `@tsv` rather than `gsub`, whose
time grows much faster than the string in jq 1.6, and `lookup.awk` building clauses only
for a paraphrase key, to 287 s, all with the same 877 findings. Rebuilt again at 308,572
text lines (669 findings), it took 265 s; trying a clause only where a typed clause's
first 5 words begin took `wording.awk` from 85 s to 22.5 s and `tree` to 216 s.

### E11. Both existing checkers are replaced with nothing lost

*Acceptance: D3 passes; the public repo's `.git/hooks/sanitise/` and its two hook files are
replaced by git-scrub with its values, categories and allowlist moved to config; the private
repo's push checker becomes a wrapper calling `git scrub push` and `git scrub private` that
keeps its own log lines, check labels and `FAULT=` runs, and its fail-first runs still fail
the named checks; the private repo's own scrub requirement still shows complete in its
status script, from a counted run of the wrapper and its two fail-first runs; the names
that repo keeps on purpose are in its allowlist, and `git scrub history` over it finds
nothing; the commit checker's `.git/sanitise-cache.json`, which holds typed sentences, and
`.git/sanitise.log` are deleted from the public repo's clone.*

### E12. Claude is told the moment it writes my words or a diary line into a public repo

In a repo where git-scrub is enabled and marked public, whatever tool Claude used to change
the working tree — `Write`, `Edit`, or a Bash command — the new lines are checked straight
after, and Claude is shown each finding so it rewrites the line while it still has the
context. The commit and push hooks still run, so nothing depends on this one.
*Acceptance: in a test repo marked public, with a test prompt log and transcript directory: a `Write`
holding a 6-word typed clause, an `Edit` adding a dated attribution, and a Bash heredoc
appending a `released as 1.2` line each produce a finding shown to Claude, naming the file,
line and rule; a clean write produces nothing; a `Write` holding 6 words Claude wrote
earlier in the same test session, which the test prompt then repeated, produces nothing; in a repo not marked public, or not enabled,
the hook does nothing and exits 0 within 50 ms; a stage-1 check on a 200-line change
finishes within E10's budget.*

- **C12.1 The hook.** A `PostToolUse` hook on every tool, registered by git-scrub's own
  `manifest.sh`. It returns at once outside an enabled public repo. Inside one, it diffs the
  working tree against what it saw after the previous tool call (the index and HEAD on the
  first call of a session), and passes only the new and changed lines on. A line is
  matched by its path and text, so one that only moved is not new. Untracked text files
  count in full. A `SessionEnd` hook removes the session's saved diff; `install.sh`
  registers both through `settings_merge`.
- **C12.2 The check.** `git scrub text` reads lines with their file and line number on
  stdin and runs stage 1 only: E3's runs, clauses and paraphrase with C3.2's lookup on a
  hit, the same as at commit, C1.4's labels including
  the three public-repo ones, and the repo's values and patterns. No model sweep, which
  takes too long for a tool call and still runs at commit.
- **C12.3 The finding.** Shown to Claude through the hook's output as a message that names
  the file, line and rule, never the matched value or my wording, and says to rewrite the
  line without it. It does not undo the write; the commit hook still refuses the line if
  it stays.
- **C12.4 Its state.** The last-seen diff per session is kept under the repo's git
  directory, mode 0600, and removed when the session ends.

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
  repo). The run's log records the SHA-1 of the checker's script and categories file, so a
  later change to either shows the comparison is stale. The public repo is marked public
  in git-scrub's config for this run, as its labels and sweep instruction are public-repo
  rules here (C4.4). Both run over the planted-case set and over the public repo's full history and
  HEAD tree; findings match line for line, except the four listed fixes (C4.2, C6.2, C6.3,
  C6.4) and the new wording rules (C3.5's whole clauses, C3.6's 6-word runs, C3.1's reading
  of every project's prompts, C3.2's exclusion of tool input and output), each shown by a planted case where the
  outputs differ as intended. Over the public repo's history and tree, the new rules'
  extra findings and the ones they no longer report are listed apart from the comparison.
- **D4 A failed check fails the run.** Every test subcommand ends with its pass and fail
  counts and exits 1 on any FAIL.
- **D5 Every run logs.** Every script and test subcommand writes
  `/tmp/<script>-<subcommand>.log` itself.
- **D6 Clean by its own check.** `git scrub history` over claude-skills finds nothing, and
  git-scrub is on there.
- **D7 In use.** Installed from a release tarball into
  `<tools-dir>/git-scrub`, on in both repos of E11 with the old
  checkers gone, with a row in `INVENTORY.md`.
- **D8 Documented.** README, SKILL.md and the claude-skills README row describe what
  shipped; every BACKLOG item is done or moved to a later version with a reason.
- **D9 Lint.** `shellcheck` passes on every script.
