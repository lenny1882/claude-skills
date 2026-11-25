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

