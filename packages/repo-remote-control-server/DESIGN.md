# repo-remote-control-server — design notes

These began as the notes for `repo-remote-control`, one package with one
command, `rrc`. On 29 Oct 2026 it was split in two; the section below says
how. Everything after it is the original record, with `rrc start`, `rrc list`
and the other server commands now `rrcd …`, and the state now under
`~/.claude/skills/repo-remote-control-server/state/`.

## The split (29 Oct 2026)

`rrc session` failed on a machine that had the sandbox on but had never run
the AWS workspace's `setup.sh`: nothing had added `rrc` to
`sandbox.excludedCommands`, so the first `mkdir` in the skill's `state/` hit
the sandbox. A package has to carry everything it needs to install and run on
any machine, not rely on another project's setup script. And a machine that
only wants one-off sessions was getting servers' hooks, units, update watcher
and linger with them.

- **Two packages.** `repo-remote-control-session` is `rrc`: `session`,
  `list`, `teardown`, and no hooks. In 1.0.0 each session was an
  `rrc-session@` unit; from 1.0.1 it is a detached process with a PID file
  (see "Session mode"). `repo-remote-control-server` is `rrcd`: start,
  clone, list, url, restart, restart-all, stop, disable, remove, tidy,
  on-update, serve and teardown, the `rrc-server@` and `rrc-update` units,
  and both hooks. There is no migration from 1.1.0: it was installed on one
  machine only, which was uninstalled and given the new packages fresh
  (decided 2 Nov, item 9).
- **Shared code once.** Finding the repo, trust, locking and reading the
  output are in the session package's `skill/lib/rrc-lib.sh`, which `rrc`
  and `rrcd` both source. `rrcd` loads it from the session skill's directory,
  not `PATH`, and checks `RRC_LIB_VERSION` (changed 2 Nov; see item 2 below).
  The server install's `verify_probe` fails without it. `rrc session`
  asks `rrcd url` for the server's URL when it is refused beside one.
- **Each install adds its own exclusions.** An entry with no wildcard matches
  only the bare command, so `["rrc"]` (planned below, and what the 22 Oct
  Docker check passed with, because it called a bare `rrc`) would have left
  every real call sandboxed. The session package adds `"rrc *"`. The server
  package adds `rrcd start *`, `rrcd clone *`, `rrcd list`,
  `rrcd restart *` and `rrcd stop *` (`rrcd url *` until 2 Nov; see item 3). `remove`, `restart-all`, `disable` and
  `teardown` stay sandboxed, so they fail from Claude and the user runs them.
  `rrcd restart *` does not match `restart-all`: the space before `*` makes
  it a whole word. Each package's `pre_uninstall` takes its own entries out,
  because `uninstall.sh` only knows about hooks; `--keep-settings` skips it.
- **Linger** is turned on by the server package's installer, in
  `manifest.sh`'s `post_install` (kit 1.3.0), as agreed. The split first
  built it into every `rrcd start`, because the kit then had no step after
  installing; changed 2 Nov (item 1).
- **No built-in clone host.** `CLONE_BASE` used to default to
  `git@ssh.bitbucket.org:<workspace>/`. A slug now needs it set in `state/config`.
- **Messages** from the update watcher start `[rrcd]`.

### Decided without asking, then put to the user (2 Nov)

The build differed from what was agreed in these places. Each was put to the
user one at a time on 2 Nov, and its decision follows it. The Docker run
(item 8) passed on 2 Nov, linger at install included; see
"Test results (Docker, 2 Nov 2026)".

