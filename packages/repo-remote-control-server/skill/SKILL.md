---
name: repo-remote-control-server
description: Use when the user wants a repo on this machine permanently reachable from claude.ai or the Claude app — start, list, stop, restart or remove a repo's Claude Remote Control server, or clone a repo and serve it. Also use when a message starting "[rrcd]" arrives, which is the update watcher asking about servers still on an old claude. A single one-off session is repo-remote-control-session's (rrc session), not this.
allowed-tools:
  - Bash
  - Read
---

# repo-remote-control-server

Every repo that should stay reachable from claude.ai gets its own Claude
Remote Control server, a systemd user service that survives reboots. `rrcd`
does all of it. Do not reimplement its steps by hand: it trusts the repo,
writes the unit's settings, and reads the URL from the server's output the
same way every time.

```bash
rrcd start <dir> [--permission-mode <mode>] [--prefix <prefix>] [--create-session-in-dir]
rrcd clone <url-or-slug> [path] [--name <folder>]   # into ~/repos/[path]/<name>, then start
rrcd list
rrcd url <dir>
rrcd restart <dir>
rrcd stop <dir>
```

`rrcd --help` has every option. `<dir>` can be any directory inside the repo.
For one session rather than a server, use `rrc session <dir>` from
repo-remote-control-session.

## Run each rrcd command as one bare call

The installer lists `rrcd start *`, `rrcd clone *`, `rrcd list`,
`rrcd url *`, `rrcd restart *` and `rrcd stop *` in
`sandbox.excludedCommands`, so those run outside the sandbox, which they have
to. An entry matches a Bash call only when the whole call is that command:

- nothing chained before or after it: no `;`, `&&`, `||` or `|`
- no redirect, no `cd`, no `$(...)` anywhere in the call
- `rrcd` by name, never `~/.local/bin/rrcd`

Any of those keeps the call sandboxed, and it fails with "Read-only file
system" or "Failed to connect to bus". Read the exit code from the tool
result rather than echoing it.

## The user runs these, not you

`rrcd remove`, `rrcd restart-all`, `rrcd disable` and `rrcd teardown` are left
sandboxed on purpose: `remove --worktrees --force` deletes worktrees that
still hold work, and `restart-all` ends every open session on the machine. A
call from Claude fails. When one is needed, give the user the one-line
command to run in their own terminal.

## Give out the URL, never the name

`rrcd start`, `clone` and `restart` print the repo's root, then its URL. Give
the user that URL. Do not tell them to pick an environment by name in the app:
environments are named after the folder, two repos called `web` look the
same, and a stopped server's environment can stay listed under the same name.
A session opened in that one never starts and shows as disconnected.
`rrcd list` prints each server's current URL; it changes on every restart, so
never reuse an old one.

## Ask before anything that ends sessions

These end every open session in the server: `rrcd restart`, `rrcd stop`, and
`rrcd start` with a changed option; so do `rrcd restart-all`, `rrcd disable`
and `rrcd remove`, which the user runs. Check `rrcd list` for open sessions
first, and ask the user before running one on a server that has any.

## When rrcd stops and says to ask

- **Exit code 3: the sandbox is off.** `sandbox.enabled` is not true, so the
  server's sessions would run commands unsandboxed. Tell the user that, and
  ask. Only with their explicit yes, run the same command again with
  `--allow-unsandboxed`. Never add it yourself to get past the error.
- **"already served".** A server in that folder stopped less than about 70
  seconds ago, or one is still running. `rrcd start` waits it out on its own.
- **"no CLONE_BASE is set".** A slug needs a clone host for this machine.
  Ask the user for it, or for the full URL; do not guess a host.
- **"linger is off and could not be turned on".** Servers will stop when the
  user logs out. Give them `loginctl enable-linger <user>` to run in their own
  terminal.

## "[rrcd]" messages

When `claude` updates, idle servers restart on their own. Servers with open
sessions keep the old version, and the watcher types a message starting
`[rrcd] claude was updated to …` into this pane, naming them. Ask the user
straight away which of those to restart, then run `rrcd restart <dir>` for
each. If they say all, `rrcd restart-all` is theirs to run.

## Sessions in a server start without a branch

Each server session works in its own git worktree,
`<repo>/.claude/worktrees/bridge-<id>`. A hook detaches it from the branch
Claude generated and tells the session to create its own,
`<type>/<KEY>-<description>`; another hook blocks commits until it has. That
happens inside those sessions, not here.

## If rrcd fails on the sandbox anyway

"Failed to connect to bus", "Read-only file system" or "Device or resource
busy" from a bare call to one of the excluded commands means its entry is
missing from `sandbox.excludedCommands`: reinstalling the package adds it.
"needs rrc from repo-remote-control-session" means that package is not
installed. Say which, and do not retry with the sandbox disabled.
