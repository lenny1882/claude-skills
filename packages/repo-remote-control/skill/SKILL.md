---
name: repo-remote-control
description: Use when the user wants to reach a repo on this machine from claude.ai or the Claude app — start, list, stop, restart or remove a repo's Claude Remote Control server, clone a repo and serve it, or open a single one-off session in a repo. Also use when a message starting "[rrc]" arrives, which is the update watcher asking about servers still on an old claude.
allowed-tools:
  - Bash
  - Read
---

# repo-remote-control

Every repo that should be reachable from claude.ai gets its own Claude Remote
Control server, a systemd user service that survives reboots. `rrc` does all
of it. Do not reimplement its steps by hand: it trusts the repo, writes the
unit's settings, and reads the URL from the server's output the same way every
time.

```bash
rrc start <dir> [--permission-mode <mode>] [--prefix <prefix>] [--create-session-in-dir]
rrc clone <url-or-slug> [path] [--name <folder>]   # into ~/repos/[path]/<name>, then start
rrc session <dir> [--name <title>]                 # one session, not a server
rrc list
rrc restart <dir> | rrc restart-all
rrc stop <dir> | rrc disable <dir>
rrc remove <dir> [--worktrees [--force]]
```

`rrc --help` has every option. `<dir>` can be any directory inside the repo.

## Give out the URL, never the name

`rrc start`, `clone`, `session` and `restart` print the repo's root, then its
URL. Give the user that URL. Do not tell them to pick an environment by name in
the app: environments are named after the folder, two repos called `web` look
the same, and a stopped server's environment can stay listed under the same
name. A session opened in that one never starts and shows as disconnected.
`rrc list` prints each server's current URL; it changes on every restart, so
never reuse an old one.

## Ask before anything that ends sessions

These end every open session in the server: `rrc restart`, `rrc restart-all`,
`rrc stop`, `rrc disable`, `rrc remove`, and `rrc start` with a changed option.
Check `rrc list` for open sessions first, and ask the user before running one
on a server that has any.

## When rrc stops and says to ask

- **Exit code 3: the sandbox is off.** `sandbox.enabled` is not true, so the
  server's sessions would run commands unsandboxed. Tell the user that, and
  ask. Only with their explicit yes, run the same command again with
  `--allow-unsandboxed`. Never add it yourself to get past the error.
- **"already served".** A server in that folder stopped less than about 70
  seconds ago, or one is still running. `rrc start` waits it out on its own;
  `rrc session` fails and says to try again in a minute.
- **`rrc session` in a repo with a server** is refused, because Claude refuses
  a single session beside a server. Give the user the server's URL from the
  error instead: they open a new session there.

## "[rrc]" messages

When `claude` updates, idle servers restart on their own. Servers with open
sessions keep the old version, and the watcher types a message starting
`[rrc] claude was updated to …` into this pane, naming them. Ask the user
straight away which of those to restart, then run `rrc restart <dir>` for each,
or `rrc restart-all` if they say all.

## Sessions in a server start without a branch

Each server session works in its own git worktree,
`<repo>/.claude/worktrees/bridge-<id>`. A hook detaches it from the branch
Claude generated and tells the session to create its own,
`<type>/<KEY>-<description>`; another hook blocks commits until it has. That
happens inside those sessions, not here.

## The part that is easy to get wrong

`rrc` has to run outside Claude's sandbox: it uses the user bus, writes to
`~/.config/systemd/user` and edits `~/.claude.json`, and the sandbox blocks all
three. It is listed in `sandbox.excludedCommands` for that reason. If an `rrc`
command fails with "Failed to connect to bus", "Read-only file system" or
"Device or resource busy", that exclusion is missing: say so, and do not retry
with the sandbox disabled.
