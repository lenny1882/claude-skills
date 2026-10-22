# claude-skills

Claude Code skills for this machine's workflows: parallel GSD phases in their
own worktrees, and Flutter hot reload on a remote Mac.

Every package under `packages/` is versioned, released and installed on its
own. A fault in one says nothing about another, so each can be fixed and
shipped without touching the rest.

## Packages

| Package | What it does |
| --- | --- |
| [`phase-worktrees`](packages/phase-worktrees/) | One git worktree and branch per GSD phase, so several phases can be executed at once |
| [`flutter-hot-reload-mac`](packages/flutter-hot-reload-mac/) | Builds a Flutter app on a remote Mac's iOS simulator and hot reloads each local save, returning a screenshot |
| [`repo-remote-control`](packages/repo-remote-control/) | TODO: one line on what it does |
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
