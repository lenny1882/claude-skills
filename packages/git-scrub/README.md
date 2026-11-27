# git-scrub

Stops names, ids, emails, your own wording and other values you've removed from
a repo from coming back in a commit or a push, and scrubs them out of history.
The values live in per-repo config outside the tree, so the repo never holds the
list of what it must not hold.

What it must do is in [`REQUIREMENTS.md`](REQUIREMENTS.md), with acceptance
criteria and a definition of done; what is built and what is still open is in
[`BACKLOG.md`](BACKLOG.md).

Part of [claude-skills](https://github.com/lenny1882/claude-skills), which holds several packages
that are each versioned, released and installed on their own.

## What you actually see

In a repo where `git scrub enable` has been run, a commit or push holding a forbidden
value is refused before it exists or leaves, with each line named:

    git-scrub: 1 finding(s) in staged
      notes.md:1  [real value]  <the value>

What it refuses, per repo:

- values from the repo's lists: literal, regular expressions, or strings in a JSON file
  picked out with jq;
- built-in labels: redaction labels, session ordinals and links, UUIDs, scratch paths,
  email addresses, Slack ids, an Atlassian domain;
- your own typed wording, taken from Claude Code's prompt log: 6 words in a row, a whole
  clause of 5 or more, or a close paraphrase, unless Claude or a tool wrote it first;
- new activity figures, when turned on;
- in a repo marked public: dated attributions, answered-question logs, release history,
  and what a model sweep (`claude -p`) finds: narrative, attributions, reported speech,
  commit messages describing the edit, placeholders the text gives back.

In a public repo, Claude is also told straight after any tool call that writes such a
line, naming the file, line and rule.

    git scrub enable / disable     hooks on or off in this repo
    git scrub id                   this repo's id and config folder
    git scrub staged | message F   what the hooks run
    git scrub push [TIP ARGS]      what pre-push runs
    git scrub tree [COMMIT]        every tracked line at a commit
    git scrub history [--sweep|--map]  every blob, message and identity ever committed
    git scrub rewrite              replace values through history, after a bundle backup

Exit codes: 0 clean, 1 findings, 2 a check could not run.

## Install

Needs `curl`, `tar` and `jq`. From the newest release:

    v=$(curl -fsSL https://raw.githubusercontent.com/lenny1882/claude-skills/versions/versions.txt | awk '$1=="git-scrub" {print $2}')
    curl -fsSL "https://github.com/lenny1882/claude-skills/releases/download/git-scrub-v$v/git-scrub.tar.gz" | tar -xz
    cd git-scrub && ./install.sh

These lines never change between versions: `versions.txt` names the newest
stable release, and only once its tarball is uploaded. To pin a version,
download `.../releases/download/git-scrub-vX.Y.Z/git-scrub.tar.gz` instead.

Or from a clone of the whole repo:

    git clone https://github.com/lenny1882/claude-skills && cd claude-skills/packages/git-scrub
    ./install.sh              # install
    ./install.sh --link       # or symlink, so edits in the checkout are live
    ./install.sh --dry-run    # show the settings change, write nothing
    ./install.sh --yes        # no prompts

Re-running the installer is safe and is how you upgrade. It merges into
`settings.json` rather than replacing it, backs the file up first, and only ever
touches its own entries. If Claude Code is already running, `/hooks` forces a
settings reload.

## Update

    ./update.sh            check, ask, upgrade, reinstall
    ./update.sh --check    report what is available and stop

Reads this package's line in `versions.txt`, so pre-releases, and releases of
the other packages in the repo, are never offered. Works from a downloaded
tarball as well as a clone — no git needed.

## Uninstall

    ./uninstall.sh                 ask before editing settings.json
    ./uninstall.sh --keep-settings leave settings.json alone
    ./uninstall.sh --keep-state    keep the package's state for a later reinstall

## How it works

Each repo's config is a folder at `~/.claude/skills/git-scrub/state/<id>/`, outside
every tree, keyed by the repo's root commit hash so a new remote URL, a rename, a host
move or a moved checkout finds it again. A shallow clone reads its root from a
commits-only bare clone of its remote. With no config found, every check refuses. The
skill's `SKILL.md` lists the files.

Stage 1 is bash, gawk, jq and git. The wording check reads `~/.claude/history.jsonl`
for what you typed, never its pasted text, and for a line that hits, looks the words up
in `~/.claude/projects/` to rule out text Claude, a tool or a subagent produced first.
Both files are Claude Code's own and undocumented; if their layout changes, wording
checks exit 2 (the log unreadable) or stop ruling Claude's text out (more
`wording` findings).

The model sweep sends lines that pass stage 1, in batches of 400, to `claude -p` on
stdin, with no tools, never a value from the lists. A batch it cannot answer blocks
with exit 2. At push, commits that passed their hooks under the current config are not
swept or checked again. A push reads only its new commits, never the pushed tree.

The write hook is a `PostToolUse` hook on every tool; it keeps the session's last-seen
uncommitted lines in `.git/scrub/` and checks only new ones. `rewrite` pipes `git
fast-export` through gawk into `git fast-import`.

Every run logs counts and categories, never a value, to the config's `log` and to
`${TMPDIR:-/tmp}/git-scrub-<subcommand>.log`. Uninstalling refuses to delete the config
unless given `--keep-state` or `delete` typed at the prompt.

## Tests

    ./test/run-tests.sh

Redirects `HOME` and `CLAUDE_DIR` into a temp directory, so your real config is
never touched. `./test/run-tests.sh` at the repo root runs every package's. Every test
gets a fake `claude`, except the checks labelled "real claude", which call the real one
(three calls) with your real login; `GIT_SCRUB_TEST_CLAUDE= ./test/run-tests.sh` leaves
them out, and they then fail as one check. `test/measure-e3.sh` counts the wording
rules' false hits over an invented corpus.

## Releasing

`/release git-scrub` at the repo root — bump `packages/git-scrub/VERSION` on `main`,
move `release/git-scrub-vX.x` onto it, tag `git-scrub-vX.Y.Z` there. The tag is what
publishes it. The release carries what `PAYLOAD` lists, and nothing else in
this directory.
