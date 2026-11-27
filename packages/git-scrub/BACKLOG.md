# git-scrub — backlog

Started 14 Nov 2026, when the package was scaffolded. Requirements are in
`REQUIREMENTS.md`; an item here that blocks a requirement says which.

---

## 1. Decide the hook point: commit, push or both — **DONE 25 Nov 2026**

Blocks E8. The commit checker runs at commit (`pre-commit`, `commit-msg`); the push checker
runs at push (`pre-push`). Commit time stops a value before it is in any object. Push time
also catches commits made with `--no-verify`, by a rebase, or in a clone without the hooks.

Answer: both, with push re-checking only what commit time didn't pass. In C8.6.

## 2. Decide the install model: per repo, or global `core.hooksPath` — **DONE 25 Nov 2026**

Blocks E8. A global `core.hooksPath` covers every repo with no step per repo, but it
replaces each repo's own hooks: the private repo's `.githooks`, any husky setup, GSD's
hooks. It only works if git-scrub's shims chain to the repo's own hook. A per-repo `git
scrub enable` leaves repos never enabled unchecked. Both need the chaining for repos with
hooks of their own.

Answer: per repo, with `git scrub enable`, chaining to the repo's own hooks. A repo that
sets its own `core.hooksPath` would bypass a global one. In C8.7.

## 3. Decide where per-repo config lives — **DONE 25 Nov 2026**

Blocks C8.1. Choices were: under the repo's git directory (`.git/scrub/`, lost with the
clone, shared by its worktrees), or `~/.config/git-scrub/<repo>` (kept when the clone is
deleted, keyed by what: the remote URL, the path?). The push checker's patterns already
live in `~/.config`.

Answer, in C8.1, C8.3, C8.4, C8.5 and E8's acceptance: the claude-package-kit state path
for a skill, `~/.claude/skills/git-scrub/state/<id>/`, where `~/.config` matches no other
package. The id is the root commit hash, since a remote URL changes with an SSH or HTTPS
form, a rename or a host move, a path changes with a moved checkout, and a repo can have no
remote or several. A shallow clone, which holds no root commit, reads the root from a
commits-only bare clone of its remote, so no case needs a command beyond `git scrub enable`. A repo with no config
found fails closed. Uninstall refuses to remove the config without `--keep-state` or a
confirmation.

## 4. Decide how the wording cache stores shingles — **DROPPED 25 Nov 2026**

There is no wording cache (C3.4): each run reads its inputs afresh.

## 5. Confirm the speed budget — **DONE 25 Nov 2026**

Blocks E10. Set from git-scrub's own two costs, measured read-only, rather than the commit
checker's, whose run writes to another project's clone: one pass over the prompt log
against a 200-line diff, and one lookup over the transcripts. E10 has the budget and the
measured figures; the paraphrase rule is still to be timed.

## 6. Build the planted-case set for the differential test — **DONE 25 Nov 2026**

For D3. One case per value source, label, category, boundary case in C1.3, and one for each
of the four fixes: a forced sweep failure, a modified working-copy file, a tracked path
with a space, and a timing check on HEAD's text being read once. The public repo has no
path with a space and no uncommitted change today, so its own history won't show the fixes.

Also, one case for each new wording rule, where git-scrub and the commit checker differ: an
unquoted 6-word typed clause (C3.5); 6 words from the middle of a longer typed clause,
which runs of 8 miss (C3.6); a clause typed in another project's session (C3.1);
a line Claude wrote to a file that I then pasted back in a prompt, and a line of command
output I pasted, neither of which git-scrub reports (C3.2). And for E3's measured
acceptance: the invented set of 200 typed prompts and the invented 2,000-line docs tree that
quotes none of them, built to hold stock phrases of 5 and 6 words and quoted tool output, so
the false-hit counts mean something.