1. **Linger.** Agreed: the installer checks `loginctl show-user -p Linger`
   and runs `loginctl enable-linger`. Built: `ensureLinger` in every
   `rrcd start` and `rrcd clone`, because `manifest.sh` has no post-install
   step (`verify_probe` also runs in the tests' throwaway-`HOME` installs,
   and `settings_merge` runs on `--dry-run`). A Claude-run `rrcd start`
   turns linger on, and the user learns of it from one line of output.

   **Decided 2 Nov: the installer, as agreed.** Checking only and leaving
   the user to run `enable-linger` was ruled out: on a remote box nothing
   starts at boot until someone logs in. Built on kit 1.3.0, which added a
   `post_install` hook point, skipped on `--dry-run` and when
   `KIT_SKIP_MACHINE_HOOKS=1` (the tests set it). `manifest.sh`'s
   `post_install` turns linger on, says so, and fails the install if it
   can't; `ensureLinger` is gone from `rrcd`. Kit 1.3.0 also skips
   `pre_uninstall` in the tests, so they call `strip_excluded` on its own.
2. **`rrcd` sources `rrc`.** Agreed: `rrcd` calls `rrc` on `PATH` as a
   command. Built: `rrcd` sources it as a library, so the two must stay in
   step function by function, and an `rrc` without the sourcing guard (1.1.0
   from `repo-remote-control`) runs its `main` inside `rrcd`.

   **Decided 2 Nov: a library of its own.** Why it was built differently: the
   shared parts were internal functions, and calling `rrc` meant adding about
   15 subcommands; sourcing `rrc` avoided that work. Calling `rrc` was then
   ruled out on its own costs: `"rrc *"` would let any Claude session run
   those subcommands unsandboxed, trust edits included, and the lock `rrcd
   start` holds across several steps cannot be held across separate `rrc`
   processes. Sourcing `rrc` with a version check was ruled out because the
   old guardless `rrc` runs its commands while being sourced, before any
   check after it. Built: the shared functions and settings are in the
   session package's `skill/lib/rrc-lib.sh`, which defines things and runs
   nothing. `rrc` sources it from its own skill; `rrcd` from the session
   skill's directory, never `PATH`, then refuses any `RRC_LIB_VERSION` but the
   one it needs. `RRCD_RRC` became `RRCD_RRC_LIB`.
3. **`rrcd url` and its `rrcd url *` exclusion.** Not discussed. Added so
   `rrc session` can put the server's URL in its "has a server" refusal.

   **Decided 2 Nov: keep `rrcd url`, drop its exclusion.** Why it was built
   this way: the server's output, which holds its URL, moved to the server
   package's state directory, so `rrc` could no longer read it, and a command
   and an exclusion were added without asking. The command stays, so only
   the server package reads its own files. The exclusion goes: `rrc` runs
   outside the sandbox through `"rrc *"`, and the `rrcd url` it starts runs
   outside with it; Claude gets URLs from `rrcd list`. `rrcd url` is off
   SKILL.md's command list, because sandboxed it would report a running
   server as "not running".
4. **Separate locks.** Not discussed. Each package locks its own
   `state/.lock`, so an `rrc session` and an `rrcd start` running at once can
   race on `~/.claude.json`. "Shared code once" above says "the lock", which
   is wrong on this.

   **Decided 2 Nov: a second lock, shared, around the `~/.claude.json` edit
   only.** Why it was built this way: the lock is a file in the package's
   state directory, so splitting the state directories split the lock, and
   nobody noticed. Each package keeps its own lock for its own state.
   `editClaudeJson` in the library also takes `~/.claude/.rrc-claude-json.lock`
   with `flock` for the backup, `jq` and `mv` (about 40 ms) and closes it
   straight after. `flock` is released by the kernel when the process exits,
   however it exits, so a leftover file never blocks anyone. Taken after the
   package lock, with nothing else taken while held, so no deadlock. Rejected:
   one lock for everything, which would make `rrc session` wait behind an
   `rrcd start` waiting up to 2 minutes for its URL and fail at the 60 s
   timeout; and a write, settle, check, random-backoff retry, which costs a
   wait on every edit to detect a clash the lock prevents. Tested: two
   writers trusting 15 repos each at once keep 30 of 30 keys with the lock,
   15 or 16 of 30 without it.
