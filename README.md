# claude-skills

Claude Code skills for this machine's workflows: parallel GSD phases in their
own worktrees, Flutter hot reload on a remote Mac, one-off Remote Control
sessions and a Remote Control server per repo, three typed repairs for a bad
answer — `/owl`, `/again` and `/mate` — `/compare`, which lays things already in
the conversation side by side, and `/one-by-one`, which takes a list one item
per reply.

Every package under `packages/` is versioned, released and installed on its
own. A fault in one says nothing about another, so each can be fixed and
shipped without touching the rest.

## Packages

| Package | What it does |
| --- | --- |
| [`phase-worktrees`](packages/phase-worktrees/) | One git worktree and branch per GSD phase, so several phases can be executed at once |
| [`flutter-hot-reload-mac`](packages/flutter-hot-reload-mac/) | Builds a Flutter app on a remote Mac's iOS simulator, or a USB iPhone on it, and hot reloads each local save, returning a screenshot. Needs `maestro-drive` 2.2.0 or later; 2.3.0 or later for a phone |
| [`owl`](packages/owl/) | `/owl` redoes the last answer end to end when it skipped steps: every step written out, Claude runs what it can, one command left for you |
| [`again`](packages/again/) | `/again` gives the last question set or list again in full, with every bare reference such as `F7` or `1b` written out |
| [`repo-remote-control-session`](packages/repo-remote-control-session/) | `rrc session` opens one Claude Remote Control session in a repo, as a systemd user unit, and prints its URL for claude.ai or the Claude app |
| [`repo-remote-control-server`](packages/repo-remote-control-server/) | `rrcd` runs a Remote Control server per repo as a systemd user unit that survives reboots and claude updates; needs `repo-remote-control-session` |
| [`mate`](packages/mate/) | `mate`, `bruv` or `dude` redoes the last answer that missed the point: it names the fault (tangent, overkill, technical, several in one) and fixes it |
| [`compare`](packages/compare/) | `/compare` or `/side-by-side` lays things already in the conversation out as level columns, both sides verbatim, and names each difference |
| [`one-by-one`](packages/one-by-one/) | `/one-by-one`, `/individually` or `/separately` goes through a list already given one item per reply, each in full, waiting for your answer before the next |
<!-- new-package.sh --monorepo adds a row above this line -->

## Install a package

Needs `curl`, `tar` and `jq`. Set `pkg` to a name from the table:

    pkg=<package>
    v=$(curl -fsSL https://raw.githubusercontent.com/lenny1882/claude-skills/versions/versions.txt | awk -v p="$pkg" '$1 == p {print $2}')
    curl -fsSL "https://github.com/lenny1882/claude-skills/releases/download/$pkg-v$v/$pkg.tar.gz" | tar -xz
    cd "$pkg" && ./install.sh

`versions.txt` lists each package's newest stable version. The release workflow
writes a package's line only after that release's tarball is uploaded, so the
lines above never change between versions and always fetch something that
exists. To pin a version instead:

    https://github.com/lenny1882/claude-skills/releases/download/<package>-vX.Y.Z/<package>.tar.gz

Each package's own README has the same lines with its name filled in, and
covers updating and uninstalling.

## Tests

    ./test/run-tests.sh

Runs every package's own suite, one section each, and fails if any of them
does.

## Releasing

`/release <package>` in this repo — bump `packages/<package>/VERSION` on
`main`, move `release/<package>-vX.x` onto it, and tag `<package>-vX.Y.Z` there.
The tag is what publishes it. See `.claude/skills/release/SKILL.md`.
