# compare

Type `/compare` (or `/side-by-side`) and Claude lays out things already in
the conversation — two drafts, options, files, versions, outputs — as level
columns, then names each difference.

"Side by side" means parallel columns where corresponding lines sit level and
you read across. Asked for in passing, it came back as two blocks one after the
other, or a markdown table whose cells wrap to different heights, or columns
laid out by hand that drifted a row out after the first long line. There was no
short way to ask for a comparison of what was already on screen.

Part of [claude-skills](https://github.com/lenny1882/claude-skills), which holds several packages
that are each versioned, released and installed on their own.

## What you actually see

`/compare` alone compares the two most recent comparable things;
`/compare the two drafts` or `/compare F3 F4` names them. The reply is a code
fence 99 columns wide, 48 per side with a 3-column gutter, both sides verbatim:

    Draft 1                                            Draft 2
    ------------------------------------------------   ------------------------------------------------
    Changing this breaks the login page.             * Changing this breaks the login page and the
                                                     * admin export.
    Same line here.                                  | Same line here.
                                                     > Extra.

`|` same, `*` changed, `<` only on the left, `>` only on the right. Below it,
one line per difference saying what it changes. No verdict unless you ask.
More than two things are compared each against the first.

## Install

Needs `curl`, `tar` and `jq`. From the newest release:

    v=$(curl -fsSL https://raw.githubusercontent.com/lenny1882/claude-skills/versions/versions.txt | awk '$1=="compare" {print $2}')
    curl -fsSL "https://github.com/lenny1882/claude-skills/releases/download/compare-v$v/compare.tar.gz" | tar -xz
    cd compare && ./install.sh

These lines never change between versions: `versions.txt` names the newest
stable release, and only once its tarball is uploaded. To pin a version,
download `.../releases/download/compare-vX.Y.Z/compare.tar.gz` instead.

Or from a clone of the whole repo:

    git clone https://github.com/lenny1882/claude-skills && cd claude-skills/packages/compare
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

Claude writes each side verbatim to a scratch file and runs
`skill/bin/side-by-side.py`, so the layout is never done by hand. It matches
lines with Python's `difflib`, so an unchanged line stays level with its twin
when lines are added or removed above it. It wraps each line to 48 columns at
the last space that fits (mid-word if there is none) and pads the shorter side
of each pair with blank rows. Tabs become four spaces; wide characters (CJK,
most emoji) count as two columns. Needs `python3` (3.8 or later).

`/side-by-side` is a second skill that tells Claude to follow `/compare`'s; a
slash command only resolves when a skill directory of that name exists. Both
are `disable-model-invocation`, so Claude never loads them uninvited.

## Tests

    ./test/run-tests.sh

Redirects `HOME` and `CLAUDE_DIR` into a temp directory, so your real config is
never touched. `./test/run-tests.sh` at the repo root runs every package's.

## Releasing

`/release compare` at the repo root — bump `packages/compare/VERSION` on `main`,
move `release/compare-vX.x` onto it, tag `compare-vX.Y.Z` there. The tag is what
publishes it. The release carries what `PAYLOAD` lists, and nothing else in
this directory.