5. **The uninstall strip ignores the confirm prompt.** Not discussed.
   `pre_uninstall` strips the exclusions before `uninstall.sh` asks
   "Remove … entries?", so answering no still strips them. Only
   `--keep-settings` stops it.

   **Decided 2 Nov: keep as built.** Why it was built this way: nobody
   checked that `pre_uninstall` runs before the settings question. It has no
   practical effect: uninstalling removes what installing added, and a
   reinstall after answering no adds the same entries back. Rejected: a
   second question in each package, and a kit `settings_unmerge` hook point
   under the kit's question, each only to make "no" keep entries that do
   nothing once the package is gone.
6. **`rrc list` no longer shows servers.** Not discussed. It shows one-off
   sessions only; servers are `rrcd list`.

   **Decided 2 Nov: keep as built.** Why it was built this way: servers and
   their state moved to the server package, and nobody weighed what each
   list should show. No program runs either list; a person or a Claude does,
   and each knows which kind it is asking about. Both skill descriptions name
   the other package, so a Claude asked about everything runs both.
   Rejected: `rrcd list` running `rrc list`, `rrc list` running `rrcd list`,
   and a pointer line in `rrc list`.
7. **Hooks renamed.** Not discussed. `repo-remote-control-*.sh` became
   `repo-remote-control-server-*.sh`, so the `settings.json` hook entries
   change path.

   **Decided 2 Nov: keep as built.** Why it was built this way: the kit names
   installed scripts after their package, and the build followed it without
   saying. It costs nothing extra: the settings.json paths change because the
   package directory was renamed, which would have happened with the old
   script names too. The old uninstaller matches `repo-remote-control` as a
   whole word, so it leaves the new entries alone.

8. **Docker scripts changed, never run.** Not discussed. `confirm.sh`'s
   `sandbox-rrc` now uses `"rrc *"` and calls `rrc session`;
   `integration.sh` installs both packages and uses `rrcd`. Neither has run.

   **Decided 2 Nov: run them, all of them, once the other open items are
   settled.** Why they were not run: Claude's Bash tool cannot reach the
   Docker socket, and the user was not asked. Since then the shared library,
   linger at install, kit 1.3.0, the shared ~/.claude.json lock and the
   dropped `rrcd url` exclusion have also not met real systemd or Claude
   Code. Both scripts first get their full output logged to
   `results/<time>/run.log`. Then `confirm.sh sandbox-rrc`, `integration.sh`
   and `integration.sh --app`, in the user's own terminal.

9. **Smaller changes.** "no environment URL" became "no URL"; the
   migration steps in README.md were written without being discussed; the
   split was staged in git without being asked.

   **Decided 2 Nov: "no URL" stays.** Why it changed: the wait loop moved
   into the shared code, which also waits for a one-off session's
   `https://claude.ai/code/session_…` URL, and that is not an environment
   URL. The last error and the output path in the same message say why it
   failed, so naming the kind of URL would add nothing.

   **Decided 2 Nov: no migration steps.** 1.1.0 is installed on one machine
   only, and that one gets uninstalled and the new packages installed fresh.
   The paragraphs on moving from 1.1.0 are gone from both READMEs.

   **Decided 2 Nov: nothing changes in git.** The staged split became
   `3d1308b` and is pushed. Its message's lines on linger at the first start
   and the `rrcd url *` exclusion are out of date; `455e09c` and `21c5d80`
   say what replaced them.

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

The original brief is the handoff from the infra-box session. Its tested
unit file and test script are in
`~/scratch/infra-box/scripts/remote-control-systemd-test.sh`, and
the write-up is item 12 of `infra-box/planning/BEFORE-STARTING.md`.

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
  setup.sh's job. (Superseded 29 Oct: the first `rrcd start` turns it on.)