Built in `test/cases/`:
- `cases.tsv`: 80 rows, one per case, each with the requirement it serves, where it goes
  (a file, the message, or a scenario), the line, git-scrub's expected categories and the
  commit checker's (`-` where the commit checker can't take the case: an ERE or literal
  source, the repo labels, the sweep's test categories, public-repo-off runs).
- `sources/`: the invented values (literal, ERE, a build-inputs-shaped JSON file, a Slack
  export), `sources.tsv` with the jq expression and kind for each JSON source, the
  allowlist, the repo labels, a message-line pattern and test categories.
- `prompts/`: a prompt log and transcripts for two projects, with a subagent transcript,
  Claude reply text, a tool call's input, a tool's output and a pasted prompt.
- `make-corpus.sh`: the 200 prompts, their transcript and the 2,000-line docs tree, the
  same bytes on every build.
- `check-cases.sh`: the manifest's shape, a case for each requirement and label, every
  fixture parsing, every jq source running, and the corpus repeating. `run-tests.sh`
  runs it.

The commit checker, run over the set in a temp repo with its prompt directory filled from
`prompts/`, gives the `checker` column on 54 of 55 file and message rows; V12 adds the
scratch-path label when the export path is under `/tmp/claude-<uid>`, which the case's
note now says. Its four fix scenarios come out as the column says: exit 1 on a sweep that
exits 1 (X1), a working-copy-only value found by `tree` (X2), a value in a path with a
space missed (X3), two `git grep` calls against HEAD (X4).

Seen failing first: with a row cut to 6 fields, the Claude scratch path label's only case
set to `pass`, and a malformed line added to the prompt log, `check-cases.sh` failed
exactly "every row has 7 fields", "a case for the label: Claude scratch path" and "every
line parses: prompts/history.jsonl", 67 passed and 3 failed.

`shellcheck` is not installed on this machine, so D9 is not yet run over these scripts.

## 12. Cut E3's remaining false hits in code — **OPEN, raised 25 Nov 2026**

For E3 and E12. Checking the two public repos' recent commits with C3.1 and C3.2 as now
written, the remaining false hits are lines of shell and Python code and of plan text that
I had pasted from somewhere these transcripts don't hold (another machine, a web session).
To measure: skip a run or clause already present in the repo's tracked text before the
commit adds it, as E5 does for figures, and count what is left.

## 7. Move the public repo onto git-scrub — **OPEN, raised 14 Nov 2026**

For E11. Its values, categories and allowlist move to config; the surname and local
export-path labels move to its config, out of the built-ins. The commit checker's
common-names list holds more names than git-scrub's built-in one, which keeps only names
that are also ordinary words; the rest go in that repo's `common.txt`.

## 8. Move the private repo's push checker onto git-scrub — **OPEN, raised 14 Nov 2026**

For E11. It is a change in another project, so it is made from a session there. Its test
harness labels, log lines and `FAULT=` runs stay.

## 9. Turn git-scrub on in claude-skills — **OPEN, raised 14 Nov 2026**

For P3 and D6, from the first working version.

## 10. The private repo's sanitising rules, and what E11 must carry over — **DONE 25 Nov 2026**

The five gaps below are now in REQUIREMENTS.md: C7.5 and E7's acceptance (deleting message
lines), C7.2 (any placeholder), C4.4 (public-repo categories), and E11's acceptance (the
allowlist, and the private repo's own requirement still passing).

For E11 and item 8. The push checker is one part of how the private repo is kept clean. The
whole set, from its requirements, its push checker, its hook and the notes kept with it:

1. **Forbidden list.** Kept outside the repo, one ERE per line, case-insensitive, `#` and
   blank lines skipped. Its categories: the work email, the real user name, client repo
   names, local paths on the laptop, session links, and `Claude-Session:` trailers.
2. **What is checked at push.** The pushed tip's tree, and each new commit's message and
   added lines (`+` lines, not `+++` headers). Binary files are skipped (`git grep -I`).
   Each hit prints cut to 200 characters.
3. **Identity.** Every new commit's author and committer is exactly one name and noreply
   address, set in the clone's own git config.
