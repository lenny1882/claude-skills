# git-scrub — backlog

Started 14 Nov 2026, when the package was scaffolded. Requirements are in
`REQUIREMENTS.md`; an item here that blocks a requirement says which.

---

## 1. Decide the hook point: commit, push or both — **OPEN, raised 14 Nov 2026**

Blocks E8. The commit checker runs at commit (`pre-commit`, `commit-msg`); the push checker
runs at push (`pre-push`). Commit time stops a value before it is in any object. Push time
also catches commits made with `--no-verify`, by a rebase, or in a clone without the hooks.
Recommended: both, with push re-checking only what commit time didn't see.

## 2. Decide the install model: per repo, or global `core.hooksPath` — **OPEN, raised 14 Nov 2026**

Blocks E8. A global `core.hooksPath` covers every repo with no step per repo, but it
replaces each repo's own hooks: the private repo's `.githooks`, any husky setup, GSD's
hooks. It only works if git-scrub's shims chain to the repo's own hook. A per-repo `git
scrub enable` leaves repos never enabled unchecked. Both need the chaining for repos with
hooks of their own.

## 3. Decide where per-repo config lives — **OPEN, raised 14 Nov 2026**

Blocks C8.1. Choices: under the repo's git directory (`.git/scrub/`, lost with the clone,
shared by its worktrees), or `~/.config/git-scrub/<repo>` (kept when the clone is deleted,
keyed by what: the remote URL, the path?). The push checker's patterns already live in
`~/.config`.

## 4. Decide how the wording cache stores shingles — **OPEN, raised 14 Nov 2026**

Blocks C3.4. The commit checker stores 16-hex-digit SHA-1 prefixes. gawk has no SHA-1, and
one `sha1sum` per shingle is too slow. Choices: plain text, or a gawk FNV-1a hash. The cache
already holds my sentences in plain text, mode 0600, so plain text exposes nothing new.

## 5. Confirm the speed budget — **OPEN, raised 14 Nov 2026**

Blocks E10. The numbers there (2 s for a 200-line diff, 30 s for a 2,000-file tree) are a
draft. Measure the commit checker on the public repo first, so the budget is set against
something.

## 6. Build the planted-case set for the differential test — **OPEN, raised 14 Nov 2026**

For D3. One case per value source, label, category, boundary case in C1.3, and one for each
of the four fixes: a forced sweep failure, a modified working-copy file, a tracked path
with a space, and a timing check on HEAD's text being read once. The public repo has no
path with a space and no uncommitted change today, so its own history won't show the fixes.

## 7. Move the public repo onto git-scrub — **OPEN, raised 14 Nov 2026**

For E11. Its values, categories and allowlist move to config; the surname and local
export-path labels move to its config, out of the built-ins.

## 8. Move the private repo's push checker onto git-scrub — **OPEN, raised 14 Nov 2026**

For E11. It is a change in another project, so it is made from a session there. Its test
harness labels, log lines and `FAULT=` runs stay.

## 9. Turn git-scrub on in claude-skills — **OPEN, raised 14 Nov 2026**

For P3 and D6, from the first working version.
