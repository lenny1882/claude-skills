# repo-remote-control — design notes

Written 20 Oct 2026, at the end of the first design session. Updated 22 Oct
with the naming decision and the results of the remaining Docker checks.
Nothing is built yet apart from the package scaffold and the Docker checks in
`test/docker/`.

## What it's for

The always-on dev box (an AWS WorkSpace, Ubuntu 24.04, user `DEVTEST\james`)
runs one orchestrator Claude session in `~/repos`, in tmux, from a systemd
user service. You want to start work in any repo from claude.ai or the Claude
app without SSHing in.

A Claude Remote Control **server** (`claude remote-control`) only opens
sessions in its own directory, so each repo needs its own server. This package
starts and manages one server per repo, as a systemd user service that
survives reboots. It does that through a skill the orchestrator uses and a
command, `rrc`, you can type over SSH.

The original brief is the handoff from the aws-workspace session. Its tested
unit file and test script are in
`~/claude-sandbox/aws-workspace/scripts/remote-control-systemd-test.sh`, and
the write-up is item 12 of `aws-workspace/planning/BEFORE-STARTING.md`.

## Commands

| Command | What it does |
| --- | --- |
| `rrc start <dir>` | Find the repo root, trust it, enable and start its server. Prints the environment URL. |
| `rrc list` | Every repo with a server: unit state, URL, open sessions, last error, and whether it runs an older `claude` than the one on disk. |
| `rrc stop <dir>` | Stop the server now. It comes back at the next boot. |
| `rrc disable <dir>` | Stop it and keep it from coming back. Trust stays, so a later `start` is quick. |
| `rrc remove <dir>` | Undo `start`: disable, forget the URL, clear the trust key. Lists the repo's worktrees, with branch and uncommitted or unpushed work; deletes them only with `--worktrees`. |
| `rrc clone <url-or-slug> [path]` | Clone, then `start`. |
| `rrc restart-all` | Restart every server, so each picks up a new `claude` binary. |
| `rrc session <dir>` | Session mode: one session, not a server. |

**Always the URL, never the name.** `rrc start` and `rrc list` print each
server's current environment URL, read from its output, and `SKILL.md` tells
the orchestrator to give you that link rather than an environment name. A
stopped server's environment may stay in the app's list under the same name
as the live one; a session opened in it never starts and shows as
disconnected. One unexplained failure on 22 Oct may have been that.

`rrc` is the skill's script, also linked into `~/.local/bin`. Nothing called
`rrc` exists on this machine or in Ubuntu's packages.

## Decisions

### Starting a server

- **Repo root.** `git rev-parse --show-toplevel`. Worktree mode needs a git
  repo, and trust is keyed on the repo root (trusting `~/repos` doesn't cover
  repos inside it).
- **Trust.** Set `projects["<root>"].hasTrustDialogAccepted = true` in
  `~/.claude.json`. Other `claude` processes rewrite that file, so:
  1. back it up;
  2. jq to a temp file and `mv`, keeping the time between read and `mv` short;
  3. start the unit, and if the output says "Workspace not trusted", set the
     key again and retry.

  This checks that the server runs, not just what the file says. It can't
  stop our `mv` overwriting a write another `claude` made in the same
  instant; the backup makes that recoverable.
- **Units.** The package installer writes both templates to
  `~/.config/systemd/user` and runs `daemon-reload`; the uninstaller disables
  every instance and removes them. Linger (`loginctl enable-linger`) is
  setup.sh's job.
- **Unit template** as tested by the aws-workspace session.
  `WorkingDirectory=/%I` needs the leading slash.

  ```
  [Unit]
  Description=Claude Remote Control server in /%I

  [Service]
  WorkingDirectory=/%I
  ExecStart=%h/.local/bin/claude remote-control --spawn worktree
  Restart=on-failure
  RestartSec=30

  [Install]
  WantedBy=default.target
  ```

- **Flags each server runs with:**
  - `--spawn worktree`: every session gets its own git worktree.
  - `--permission-mode auto` by default, settable per repo.
  - `--no-create-session-in-dir` by default, settable per repo. Otherwise the
    server opens a session in the main checkout at every start.
  - `--remote-control-session-name-prefix` (see "Naming").