- **Unit template** as tested by the infra-box session.
  `WorkingDirectory=/%I` needs the leading slash.

  ```
  [Unit]
  Description=Claude Remote Control server in /%I

  [Service]
  WorkingDirectory=/%I
  ExecStart=%h/.local/bin/claude remote-control --spawn worktree
  Restart=always
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
  entry. (Superseded 29 Oct: each package's installer adds its own entries,
  with a wildcard; see "The split".)

### Restarting after a `claude` update

A running server keeps the old binary until it restarts, and restarting ends
the sessions open in it.

- A systemd path unit watches `~/.local/bin`, the directory holding the
  `claude` symlink, and `~/.local/share/claude/versions`. Not the symlink
  itself: inotify follows it, so the watch sits on the old binary and
  relinking never fires it (integration test, 22 Oct).
- When it changes, idle servers (0 open sessions) restart automatically.
- For servers with sessions open, the watcher types a message into the
  orchestrator's tmux pane, and the orchestrator asks you straight away.
- `rrc restart-all` on request restarts everything.
- The pane is `ORCHESTRATOR_TMUX` in `state/config` (see "Where `rrc` keeps
  its files"),
  default `orchestrator:0`. The infra-box handoff starts the orchestrator
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

  **Changed 26 Oct: `Restart=always`.** The infra-box session cut a
  server's network for 15 minutes (`remote-control-systemd-test.sh
  offline`). After "disconnected 9m 54s" the server exited with status 0
  (`Result=success`), so `Restart=on-failure` never restarted it, and it was
  still down after the network came back. `Restart=always` covers that and
  still retries a refused server; `systemctl stop`, which `rrc stop` uses, is
  never followed by a restart. On that exit the server released its
  worktree locks, removed worktrees without changes, and kept one with
  uncommitted changes ("kept worktree … · uncommitted changes").

  **Added 26 Oct: `rrc tidy`, as the unit's `ExecStartPre`.** A server killed
  by a reboot gets no such exit. Its sessions' worktrees stay locked with
  `claude agent bridge-… (pid N start T)`, naming the dead server, and
  `git worktree prune` skips them, so every Sunday maintenance reboot would
  leave a worktree and a `worktree-bridge-*` branch per open session. Before
  each start, `tidy` releases a lock whose PID isn't running with start time
  T (field 22 of `/proc/PID/stat`, so a PID reused after the reboot doesn't
  count), removes a server worktree with no uncommitted changes and no
  commits that no other branch or remote has, deletes its generated branch,
  and keeps the rest, unlocked. Another tool's lock is left alone. It logs to
  `state/logs/tidy.log`, because the unit's output file is emptied for the
  server. It takes no `rrc` lock: `rrc start` holds that while it waits for
  this very server. The `-` in `ExecStartPre=-` means a failed tidy never
  stops the server starting.

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

**Decided and built 2 Nov: no systemd for a session.** The unit only
exists so the `claude` process outlives the `rrc` call that started it, and
`setsid nohup` does that (see "Detached sessions (this machine, 2 Nov
2026)"). Both of the first real failures were in the unit file. As proposed:

- **`rrc session <dir>`** keeps finding the root, the server check
  (`systemctl --user is-active rrc-server@…`, read-only), the sandbox check
  and the trust. Then it empties `state/logs/<instance>.session.log` and, in
  the root, runs `setsid nohup claude remote-control --spawn session <flags>`
  with output to that log and stdin from `/dev/null`, and writes the PID to
  `state/sessions/<instance>.pid`. The flags are passed as an array, so
  `--name` can keep its spaces.
- **Waiting for the URL** works as before, but "failed" means the PID is gone
  rather than the unit failing, and the "Workspace not trusted" retry starts
  the process again rather than the unit. No URL in time and that retry
  each stop the process first, so none is left holding the folder.
  "already served" stops it too, then starts again every 15 seconds for up
  to 300: a folder stays refused for 131 to 194 seconds after its last
  session stops (see "Test results (Docker, 2 Nov 2026, sessions without
  systemd)"), not the 70 measured for servers. SKILL.md gives the call a
  600000 ms timeout to match. It is `waitForSession` in `rrc`, not the library: only `rrc` needs
  it, and `rrcd` keeps `waitForUrl`, so `RRC_LIB_VERSION` stays 1.
- **A PID counts as a session** only while it is alive, its
  `/proc/<pid>/cwd` is the root and its command line has `remote-control`,
  so a reused PID is never taken for one. That check also replaces
  "is a session already running in this repo".
- **`rrc list`** prints each live one with its URL from the log, and removes
  the PID files of dead ones.
- **`rrc teardown`** sends each live one `TERM`, then `KILL` after 10
  seconds, and removes the PID files. It also unlinks an
  `rrc-session@.service` left by 1.0.0 and resets it, once.
- **Gone:** `systemd/rrc-session@.service`, `ensureUnits`, `sessionUnitOf`,
  the `.env` files and the `daemon-reload`.
- **Kept:** `"rrc *"` in `sandbox.excludedCommands`. `rrc` still writes
  `~/.claude.json`, and `claude` has to start outside the sandbox: a
  sandboxed call has its own PID namespace, so a child left behind dies with
  it.
- **What it gives up:** a reboot ends the session, as it does now; nothing
  can restart a crashed one, as now (`Restart=no`).
- **Tests:** a stand-in `claude` that prints a session URL and waits, for
  start, an already-running session, a dead PID, a reused PID, the pointer,
  list and teardown; one checks the lock fds are closed in the session,
  and fails if they are not. `integration.sh` starts a session in a repo
  with hyphens in its path, checks it outlives `rrc` with no unit, stops it,
  and starts a second one, which must have a new URL; with `--app`, it ends
  sessions in the app in between, which is what made the 404.
- **A folder's `bridge-pointer.json`** (see "Detached sessions"). Decided
  2 Nov: `rrc session` deletes `~/.claude/projects/<folder>/bridge-pointer.json`
  before a start when no live process owns it (its `pid` is dead or not
  `remote-control`), so every start opens a new session. The folder name is
  the root with every character other than a letter or digit turned into
  `-`, as Claude Code names it (`…/repo/.claude/worktrees/x` becomes
  `-…-repo--claude-worktrees-x`). The
  Docker check opens two sessions in a row in one folder, ending the first
  in between, so a change to the file's name or place fails there.

### Cloning

- `rrc clone <url-or-slug> [path]`.
- A full URL from any host (Bitbucket, GitHub) is used as given.
- A bare slug is expanded with `CLONE_BASE`, default
  `git@ssh.bitbucket.org:<workspace>/`.
- `[path]` is relative to `~/repos` (for example `client_x`, matching
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
`feature/ABC-456-order-totals`") and the session runs `git switch` to it
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
`client-x-web-temporal-rabbit`.

**But it barely shows.** In the `idle-count` check, with the prefix set to
`client_x/web`, the session was listed as `OK`, the text of its first
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
| name-restart | `--name rrc-confirm-name`, then `systemctl restart` | Name appeared nowhere. Environment ID changed (`env_01AAA…` → `env_01BBB…`). The app showed one environment, `demo`, not two. |
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
| idle-count | Session opened and ended; prefix `client_x/web` | Capacity 0 → 1 → 0. Session title was `OK`, from the conversation, not the prefix. |
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

## Test results (Docker, 2 Nov 2026)

Claude Code 2.1.308. The split packages, with the shared library, linger at
install, kit 1.3.0, the shared `~/.claude.json` lock and no `rrcd url *`
exclusion: `confirm.sh sandbox-rrc`, then `integration.sh --app`, which
installs both packages from the checkout into the box. Everything passed.
Evidence: `test/docker/results/20261102-194809/` (`run.log` has the whole
run).

| Check | What was done | Result |
| --- | --- | --- |
| sandbox-rrc | A sandboxed `claude -p` runs the bare call `rrc session /home/dev/repos/demo`, then with `excludedCommands: ["rrc *"]` | Sandboxed: user bus, unit dir and `~/.claude.json` all blocked. Excluded: all three work. |
| install | Session package, then server package, `install.sh --yes` | Both probes passed; each added its own `excludedCommands` entries. |
| start, start-again, list | `rrcd start` on two repos, again on one, then `rrcd list` | Root and environment URL printed; unit active and enabled; watcher enabled; second start gave the same URL without restarting; list showed both idle with URLs. |
| session-refused | `rrc session` in a repo with a server | Refused, with the server's URL from `rrcd url`, which ran without an exclusion of its own. |
| restart | `rrcd restart` | New URL. |
| update | `claude install` 2.1.308 → 2.1.305 | The path unit fired, the idle server restarted on the new binary, the busy one kept running and the orchestrator pane got the `[rrcd]` message. |
| hook-detached, guard-blocked | A session opened from the app in a server | HEAD detached with no branch name; `git commit` blocked with "Create the task's branch first". |
| remove, teardown | `rrcd remove`, then `rrcd teardown` and `rrc teardown` | Server disabled and its trust cleared; no `rrc-*` unit left loaded. |

The box's user already had linger, so that run's `post_install` took its
already-on path. `integration.sh` now turns linger off before the install,
and a `linger` check passes only if the install printed "turned on linger"
and `loginctl` then says `Linger=yes`. A user turns on their own linger
through polkit, which the box did not have, so the script installs polkitd,
reloads systemd and D-Bus and starts polkit first.

- `20261102-203153/`: polkitd installed but not yet known to systemd, so
  `loginctl enable-linger dev` failed with "Connection timed out".
  `post_install` warned, gave the command to run, and the install failed, as
  designed. The script did not reload systemd and D-Bus yet.
- `20261102-203404/`: with polkit running, the install printed "turned on
  linger for dev" and `linger` passed, then every check without the app
  passed again.

Not covered: two writers to `~/.claude.json` at once; that is covered only
by the session package's tests.

## The server unit on systemd 245 (2 Nov 2026)

`rrc-server@.service` had both of the session unit's faults. Fixed 2 Nov:
the unit runs `rrcd serve "/%I"`, which finds the repo's `.env` and output
file from the path itself, empties the output, and `exec`s
`claude remote-control --spawn worktree` with the flags, its output going
there, so the unit's MainPID is still claude's for the update watcher. No
`EnvironmentFile=`, no `StandardOutput=`, and no `%i` anywhere in the unit.
`integration.sh`'s second server is now `client-x/my-web`, hyphens and all.

## Detached sessions (this machine, 2 Nov 2026)

This machine runs Ubuntu 20.04 with systemd 245; the Docker box is 24.04
with systemd 255.

- **`rrc session ~/infra-box` failed**
  (session 1.0.0, installed from the release). systemd failed
  `rrc-session@mnt-sda-Development-github\x2dlenny1882-aws\x2dworkspace.service`
  with result "resources". The journal had two causes, both in the unit file
  and both in `rrc-server@.service` too:
  - "Failed to load environment files: No such file or directory". The file
    exists as `state/sessions/mnt-sda-Development-github\x2dlenny1882-aws\x2dworkspace.env`,
    but `%i.env` resolved to another name. The `\x2d` is an escaped hyphen;
    no Docker repo had a hyphen in its path. Whether systemd 255 does the
    same is not known.
  - "Failed to parse output specifier, ignoring: truncate:…".
    `StandardOutput=truncate:` arrived in systemd 248, so on 245 the output
    goes to the journal and `rrc` would never see the URL.
  1.1.0 had the same unit.
- **A `setsid nohup` process outlives the call that started it.** A `bash`
  loop writing a timestamp every 5 seconds, started with `!` (unsandboxed,
  the same path as an excluded `rrc`), wrote all 24 after the call returned.
- **A real detached session works.** `setsid nohup claude remote-control
  --spawn session --permission-mode auto`, started with `!` in
  `infra-box`, wrote its `https://claude.ai/code/session_…` URL to a
  plain log file. Opened from claude.ai after the call returned, it answered
  with the right directory and branch. Ended in the app, its process exited.
