# mate

Type `mate`, `bruv` or `dude` after an answer that missed the point, and
Claude names how it missed and answers again.

Between 12 Oct and 9 Nov 2026, about 47 complaints in 2,140 typed messages
were about four ways an answer misses: it went off on a tangent (about 20),
gave a page for a yes/no question (12), explained the mechanism when the
question was about the outcome (8), or bundled several decisions into one
reply (7). Each took several messages to put right. One word now does it.

Part of [claude-skills](https://github.com/lenny1882/claude-skills), which holds several packages
that are each versioned, released and installed on their own.

## What you actually see

`mate`, `bruv` or `dude` as the whole message, with or without a slash, any
case, trailing punctuation allowed. The reply's first line names the fault, for
example "That went off into build work; the question was what is left to
plan." Then:

- **Tangent:** the answer to the question, inside the session's mode. If the
  tangent changed files or ran commands, they are listed first; nothing is
  undone unless you say so.
- **Overkill:** the yes/no or the fact, plus at most one line on why.
- **Technical:** the outcome in plain words.
- **Several in one:** the first question or decision only, with its context.
  Claude waits for your answer before giving the next. A run of commands meant
  to be pasted together is never split.

A message that merely contains the word — "thanks mate", "mate, why?" — is
left alone.

## Install

Needs `curl`, `tar` and `jq`. From the newest release:

    v=$(curl -fsSL https://raw.githubusercontent.com/lenny1882/claude-skills/versions/versions.txt | awk '$1=="mate" {print $2}')
    curl -fsSL "https://github.com/lenny1882/claude-skills/releases/download/mate-v$v/mate.tar.gz" | tar -xz
    cd mate && ./install.sh

These lines never change between versions: `versions.txt` names the newest
stable release, and only once its tarball is uploaded. To pin a version,
download `.../releases/download/mate-vX.Y.Z/mate.tar.gz` instead.

Or from a clone of the whole repo:

    git clone https://github.com/lenny1882/claude-skills && cd claude-skills/packages/mate
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

`/mate` is a skill. `/bruv` and `/dude` are two more skills that tell Claude
to follow `/mate`'s; a slash command only resolves when a skill directory of
that name exists. All three are `disable-model-invocation`, so Claude never
loads them uninvited.

A bare word without the slash is caught by `hooks/mate-bare-word.sh` on
`UserPromptSubmit`. A hook cannot rewrite the prompt, and Claude cannot call a
`disable-model-invocation` skill through the Skill tool, so the hook adds the
skill's text, frontmatter removed, as `additionalContext`. If Claude Code stops
accepting `additionalContext` from `UserPromptSubmit`, the symptom is a bare
`mate` getting an ordinary reply instead of a named fault; `/mate` still works.
The hook fails open: no `jq`, no skill file or unreadable input lets the
message through as typed.

## Tests

    ./test/run-tests.sh

Redirects `HOME` and `CLAUDE_DIR` into a temp directory, so your real config is
never touched. `./test/run-tests.sh` at the repo root runs every package's.

## Releasing

`/release mate` at the repo root — bump `packages/mate/VERSION` on `main`,
move `release/mate-vX.x` onto it, tag `mate-vX.Y.Z` there. The tag is what
publishes it. The release carries what `PAYLOAD` lists, and nothing else in
this directory.
