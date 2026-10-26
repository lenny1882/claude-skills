# owl

Type `/owl` after an answer that skipped steps, and Claude redoes it end to
end: every step written out, the ones it can run run, and one command left for
you.

Without it, finishing a task meant asking for the missing steps one reply at a
time, or objecting to an answer that handed out part of the route and stopped.
That happened in about a dozen sessions across five projects between 28 Sep
and 26 Oct 2026. A memory written to stop it was never added to its project's
index, so it was never loaded; a skill you type is loaded every time.

Part of [claude-skills](https://github.com/lenny1882/claude-skills), which holds several packages
that are each versioned, released and installed on their own.

## What you actually see

`/owl` in a Claude Code session. Claude checks where things stand, then lists
every step to finish the task, in order. Each step says where it runs (Claude's
Bash, `!` in Claude Code, or your own terminal), the exact command, how to get
any short-lived or single-use key or login it needs, what to capture, and the
output that means it worked. Claude then runs every step it can, reporting each
result, and the answer ends on the single command left for you, on one line.

## Install

Needs `curl`, `tar` and `jq`. From the newest release:

    v=$(curl -fsSL https://raw.githubusercontent.com/lenny1882/claude-skills/versions/versions.txt | awk '$1=="owl" {print $2}')
    curl -fsSL "https://github.com/lenny1882/claude-skills/releases/download/owl-v$v/owl.tar.gz" | tar -xz
    cd owl && ./install.sh

These lines never change between versions: `versions.txt` names the newest
stable release, and only once its tarball is uploaded. To pin a version,
download `.../releases/download/owl-vX.Y.Z/owl.tar.gz` instead.

Or from a clone of the whole repo:

    git clone https://github.com/lenny1882/claude-skills && cd claude-skills/packages/owl
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

One `SKILL.md`, installed to `~/.claude/skills/owl/`. Its frontmatter sets
`disable-model-invocation: true`, so Claude loads it only when you type `/owl`,
never on its own judgement. The installer's live check fails if that line or
the `name: owl` line goes missing. Relies on Claude Code reading
`disable-model-invocation` from skill frontmatter; if an update stops honouring
it, the symptom is Claude redoing answers nobody asked it to redo.

## Tests

    ./test/run-tests.sh

Redirects `HOME` and `CLAUDE_DIR` into a temp directory, so your real config is
never touched. `./test/run-tests.sh` at the repo root runs every package's.

## Releasing

`/release owl` at the repo root — bump `packages/owl/VERSION` on `main`,
move `release/owl-vX.x` onto it, tag `owl-vX.Y.Z` there. The tag is what
publishes it. The release carries what `PAYLOAD` lists, and nothing else in
this directory.