4. **Visibility.** An anonymous GitHub API request must get 404. Checked at the build and
   after any change to the repo's settings, never from a hook.
5. **Fail-first.** A planted line and a wrong author on a throwaway branch are each
   refused once, with no `FAULT=` switch needed.
6. **New content stays scrubbed.** New files and commits don't bring back a value the
   history rewrite took out, even though the repo is private.
7. **Placeholders, not values.** A per-person value in a doc or script is a placeholder:
   a fixed user name, a generic test user, numbered client names (`client_a` onwards). A
   script that needs the real value stops until it is filled in, rather than carrying a
   local default. A file pasted into a console has its placeholders filled at paste time,
   never in the repo.
8. **Values kept on purpose.** Two names were left in the history by choice: the
   directory's domain and a Bitbucket workspace name. They are not on the forbidden list.
9. **Test fixtures.** A fixture that needs a session link builds it at run time, so the
   literal never sits in the tree.
10. **The history rewrite.** Done once, before the first push: every value replaced,
    every commit's identity rewritten, `Claude-Session:` trailer lines deleted from
    messages, and handoff files folded into the plans and removed.

On top of these, a rule for every public repo: tracked files and commit messages hold only
requirements, behaviour, usage and technical reasons, with no narrative, attributions,
question logs or release history, and a placeholder is only a placeholder if nothing
around it gives the value back.

What REQUIREMENTS.md doesn't cover yet:

- **Deleting message lines.** C7 replaces values. Rule 10 deletes whole trailer lines
  (`Claude-Session:` and the like) from commit messages. `rewrite` needs a list of message
  line patterns to drop.
- **Rule 8 as allowlist entries.** C1.5 has the allowlist, but E11's move must put these
  two names in the private repo's allowlist, or `history` over it reports them.
- **Rule 7's placeholder style.** C7.2's numbered `[name-01]` placeholders differ from the
  readable ones already in the private repo's history. C7.2 needs to say the map takes any
  placeholder, and the generated map is only a starting point.
- **The public-repo rule.** No category for narrative, attributions or question logs, and
  no check that a placeholder can't be decoded from the text around it. Both are model
  sweep (E4) material: a category in the categories file for a public repo.
- **Rule 6 after the move.** E11's wrapper keeps `scrub-check.sh`'s labels and `FAULT=`
  runs. The repo's requirement (forbidden list, identity, visibility, one refusal each for
  a planted line and a wrong author) has to keep passing its own `criteria-status.sh` row.

## 11. The commit checker's current rules — **DONE 25 Nov 2026**

The commit checker's script and categories file differ from the versions REQUIREMENTS.md
was first drafted against. Its rules now: the owner's first name is forbidden, matched
case-sensitively; attributions of any kind, reported speech and answered-question logs are
forbidden; narrative and commentary is its own category; a placeholder may not be described;
figures measured on the owner's data during a run count as activity figures; the owner's
phrases are forbidden in tests and fixtures too. Its stage 1 gained four labels (the first
name, a dated attribution, an `Answered` line, `released as/in` a version), and its sweep
prompt asks for strictness on narrative, history, attribution and commentary.