- **Logout:** `/etc/systemd/logind.conf` leaves `KillUserProcesses` at its
  default, `no`, with no override, so an SSH logout does not kill it either.
- **Quitting Claude Code does not end it.** Started with `!` from a second
  Claude Code in `infra-box`, the process (PID 497454) was still running
  8 minutes later, after that Claude Code had been quit.
- **A second session in the same folder resumes the first, and fails if it
  was ended in the app.** `claude` keeps each folder's last Remote Control
  session in `~/.claude/projects/<folder>/bridge-pointer.json`
  (`{"sessionId":"session_…","environmentId":"env_…","source":"standalone","pid":…,"procStart":"…"}`).
  When a session ends, the pointer stays ("Resume this session by running
  `claude remote-control --continue`"). The next `--spawn session` in that
  folder printed the same `session_01EXAMPLE3` URL, logged
  "CCR v2 worker registration failed … Request failed with status code 404",
  and stayed running with the folder held: the URL showed "this session
  couldn't be found", and a third start was refused as "already served".
  `rrc session` hits this whichever way it starts `claude`; the 22 Oct
  Docker check opened one session per folder, so never saw it. The file is
  Claude Code's own and undocumented.

## Test results (Docker, 2 Nov 2026, sessions without systemd)

Both packages as built that evening, unreleased, from the checkout:
`rrc session` as a `setsid` process with a PID file and the pointer
cleared, `rrc-server@.service` running `rrcd serve "/%I"`, and the second
server at `client-x/my-web`. Claude Code 2.1.305.

Three runs failed on the script, not the packages:

- `20261102-224149`: the second server's setup made its origin only when
  the repo was missing. `origin/web.git` was left from runs that used
  `client_x/web`, with another history, so the push was rejected, the
  script stopped, and nothing it had started was torn down.
- `20261102-224157`: the second session in `one-off-x` was refused as
  "already served" 75 seconds after `rrc teardown`. The script waited a
  fixed 75, from the server figure.
- `20261102-224626`: `rrcd start` failed with "Transport endpoint is not
  connected". After linger came back on, the script waited only for the
  user bus socket, which was left from the instance linger-off stopped.

`integration.sh` since clears what earlier runs left (both teardowns, any
`claude remote-control`, its repos, origin and state), does the same on
exit however it exits, and waits for the user's systemd to answer
`running` or `degraded`.

Two full runs with `--app` then passed every check, 27 of 27:
`20261102-224852`, with the script retrying while the folder was refused,
and `20261102-231228`, with `rrc session` waiting it out itself.

| What | Result |
| --- | --- |
| Server checks with hyphens in the path (`client-x/my-web`) | start, list, restart, the update watcher, hooks and remove all passed |
| `rrc session` in `one-off-x` | URL printed; process alive after `rrc` returned; no unit linked; listed; stopped by teardown |
| A second session after `rrc teardown` | a new URL, not the last one |
| A session ended in the app | its process exited; the next session got a new URL and answered, rather than "this session couldn't be found" |
| How long a folder stays refused after its last session stops | after `rrc teardown`: 179 s, then 194 s; after ending it in the app: 148 s, then 131 s; leftovers killed by the cleanup: 35 s |

So `rrc session` waits up to 300 seconds, raised from 240 after the 194.

## The servers' PATH (9 Nov 2026)

2.0.2 put `Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin` in
the unit so sessions could run `rrcd` by name (infra-box, 3 Nov). systemd
can't expand `$PATH` in `Environment=`, so that replaced the user manager's
PATH: no `/usr/sbin`, `/sbin` or `/snap/bin`, and nothing from `~/.profile`
or `~/.bashrc` (nvm's node, SDKs, asdf shims) for the servers' sessions or
anything they start. Changed, not yet released: the line is gone, and
`rrcd serve` runs `bash -l -i` once per start and takes its PATH, with
`~/.local/bin` first. Considered and not taken: a fixed list of directories
in `state/config` (kept up by hand), the caller's PATH stored at
`rrcd start` (stale after `nvm` changes the default, and empty from cron),
and `EnvironmentFile=` or drop-ins (systemd replaces `PATH`, never adds to
it, and runs no shell code). With this machine's `.bashrc` the shell took
0.1 s. BACKLOG.md item 1 has what aws-workspace has to change.

Docker, 9 Nov, with this change: `sandbox-rrc` passed, `integration.sh
--app` passed 27 of 27, and a running server's `/proc/<pid>/environ` had
`~/.local/bin` first, a line added below `.bashrc`'s interactive check,
`/usr/sbin`, and `rrcd` found by name. It also had `~/.local/bin` three
times (`rrcd serve`, the box user's `.profile`, and the shell); `rrcd serve`
now drops repeats, keeping each directory at its first place.

## Still open

1. **The login-shell PATH:** passed in Docker 9 Nov; the release and the
   second message to aws-workspace are still to do (BACKLOG.md item 1).

Cloning over `git@ssh.bitbucket.org` from the box, and the sandbox blocking
`rrcd` there with the installers' `excludedCommands` fixing it, are tests on
the AWS WorkSpace: aws-workspace's REMAINING-TESTS.md item 15 has them.

repo-remote-control 1.1.0 is installed only on the user's own machine, which
gets it uninstalled and the new packages installed fresh (decided 2 Nov).

## Handed to the infra-box session for setup.sh

Sent to "AWS workspace handoff reconciliation" on 20 Oct. An earlier copy went
to the wrong session and expired undelivered.

1. `sandbox.enabled: true` in `~/.claude/settings.json` (merge, back up first).
2. Install `bubblewrap` and `socat`.
3. Add `ssh.bitbucket.org` host keys to `~/.ssh/known_hosts` from
   `https://bitbucket.org/site/ssh`.
4. Repoint existing `git@bitbucket.org:` remotes to `git@ssh.bitbucket.org:`.
5. `loginctl enable-linger`.
6. Keep the orchestrator in `orchestrator:0`, or set `ORCHESTRATOR_TMUX`.

Sent to `infra-box-62`, a local session, on 22 Oct ("AWS workspace
handoff reconciliation" was offline):

7. `"excludedCommands": ["rrc"]` in the sandbox settings, merged alongside
   item 1 (see "Sandbox"). No longer needed from setup.sh: the installers add
   their own, and `["rrc"]` would not have matched a call with arguments.
8. Confirm cloning over `ssh.bitbucket.org` from the box (now aws-workspace's
   REMAINING-TESTS.md item 15).

## Build status (22 Oct)

The single `repo-remote-control` package, before the split; kept as the
record of what was decided while building it.

Built and committed, with tests (`test/run-tests.sh`): `rrc` start, list,
stop, disable, remove, clone, session, restart, restart-all, on-update and
teardown; the server, session and update-watcher units; the `SessionStart`
hook and the commit guard; `SKILL.md` and the README. Decided while building:

- `rrc clone --name <folder>` picks the folder name, and clone warns when
  another repo under `~/repos` has the same folder name.
- `rrc session --name` titles are made one argument: spaces become hyphens.
  Since session 1.0.1 they keep their spaces: the flags go to `claude` as an
  array, not through a unit's `$RRC_ARGS`.
- `rrc restart <dir>` restarts one server; the `[rrc]` message from the
  update watcher points at it and at `restart-all`.
- `rrc teardown` undoes everything in systemd. `uninstall.sh` runs it through
  `manifest.sh`'s `pre_uninstall` before removing anything, since kit v1.2.1.
  The request to the package-kit session was not delivered: that session had
  ended.

## Done by 22 Oct

Done 22 Oct: `confirm.sh refused-exit` passed (a refused server exits with
status 1, so `Restart=on-failure` retries it), and `integration.sh` passed all
13 checks, the update watcher among them once it watched `~/.local/bin`.
`integration.sh --app` then passed all 16: in a real server session the
`SessionStart` hook detached HEAD and the commit guard blocked a commit, and
a busy server was left running while the orchestrator pane got the `[rrc]`
message. The package was then upgraded to kit v1.2.1, whose `uninstall.sh`
runs `pre_uninstall`, so uninstalling runs `rrc teardown` first.

What is still to do is under "Still open".
