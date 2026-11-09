# one-by-one

Type `/one-by-one` after a list of questions or points, and Claude goes
through it one item per reply, each with the detail it needs, waiting for your
answer before the next.

A list of several questions answered together gets each one too briefly, and
the answers come back bundled into one message. `/mate` fixes an answer that
bundled decisions by mistake; `/one-by-one` is for any list you want opened
up, fault or not.

Part of [claude-skills](https://github.com/lenny1882/claude-skills), which holds several packages
that are each versioned, released and installed on their own.

## What you actually see

`/one-by-one` takes the most recent list; `/one-by-one the decisions` or `/one-by-one F9-F12` names one. The first
reply says which list it is and how many items it has, then gives item 1 only,
headed "1 of 5 — <what it is>": what it is, what happens today (checked, not
remembered), and each option with what it changes, the recommended one marked.
Then it stops.

Your answer moves it to the next item. "skip", "next" and "back" work too.
After the last item, one closing list gives every item with its answer.

## Install

Needs `curl`, `tar` and `jq`. From the newest release:

    v=$(curl -fsSL https://raw.githubusercontent.com/lenny1882/claude-skills/versions/versions.txt | awk '$1=="one-by-one" {print $2}')
    curl -fsSL "https://github.com/lenny1882/claude-skills/releases/download/one-by-one-v$v/one-by-one.tar.gz" | tar -xz
    cd one-by-one && ./install.sh

These lines never change between versions: `versions.txt` names the newest
stable release, and only once its tarball is uploaded. To pin a version,
download `.../releases/download/one-by-one-vX.Y.Z/one-by-one.tar.gz` instead.

Or from a clone of the whole repo:

    git clone https://github.com/lenny1882/claude-skills && cd claude-skills/packages/one-by-one
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

A typed-only skill (`disable-model-invocation`), so Claude never loads it
uninvited. It is instructions only: no hook, no script, no state. Where it
has got to in the list lives in the conversation, so a `/compact` or
`/clear` midway loses the place; type `/one-by-one` again to pick up from the
items not yet answered.

## Tests

    ./test/run-tests.sh

Redirects `HOME` and `CLAUDE_DIR` into a temp directory, so your real config is
never touched. `./test/run-tests.sh` at the repo root runs every package's.

## Releasing

`/release one-by-one` at the repo root — bump `packages/one-by-one/VERSION` on `main`,
move `release/one-by-one-vX.x` onto it, tag `one-by-one-vX.Y.Z` there. The tag is what
publishes it. The release carries what `PAYLOAD` lists, and nothing else in
this directory.