In REQUIREMENTS.md: C1.4 (the first name in repo config; three labels for public repos),
C4.1 (the prompt's fixed instruction and answer format), C4.4 (public-repo labels,
instruction and categories, commit messages that describe the edit), and D3 (the
checker's hashes logged; the public repo marked public for the comparison).

## 13. Stage 1 — **DONE 25 Nov 2026** for E1, C1.1 to C1.6, C7.5's message check and E5

`skill/bin/git-scrub` (`staged`, `message`, `text`, `enable`, `disable`, `id`) and
`skill/lib/stage1.awk`, with the built-in labels in `skill/lib/labels.tsv` and the common
words in `skill/lib/common.txt`. `test/stage1-tests.sh` runs every planted file and
message row that stage 1 alone decides (50), the C1.6, C4.4 public-off and E5 opt-in
scenarios, E1's commit acceptance through the hooks, the log holding no value, and C8.4's
exit 2 with no config: 78 passed, 0 failed.

Seen failing first, each fault planted in a copy of the package:
- C1.3's boundary check removed: B3 and B7 failed, 76 passed and 2 failed.
- The Slack id label deleted: V16 and L9 failed, 76 passed and 2 failed.
- The allowlist ignored: V15 and "the allowlisted commit is made" failed, and the two
  clean-commit checks after it, since the refused file stayed staged; 74 passed and 4
  failed.

Not built yet, and refused with exit 2 and the reason rather than done wrongly: `enable`
over a repo's `core.hooksPath` (C8.7) and in a repo with no commits (C8.3). Still to do
for E8: `pre-push` and C8.6's passed-commit list, C8.3's shallow-clone step, and putting
`git-scrub` on `PATH` (P2).

## 14. Wording — **DONE 25 Nov 2026** for E3, C3.1 to C3.6

`skill/lib/wording.awk` finds 6-word runs, whole typed clauses of 5+ words and
paraphrases against the prompt log; `skill/lib/lookup.awk` rules out what Claude, a tool
or a subagent produced first, reading the prompt's own session and then one search over
the other transcripts, only for lines that hit. `test/wording-tests.sh` runs the 14
planted wording rows, the public-default, off-elsewhere, `wording=1` and `run_length=8`
scenarios, exit 2 with no prompt log, and the log holding no wording: 99 passed, 0 failed
with stage 1's tests.

Seen failing first, each fault planted in a copy of the package:
- The C3.2 lookup skipped: W7, W8, W9 and W10 failed, 95 passed and 4 failed.
- The run length set to 7: W1 and the `wording=1` scenario (which uses W1) failed, 97
  passed and 2 failed.
- Pasted text read into the prompts: W11 failed, 98 passed and 1 failed.

E3's measured acceptance, from `test/measure-e3.sh` over the corpus, whose 2,000 doc
lines are tracked in the measured repo and quote none of its 200 prompts, so every hit
is false. One in eight prompts opens with a stock phrase as a clause of its own, one in
eight has one inline, one in five pastes back a tool output line its transcript printed.
False hits, each rule on its own:
- runs of 5: 274; runs of 6: 88, 76 of them three 6-word stock phrases and 1 a chance
  run of the corpus's small vocabulary; runs of 8: 0;
- whole clauses of 4+: 247; of 5+: 160, all 5- and 6-word stock phrases typed as their
  own clause; of 6+: 76, the same ones runs of 6 catch;
- paraphrase: 0, once the repo's common words are removed (C3.3);
- the defaults together (runs of 6, clauses of 5+, paraphrase): 172.
No pasted-back tool output line was reported, so C3.2 ruled all of them out. The run
length stays 6 and the clause floor stays 5: shorter runs and a floor of 4 add false
hits, longer runs miss quotes, and a floor of 6 catches nothing runs of 6 don't.
Each of the eight runs took about 3 s over 2,000 lines; E10's lookup timing is still open.

## 15. Push, tree, hooks and lookup — **DONE 25 Nov 2026** for E2, E8 (except a rewrite), C2.1, C2.2, C6.2, C6.3, C8.3, C8.4, C8.6, C8.7, P2

`git scrub push` checks each pushed tip's tree, and each new commit's added lines, message
and identity unless it is on the passed list under the config's current hash; a deleted
ref is skipped. `git scrub tree` reads the commit through `git grep --null`. `enable`
installs `pre-commit`, `commit-msg`, `post-commit` and `pre-push`, chained to the repo's
own hooks in `.git/hooks` or, where `core.hooksPath` is set, from a hooks directory of its
own that forwards every other hook there; `disable` puts either back. The id lookup
covers a shallow clone through a commits-only bare clone, writes the match to
`scrub.id`, and gives a repo with no commits a generated id that its first commit moves
to the root hash. `manifest.sh` puts `git-scrub` on `PATH`; the copy finds `lib/` in the
installed skill. `test/e8-tests.sh`: 125 passed, 0 failed with the earlier tests.

Seen failing first, each fault planted in a copy of the package:
- Every new commit treated as passed: "a config change rechecks passed commits" failed,
  124 passed and 1 failed. (The --no-verify cases still failed the push, through the
  tip's tree.)
- The shallow-clone step skipped: the shallow clone, its `scrub.id`, the unreachable
  remote and the reachable-again cases failed, 121 passed and 4 failed. With a one-commit
  source the shallow tip was the root itself and the fault went unseen, so the source now
  has two commits.
- No forwarders for the other hooks in `core.hooksPath`: "other core.hooksPath hooks
  still run" failed, 124 passed and 1 failed.

Not built yet: the history rewrite (E7, and E8's after-a-rewrite case), uninstall's
refusal to remove the config (C8.5, and E8's uninstall-and-reinstall case), `history`
(E6), the model sweep (E4), the write hook (E12) and the private-repo visibility check
(C2.3).

## 16. Model sweep — **DONE 25 Nov 2026** for E4, C4.1 to C4.4

`sweep()` in `skill/bin/git-scrub` sends batches of 400 lines to `claude -p` on stdin,
with the repo's categories, `skill/lib/public-categories.md` in a repo marked public, the
public instruction there, and the related typed clauses chosen by
`skill/lib/sweep-wording.awk` with values removed by `stage1.awk`'s redact mode.
`test/sweep-tests.sh` checks, with a fake `claude` that every other test also gets: no
stage-1 value in the prompt, the redacted wording, the categories and public part, a
finding blocking with exit 1, an unusable answer and a failing `claude` each exiting 2
with the batch named, 451 lines in two batches with the second run after the first
fails, `SWEEP_SKIP=1`, `sweep=0`, and no sweep after a stage-1 finding. With the real
`claude`: S1 to S5 and S7 to S9 reported, S6's message reported, and C0 CLEAN. 148
passed, 0 failed.

Seen failing first, each fault planted in a copy of the package, run with the real
`claude` left out (its tests then fail as "E4 (real claude)"):
- The wording list sent without redaction: "no stage-1 value is in the prompt" and
  "related wording sent redacted" failed.
- An unusable answer treated as clean: both X1 (C4.2) checks failed.
- The built-in public categories emptied: "categories in the prompt" failed.

## 17. History — **DONE 25 Nov 2026** for E6, C6.0, C6.1, C6.5

`git scrub history` lists every object reachable from any ref once (`git rev-list --all
--objects`), reads the blobs through one `git cat-file --batch`, skips a blob with a NUL
in its first 8,000 bytes, and checks every commit message line, author and committer.
`--sweep` sends each distinct line to the model once. `test/history-tests.sh`: a value in
a blob later deleted is found by `history` and not `tree`, a working-copy-only value by
neither, a blob in three commits and two paths found once, a binary blob skipped, a
message value and an author value found, no sweep unless asked, and each distinct line
sent once. 148 passed, 1 failed, the one being the live sweep checks, left out of this run.

Seen failing first, each fault planted in a copy of the package:
- Reading every commit's tree instead of each blob once: C6.1 failed, and the
  deleted-blob and message cases, since the fault returned before reading them; 145
  passed and 4 failed.
- Binary blobs not skipped: "a binary blob is skipped" failed.
- Messages not read: "a message value" failed.
A fault reading each blob once per path went unseen: `rev-list --objects` already gives
each blob once, at its first path.

## 18. History rewrite — **DONE 25 Nov 2026** for E7, C7.1 to C7.5, and E8's after-a-rewrite case

`git scrub rewrite` refuses on a dirty tree, writes `.git/scrub/rewrite-<date>.bundle`
at mode 0600, pipes `git fast-export --all` through `skill/lib/rewrite.awk` into `git
fast-import`, resets the working tree, moves the config to the new root hash and clears
its passed list, then runs `history` and lists the outward steps. `history --map` writes
a starting `map.tsv` with numbered placeholders. `test/rewrite-tests.sh` runs E7's
acceptance: values in three commits' blobs, one message and one author, a trailer in two
messages, and a dropped directory; after the rewrite no trace of any value, each reading
as its placeholder, no trailer, the rest of each message unchanged, the path in no
commit, every identity rewritten, the bundle restoring the old history and not sent by a
push; plus C7.3's wording case. 166 passed, 1 failed, the one being the live sweep checks,
left out of this run.

Seen failing first, each fault planted in a copy of the package:
- Message lines not deleted: the trailer and the unchanged-message checks failed.
- Paths not dropped: "the dropped path is in no commit" failed.
- Blobs not rewritten: the clean-history check, three values' traces and the placeholder
  check failed.

## 19. Uninstall keeps the config — **DONE 25 Nov 2026** for C8.5 and E8's uninstall-and-reinstall case

`pre_uninstall` in `manifest.sh` refuses, with nothing removed, while the skill's
`state/` holds any repo's config, unless `--keep-state` is given or `delete` is typed.
`test/uninstall-tests.sh`: `uninstall.sh --yes` with no terminal refuses and leaves the
package and config in place; `--keep-state` removes the package and keeps the config; a
reinstall finds it. Seen failing first: with the refusal removed, all three failed, the
config being deleted by the first.

## 20. Write hook — **DONE 25 Nov 2026** for E12, C12.1 to C12.4

`git scrub write-hook` (`PostToolUse`, every tool) and `git scrub write-hook-end`
(`SessionEnd`), registered by `manifest.sh`'s `settings_merge`. Outside an enabled public
repo the hook returns at once. Inside, it lists every uncommitted line, keeps those not
in the session's saved diff (`.git/scrub/seen-<session>`, mode 0600), runs them through
`git scrub text`, and answers with a block decision whose reason names each file, line and
rule. `test/write-hook-tests.sh` feeds it the JSON Claude Code sends: a Write holding a
6-word typed clause, an Edit adding a dated attribution and a Bash heredoc appending a
release line are each reported; the report never holds the wording; an unfixed line is
not reported again; a clean write produces nothing; the saved diff is mode 0600 and
removed at session end; 200 new lines took 947 ms against E10's 1 s; a repo not marked
public took 16 ms and one not enabled 15 ms, both under 50 ms. 181 passed, 1 failed, the
one being the live sweep checks, left out of this run.

The 200-line case is within 6% of its budget, nearly all of it reading the prompt log
(item 14's 0.65 s): E10 is still to be confirmed on a quiet machine.

Seen failing first, each fault planted in a copy of the package:
- No saved diff kept: "not reported again" and "a clean write produces nothing" failed.
- The matched text left in the report: "the report never holds the wording" failed.
- The public-repo check removed: "not public: nothing within 50 ms" failed. The first
  version of that test kept only the last of five timed calls' output, by which time the
  line had been seen, and missed the fault; it now checks the first call.

## 21. Visibility check — **DONE 25 Nov 2026** for C2.3

`git scrub private [REMOTE]` reads the owner and repo from a GitHub remote (SSH, HTTPS
or `ssh://` form), asks `https://api.github.com/repos/<owner>/<repo>` with no token, and
exits 0 on 404, 1 on 200, and 2 on any other answer or a remote that is not GitHub.
`test/private-tests.sh` uses a fake `curl`: each URL form asks for the right repo, no
token reaches the request, and each answer gives its exit code. Seen failing first: the
first version left `.git` on the repo name from the SSH and `ssh://` forms, and those two
cases failed; planted, a 200 passing failed "200 fails", and a token passed through
failed "the request carries no token".

## 22. Differential test (D3) — **DONE 26 Nov 2026**

`test/d3.sh PUBLIC-REPO` runs the commit checker (by symlink, from where it is) and
git-scrub in temp clones, compares locations and categories only, logs to
`${TMPDIR:-/tmp}/d3.log` and lists the differing locations in `d3-detail.tsv`, mode 0600.
`GIT_SCRUB_FINDINGS=FILE` makes git-scrub write every finding's location and category
for it. Both sides set apart `wording`, `close to wording` and `identity` findings.

Run against the public repo: 3 passed, 0 failed, in about 34 minutes.
- Part 1, the planted set: 45 rows give the same findings from both checkers and 8 differ
  as the manifest says. V12's export path is relative to the temp repo, so no
  `/tmp/claude-<uid>` path is in it.
- Part 2, HEAD's tree: no difference outside the wording rules; set apart, 17 `wording`
  and 10 `close to wording` only from the commit checker, 12 `wording` only from git-scrub.
- Part 2, the full history: no difference outside the wording rules; set apart, 148
  `wording` and 288 `close to wording` only from the commit checker, 464 `wording` only
  from git-scrub.

Open: the set-apart `close to wording` findings are not compared, so D3 would still pass
if git-scrub's paraphrase rule stopped finding one the commit checker finds. To keep that
check, record the current locations as known differences and fail on any beyond them.

## 23. Wording lookup speed — **DONE 26 Nov 2026** for C3.2's order; E10 still open

The lookup follows C3.2's order: each prompt's own session first, then, only for the keys
it leaves, one search of the other transcripts, in the C locale, by eight greps in
parallel, returning only the matching lines for jq to read. A paraphrase key is searched
for by its longest word and kept to the lines holding every other word. E10 has the
timings. `GIT_SCRUB_GREP` names the grep the lookup runs, so the tests can see which
searches run. `test/wording-tests.sh` adds O1 (held in its own session and another: not
reported, no other transcript read, no search of every transcript), O2 (held only in
another session: not reported, that transcript read) and P1 (a paraphrase: reported with
no transcript holding it, not reported with one holding every word, which is read, and a
transcript holding only some of the words not read). 202 passed, 1 failed, the one being
the live sweep checks, left out of this run.

Seen failing first, each fault planted in a copy of the package:
- The pre-change order: "O1: no other session's transcript is read" failed, then, with
  the shared search still run first, "O1: no search over every transcript".
- Step 2 removed: O2's two checks failed.
- Only the longest paraphrase word searched for: "a transcript holding only some words is
  not read" failed, in both the file and the line versions.
- Only one of the eight greps run: O2's and P1's rule-out checks failed.

`git scrub history` over the public repo gives the same 447 findings, location and
category, as the code before these changes, in 7 min 24 s against 20 min 3 s.

Reading only the matching lines narrows one case: a key whose own regex misses, for its
words being split by something like `\r` or `\u00a0` in the JSON, is found only in a
line another key's regex matched, where the whole file was read before. It changed no
finding in the public repo's history. Not covered by a test: a transcript line longer
than a pipe buffer, which each grep's own output file is there for.

`wording.awk` runs in the C locale, with the same candidates on a 200-line diff, a
27,150-line one and the planted cases: the 200-line diff with no hit takes 2.7 s, within
E10's budget, now 3 s. Open for E10: `tree` over 2,000 files (item 24); the write hook, whose
200-line check took 1,054 and 1,076 ms in two of three runs at a load average of 2.5 to
3; the model sweep's time on a 200-line diff. Also open: item 12.
`test/e9-tests.sh` runs in `run-tests.sh` and passes (5 checks).

Running a long test from the Bash tool: each sandboxed command has its own process list,
so `pgrep` there cannot see a run started by another command, and a job left running with
`&` inside a backgrounded command is killed when that command ends; run it in the
foreground of the backgrounded command, and stop it with its task id.

## 24. `tree` over 2,000 files — **OPEN, raised 26 Nov 2026**

For E10. Over a 2,000-file repo of 308,892 lines, `tree` takes 185 s with wording off and
1,022 s with it on, against 30 s; E10 has the measurements.

Stage 1, **DONE 26 Nov 2026**: `skill/lib/labelfn.awk` writes `lmatch(i, s)` from the
run's labels file, built-ins and the repo's own `labels.tsv` alike, with each label's ERE
as a regex literal, `/` escaped; `stage1.awk` takes it as a second `-f` and calls it in
both `check()` and `redact()`. The suite: 202 passed, 1 failed, the live sweep checks, as
before. The same findings from the code before and after: on the planted cases, `staged`
44, `tree` 43 and redact mode over every case line 80; on the 2,000-file repo, rebuilt
the same way (265,067 text lines, the three repos having changed), `tree` 618. `tree`
over it with wording off: 15.2 s, against 168.6 s before; with wording on: 705 s,
877 findings.

Then, for wording. Split over the same repo, 710 s in all: stage 1 and reading the prompt
log 20 s; `wording.awk` 80.5 s, giving 2,217 candidates from 84 prompts; step 1 54 s,
leaving 145 keys from 49 prompts, 14 of them paraphrases; step 2's search of the other
transcripts 3.3 s, matching 25,401 lines (173 MB); step 2's loop per prompt 551 s. The
loop sends every matched line through `produced`'s jq once for each prompt with a run key
left, so the same 173 MB of JSON is parsed up to 49 times.

Step 2's single parse, **DONE 26 Nov 2026**: `produced_tagged()` parses the matched
lines once, as file<TAB>ms<TAB>string, and each prompt keeps those from other files and
before its own time, in the same order as before, then runs `lookup.awk` over them;
paraphrase lines still go through `produced()` per key. The suite: 202 passed, 1 failed,
the live sweep checks. The same findings as before: planted cases `staged` 44 and
`tree` 43; the 2,000-file repo's `tree` with wording on 877. That `tree` takes 481 s,
against 710 s.

jq's escaping, **DONE 26 Nov 2026**. The loop's time per prompt was split: 247 s went to
the paraphrase keys' search, nearly all of it in `produced()`'s jq, and 147 s to
`lookup.awk`. jq 1.6's `gsub("\n"; "\u001e")` takes time that grows much faster than the
string: 383 transcript lines of 17.7 MB took 12.9 s, where 1,100 lines of 66 MB with
shorter strings took 2.2 s. `produced()` and `produced_tagged()` now escape with `@tsv`,
which jq runs in C, and `lib/untsv.awk` decodes it, newlines to \036 as before: 0.33 s on
those 383 lines. The strings are byte for byte the same on those lines, on the five
largest transcripts (92 MB, 9.7 s before and 4.1 s after) and in the tagged form.
`lookup.awk` builds clauses only when a paraphrase key is among its keys, since only
paraphrase keys read them. The suite: 202 passed, 1 failed, the live sweep checks. The
same findings: planted cases `staged` 44 and `tree` 43; the 2,000-file repo's `tree` with
wording on 877. That `tree` takes 287 s, against 481 s.

The clause check, **DONE 27 Nov 2026**. Over the same repo rebuilt again (308,572 text
lines; `tree` 265 s with wording on, 669 findings), split again: `wording.awk` 85 s, step
2's paraphrase search 59 s, step 2's loop per prompt 46 s, jq over paraphrase lines 26 s,
step 1 21 s, stage 1 12 s. Nearly all of `wording.awk`'s time was the clause check, which
joined every span of 5 to 40 words at every word position: on a tenth of the lines,
988,000 joins for 5 clause hits. It now tries a span only where its first 5 words begin a
typed clause, and only at lengths a typed clause has, in the same order. The candidates
are byte for byte the same on that repo (2,217) and on the planted cases, with HEAD's text
and without. `wording.awk` takes 22.5 s, against 85 s; `tree` 216 s.

The 2,000-file repo is built by copying the tracked files of claude-skills, maestro-drive
and claude-impersonator (`git archive HEAD`, files under 200 KB, no images or archives)
into `copy0/`, `copy1/` and onwards until there are 2,000.