- **One server per repo.** systemd names the instance after the repo path,
  and Claude refuses a second server in the same folder.

### Output and the URL

The plan was a wrapper keeping only the latest status screen in a small file,
because the handoff reported about 500,000 journal lines a day per repo. The
Docker checks measured the output written to a file
(`StandardOutput=truncate:<file>`):

- idle server: 700 bytes, then nothing;
- one session open, after one short exchange: 12.9 KB;
- after that session ended: 46.8 KB.

So the output grows with session activity, by tens of KB for a short session,
and not while idle.

**Decided 22 Oct:** `StandardOutput=truncate:<file>`, no wrapper. A busy repo
writes a few MB a day, and the file resets at every restart, including the
one after each `claude` update. `rrc list` reads the current screen: whatever
follows the last `ESC[J`. If a file grows too large in practice, a wrapper
can be added later. The file is `state/logs/<instance>.log` (see "Where
`rrc` keeps its files").

The environment URL changes on every restart, so `rrc list` reads it from the
current output rather than storing it once.

### Sandbox

Sessions follow the global `sandbox.enabled` setting. Claude Code's own
message: "To sandbox sessions, set sandbox.enabled to true in settings."

- setup.sh turns the sandbox on globally and installs `bubblewrap` and
  `socat`.
- `rrc start` checks it. If it's off, `rrc` stops and says why, the calling
  Claude asks you, and only your yes lets it rerun with
  `--allow-unsandboxed`. It never proceeds on its own.
- Confirmed in Docker (`sandbox-auto`, 22 Oct): a server session with the
  sandbox on and `--permission-mode auto` reports auto mode, and the sandbox
  blocks a write outside its worktree without asking. Auto mode alone does
  not: the same write went through with the sandbox off.
- **`rrc` can't run inside the orchestrator's sandbox.** The sandbox blocks
  all three things `rrc start` does outside the repo: `systemctl --user` over
  the user bus, writing to `~/.config/systemd/user`, and writing
  `~/.claude.json` (`sandbox-rrc`, 22 Oct; the same three fail on this
  machine's sandbox). With `"excludedCommands": ["rrc"]` in the sandbox
  settings, all three work from the sandboxed session. setup.sh adds that
  entry.

### Restarting after a `claude` update

A running server keeps the old binary until it restarts, and restarting ends
the sessions open in it.

- A systemd path unit watches `~/.local/bin/claude`.
- When it changes, idle servers (0 open sessions) restart automatically.
- For servers with sessions open, the watcher types a message into the
  orchestrator's tmux pane, and the orchestrator asks you straight away.
- `rrc restart-all` on request restarts everything.
- The pane is `ORCHESTRATOR_TMUX` in `state/config` (see "Where `rrc` keeps
  its files"),
  default `orchestrator:0`. The aws-workspace handoff starts the orchestrator
  with `tmux new-session -d -s orchestrator -c ~/repos 'claude --remote-control "orchestrator"'`
  and adds other windows to that session, so the window number matters.
- Confirmed in Docker (`tmux-queue`, 22 Oct): a message typed with
  `tmux send-keys` into a session that is busy with a foreground command waits,
  and is answered after the current turn.
- Confirmed (`idle-count`, 22 Oct): "Capacity: N/32" went 0 → 1 → 0 as a
  session opened and ended, so it can tell idle servers apart.
- **A new server can be refused for about 70 seconds.** Once, a server started
  right after the previous server in the same repo had stopped printed "This
  folder is already served by a terminal `claude remote-control` on this
  device. Stop it first. Exiting in about 70 seconds." The previous one was a
  `--spawn session` server that had exited on its own when its session ended.
  A plain `systemctl restart` of a worktree server (`name-restart`) was not
  refused, and neither were the other back-to-back starts.

  **Decided 22 Oct:** systemd does the retrying. The unit's
  `Restart=on-failure` and `RestartSec=30` start a refused server again until
  the old registration clears; this also covers restarts systemd makes on its
  own, which `rrc` never sees. `rrc start` waits up to 2 minutes for the URL in
  the output file, then reports it or the last error. This relies on a
  refused server exiting with an error; check that in Docker during the
  build. If it exits 0, fall back to `Restart=always` or to `rrc` stopping and
  starting the unit itself.

### Session mode

One session rather than a server. One-off: a temporary unit, gone when the
conversation ends or the box reboots. A repo that should stay reachable gets a
server.

Claude Code has this built in, `claude remote-control --spawn session`, so
tmux isn't needed. Confirmed in Docker (`spawn-session`, 22 Oct): it opens one
session without you starting it, titled with `--name`, applies
`--permission-mode`, and the process exits when the session ends. It's
refused in a repo that already has a server, so `rrc session` must check for
one and say so.

### Cloning

- `rrc clone <url-or-slug> [path]`.
- A full URL from any host (Bitbucket, GitHub) is used as given.
- A bare slug is expanded with `CLONE_BASE`, default
  `git@ssh.bitbucket.org:oneiota/`.
- `[path]` is relative to `~/repos` (for example `client_hugoboss`, matching
  Bitbucket projects); an absolute path is used as given; no path means
  `~/repos`.

Bitbucket moves Git-over-SSH to `ssh.bitbucket.org` by 12 Nov 2026, and
`bitbucket.org` becomes HTTPS-only.

### Branches

Claude Code names a server session's branch `worktree-bridge-<session ID>` and
puts its worktree in `<repo>/.claude/worktrees/bridge-<session ID>`, based on
the trunk on origin. You don't want generated branch names.

Each session names its own branch, by your convention, once it knows the
task.

**Convention.**

- `<type>/<KEY>-<description>` when there's a Jira ticket in any project,
  else `<type>/<description>`.
- The description is lower-case words joined by hyphens.

| Type | Meaning | Default base |
| --- | --- | --- |
| `feature` | A feature; a GSD milestone | trunk |
| `unit` | A contained task within a feature; a GSD phase. Uses its own Jira key if it has one | its feature's branch |
| `bug` | A fix | trunk |
| `docs` | Documentation | trunk |
| `tmp` | Throwaway, never merged | trunk |

Bases are defaults, not rules. A session uses another base when you say so or
the work needs it, and nothing checks or blocks that.

**Existing branches.** Say so in the first message ("work on
`feature/HB-123-basket-totals`") and the session runs `git switch` to it
instead of creating one. A branch can be checked out in only one worktree at
a time. If it's checked out elsewhere, the session says where and you choose.
Nothing in the app picks a branch when a session opens.

**How it's enforced.** Claude's own worktree creation stays as it is. Two
hooks act only on paths under `.claude/worktrees/bridge-*`:

1. **`SessionStart`.** `git switch --detach` and delete the empty
   `worktree-bridge-…` branch. The session starts on the trunk with no
   branch, and its instructions say to create its branch first.
2. **`PreToolUse` commit guard.** Block `git commit` on a detached HEAD with
   "create your branch first: git switch -c <type>/<KEY>-<description>".

   **Decided 22 Oct: Bash only, and advisory.** It matches `git commit`,
   `git -C <dir> commit` and commits inside `&&` chains in Bash commands. A
   commit made another way gets past it: a GSD MCP tool such as
   `gsd_commit_docs`, a git alias, a script. That's accepted: the
   `SessionStart` instructions are the main defence, and a commit on a
   detached HEAD can still be put on a branch with `git switch -c`. Hooking
   GSD's MCP tools or a per-repo git `pre-commit` hook can be added later.

**Why not a `WorktreeCreate` hook.** It replaces worktree creation for every
caller on the machine, including GSD's executor subagents. Those are based on
the phase branch's HEAD, commit per task, and rely on Claude's locking and
cleanup. Copying all of that would track Claude's internals with every
release. The two narrow hooks leave GSD, subagents, `EnterWorktree`,
`claude --worktree` and `phase-worktrees` alone, so installing everywhere is
safe.

**What this costs.**

- Worktree directory names stay generated.
- Claude's own rules decide when server worktrees are cleaned up.
- The generated branch exists for a second or two before `SessionStart`
  runs.

**Confirmed in Docker** (`sessionstart-detach`, 22 Oct, with a stand-in hook
in `test/docker/fixtures/`): `SessionStart` fires in the server session's
worktree with that worktree as its cwd, before the session's first command.
The session's own `git status` already showed `HEAD detached` and no
`worktree-bridge-*` branch. When the session ended unused, the server still
removed the detached worktree ("removed worktree …"), so the detach doesn't
stop its cleanup.

`phase-worktrees` makes its own worktrees with `git worktree add` at
`<repo>-worktrees/p<N>-<slug>`, so neither hook touches them. Its no-ticket
branch name `gsd/phase-<N>-<slug>` doesn't follow this convention.

### Naming

The environment can't be named: the app labels it with the repo name (from a
GitHub URL) or the folder name, here `demo`. `--name` only titles the session
a server opens at start, which we turn off, or the one session in session
mode. Session titles start as `<prefix>-<two random words>`. The prefix
defaults to the hostname and is settable; the words aren't.

**Decided 22 Oct:** the prefix defaults to the repo's path under `~/repos`,
overridable per repo at `rrc start`. A title would start as
`client-hugoboss-web-temporal-rabbit`.

**But it barely shows.** In the `idle-count` check, with the prefix set to
`client_hugoboss/web`, the session was listed as `OK`, the text of its first
reply. Claude Code replaces the generated title with one from the
conversation during the first turn, so the prefix is visible only until then.
Kept anyway (decided 22 Oct).

Two repos with the same folder name in different projects show identical
environment names; cloning one under a different folder name avoids that.

### Where `rrc` keeps its files

**Decided 22 Oct:** everything `rrc` writes lives with the skill, in
`~/.claude/skills/repo-remote-control/state/`:

- `state/config`: `ORCHESTRATOR_TMUX`, `CLONE_BASE`.
- `state/repos/<instance>.env`: per-repo flags (permission mode,
  `--no-create-session-in-dir`, the prefix override), written by `rrc start`
  and read by the unit as its `EnvironmentFile`.
- `state/logs/<instance>.log`: each server's output (`truncate:`).

The package kit's installer replaces the skill directory on every install and
upgrade, so `state/` relies on the kit's new convention: `place()` keeps
`state/` across installs, and `state/` is gitignored for `--link` installs.
That convention was agreed on 22 Oct and is in the kit's working tree,
unreleased; this package's `install.sh` needs updating to match. systemd only
reads units from `~/.config/systemd/user`, so the unit files are linked there
from the skill.

Dropped 22 Oct: a check of whether the environment ID survives a kill or
power loss. `rrc` reads the URL from the current output every time, so the
answer changes nothing it does.

## Operations

- **`remove`** lists worktrees and deletes them only with `--worktrees`.
- **`stop`** is weak on a box that rarely reboots, but you asked for all of
  them.

## What Claude Code does

All of this is from Claude Code 2.1.304's code, read out of the binary.

- **When a session ends normally,** the server keeps the worktree if it has
  any of: uncommitted changes, commits since it was made, or a moved
  checkout ("kept worktree … · uncommitted changes"). Otherwise it removes
  the worktree and deletes the branch Claude recorded. Idle and crashed
  sessions always keep theirs.
- **Periodic sweep.** During transcript cleanup, Claude removes worktrees
  named `bridge-*`, `agent-a…` and similar only when all of these hold:
  - it isn't the current session's worktree;
  - it's older than the cleanup cutoff;
  - `git status` is clean;
  - every commit on HEAD exists on a remote;
  - no live process holds its lock.
- **A missing recorded branch** only produces a logged `git branch -D` error.
  A renamed branch is never deleted by either cleanup.
- **Branch base:** the branch `origin/HEAD` points at, fetched if stale, or
  local HEAD if the fetch fails. Branches are created `--no-track`.

## Test results (Docker, 20 Oct 2026)

`test/docker/confirm.sh` runs Claude Code 2.1.304 in a container
(`rrcconfirm`) set up like the box, with a test repo `demo`. It checks
behaviour the design depends on; it doesn't test our code, which doesn't
exist yet. Evidence: `test/docker/results/20261020-232722/`.

| Check | What was done | Result |
| --- | --- | --- |
| untrusted-output | Server started in an untrusted repo | "Workspace not trusted" appears in the output. `start` can rely on it. |
| raw-output | Server left running 50s, output to a file | 700 bytes, then nothing; redraws only on change (`ESC[7A ESC[J`). The flood didn't happen while idle. |
| name-restart | `--name rrc-confirm-name`, then `systemctl restart` | Name appeared nowhere. Environment ID changed (`env_01RVx…` → `env_01MZP…`). The app showed one environment, `demo`, not two. |
| folder-served | Session mode in a repo with a server | Refused: "This folder is already served by a terminal `claude remote-control` on this device." |
| tmux-queue | Message typed into a busy session | Invalid test. Claude ran the `sleep` in the background, so the session wasn't busy. It does show `tmux send-keys` input gets answered. |

## Test results (Docker, 22 Oct 2026)

Claude Code 2.1.308: the container had updated itself from 2.1.304 before
`DISABLE_AUTOUPDATER=1` was added. `confirm.sh` was rewritten the same day:
checks that need you in the app now ask yes/no in the terminal and record the
answers. Evidence: `test/docker/results/20261022-120332/` (the app checks),
`20261022-130116/` (`sandbox-auto`), `20261022-131510/` (`sandbox-rrc`).

| Check | What was done | Result |
| --- | --- | --- |
| tmux-queue | Message typed while the session ran `timeout 45 tail -f /dev/null` in the foreground | Waited, answered after the first turn finished. |
| idle-count | Session opened and ended; prefix `client_hugoboss/web` | Capacity 0 → 1 → 0. Session title was `OK`, from the conversation, not the prefix. |
| sessionstart-detach | Stand-in hook detaches HEAD and deletes the generated branch | Fired in the worktree, in time; branch gone; unused worktree still removed at session end. |
| spawn-session | `--spawn session --name rrc-confirm-single --permission-mode plan` | One session, titled `rrc-confirm-single`; plan mode held; process exited when it ended. |
| sandbox-auto | bwrap; `claude -p`; server with sandbox + auto, auto only, sandbox only | bwrap runs; sandbox blocks writes outside the worktree in `-p` and server sessions; auto alone doesn't. |
| sandbox-rrc | Stand-in `rrc` run by a sandboxed `claude -p`, then with `excludedCommands: ["rrc"]` | Sandboxed: user bus, unit dir and `~/.claude.json` all blocked. Excluded: all three work. |

Two `sandbox-auto` runs earlier the same day failed: the server was `Ready`
but the session opened from the app never reached it (Capacity stayed 0), and
the app showed it disconnected. The first was the 70-second refusal (see
"Restarting"). The second used the server's own environment URL and had no
error in the server output; it was not run with the debug log, and the next
run, with identical settings, worked. Cause unknown.

The sandbox-only server variant's "permission mode is default?" question
failed only because a session in default mode can't see its own mode.

Run any check as `test/docker/confirm.sh <check>`; `start` restarts a stopped
container, `down` removes it.

## Still open

1. **Cloning from the box:** confirm `git@ssh.bitbucket.org` works with the
   box's key and the added host keys. Waits for the box.
2. **On the box, once it exists:** confirm its sandbox blocks `rrc` the way
   Docker's did, and that `excludedCommands` fixes it there too.

## Handed to the aws-workspace session for setup.sh

Sent to "AWS workspace handoff reconciliation" on 20 Oct. An earlier copy went
to the wrong session and expired undelivered.

1. `sandbox.enabled: true` in `~/.claude/settings.json` (merge, back up first).
2. Install `bubblewrap` and `socat`.
3. Add `ssh.bitbucket.org` host keys to `~/.ssh/known_hosts` from
   `https://bitbucket.org/site/ssh`.
4. Repoint existing `git@bitbucket.org:` remotes to `git@ssh.bitbucket.org:`.
5. `loginctl enable-linger`.
6. Keep the orchestrator in `orchestrator:0`, or set `ORCHESTRATOR_TMUX`.

Sent to `aws-workspace-62`, a local session, on 22 Oct ("AWS workspace
handoff reconciliation" was offline):

7. `"excludedCommands": ["rrc"]` in the sandbox settings, merged alongside
   item 1 (see "Sandbox").
8. Confirm cloning over `ssh.bitbucket.org` from the box (open item 1).

## Next steps

1. Build: `rrc`, the two unit templates, the `SessionStart` hook, the commit
   guard, the update watcher and path unit, `manifest.sh`, and the tests.
   Check during the build: whether a refused server exits with an error
   (see "Restarting"), and whether a path unit on `~/.local/bin/claude` fires
   when `claude` updates, since it's a symlink into a versions directory.
