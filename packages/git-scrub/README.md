# git-scrub

Stops names, ids, emails, your own wording and other values you've removed from
a repo from coming back in a commit or a push, and scrubs them out of history.
The values live in per-repo config outside the tree, so the repo never holds the
list of what it must not hold.

**Not built yet.** What it must do is in [`REQUIREMENTS.md`](REQUIREMENTS.md),
with acceptance criteria and a definition of done; open decisions and work are in
[`BACKLOG.md`](BACKLOG.md).

Part of [claude-skills](https://github.com/lenny1882/claude-skills), which holds several packages
that are each versioned, released and installed on their own.

## What you actually see

<The observable behaviour, from the user's side. Not the implementation.>

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

<The mechanism, and anything undocumented it relies on. If it depends on
behaviour that could be withdrawn in a Claude Code update, say so here and say
what the symptom would look like.>

## Tests

    ./test/run-tests.sh

Redirects `HOME` and `CLAUDE_DIR` into a temp directory, so your real config is
never touched. `./test/run-tests.sh` at the repo root runs every package's.

## Releasing

`/release git-scrub` at the repo root — bump `packages/git-scrub/VERSION` on `main`,
move `release/git-scrub-vX.x` onto it, tag `git-scrub-vX.Y.Z` there. The tag is what
publishes it. The release carries what `PAYLOAD` lists, and nothing else in
this directory.
