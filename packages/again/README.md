# again

Type `/again` after a set of questions or a list you can't follow, and Claude
gives it again in full: every item with its context, the current state and
the options, and every bare reference written out.

Without it, a reply full of `F7`, `1b`, `D-12` or `REQ-04` had to be decoded by
scrolling back, or asked for again in so many words — about fifteen times
between 28 Sep and 26 Oct 2026. A `Stop` hook against bare references is being
built in `claude-hooks`' `claude-guard-hooks` to stop the next such reply;
`/again` repairs one that has already gone out.

Part of [claude-skills](https://github.com/lenny1882/claude-skills), which holds several packages
that are each versioned, released and installed on their own.

## What you actually see

`/again` in a Claude Code session, or `/again <which one>` to pick an earlier
set. Claude re-presents the most recent question set or list with the original
numbering, so answers already given still line up. Each item says what it is,
the current behaviour, and the options with a recommendation. Answered items
stay in, marked with their answer. F-numbers, `1b`-style answers, decision and
requirement ids are written out where they appear.

## Install

Needs `curl`, `tar` and `jq`. From the newest release:

    v=$(curl -fsSL https://raw.githubusercontent.com/lenny1882/claude-skills/versions/versions.txt | awk '$1=="again" {print $2}')
    curl -fsSL "https://github.com/lenny1882/claude-skills/releases/download/again-v$v/again.tar.gz" | tar -xz
    cd again && ./install.sh

These lines never change between versions: `versions.txt` names the newest
stable release, and only once its tarball is uploaded. To pin a version,
download `.../releases/download/again-vX.Y.Z/again.tar.gz` instead.

Or from a clone of the whole repo:

    git clone https://github.com/lenny1882/claude-skills && cd claude-skills/packages/again
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

One `SKILL.md`, installed to `~/.claude/skills/again/`. Its frontmatter sets
`disable-model-invocation: true`, so Claude loads it only when you type
`/again`. The installer's live check fails if that line or the `name: again`
line goes missing. Relies on Claude Code reading `disable-model-invocation`
from skill frontmatter; if an update stops honouring it, the symptom is Claude
re-presenting lists nobody asked for.

## Tests

    ./test/run-tests.sh

Redirects `HOME` and `CLAUDE_DIR` into a temp directory, so your real config is
never touched. `./test/run-tests.sh` at the repo root runs every package's.

## Releasing

`/release again` at the repo root — bump `packages/again/VERSION` on `main`,
move `release/again-vX.x` onto it, tag `again-vX.Y.Z` there. The tag is what
publishes it. The release carries what `PAYLOAD` lists, and nothing else in
this directory.
