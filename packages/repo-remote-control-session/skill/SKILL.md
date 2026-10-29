---
name: repo-remote-control-session
description: Use when the user wants a single one-off Claude Remote Control session in a repo on this machine, to open from claude.ai or the Claude app — "open a session in X", "start a remote session in X" — or asks which one-off sessions are running. Not for servers that survive reboots; those are repo-remote-control-server's.
allowed-tools:
  - Bash
  - Read
---

# repo-remote-control-session

`rrc session` opens one Claude Remote Control session in a repo, as a systemd
user unit, and prints its URL. The session ends when the conversation does
and never comes back at boot. Do not reimplement its steps by hand: it trusts
the repo, writes the unit's settings, and reads the URL from the session's
output the same way every time.

```bash
rrc session <dir> [--name <title>] [--permission-mode <mode>]
rrc list
```

`rrc --help` has every option. `<dir>` can be any directory inside the repo.
Find the repo on this machine yourself before asking the user where it is.

## Run each rrc command as one bare call

The installer lists `rrc *` in `sandbox.excludedCommands`, so `rrc` runs
outside the sandbox, which it has to. That entry matches a Bash call only when
the whole call is `rrc …`:

- nothing chained before or after it: no `;`, `&&`, `||` or `|`
- no redirect, no `cd`, no `$(...)` anywhere in the call
- `rrc` by name, never `~/.local/bin/rrc`

Any of those keeps the call sandboxed, and `rrc` fails with "Read-only file
system" or "Failed to connect to bus". Read the exit code from the tool
result rather than echoing it.

## Give out the URL, never the name

`rrc session` prints the repo's root, then the session's URL. Give the user
that URL. The app names environments after the folder, so two repos called
`web` look the same, and a stopped one can stay listed under the same name.

## When rrc stops and says to ask

- **Exit code 3: the sandbox is off.** `sandbox.enabled` is not true, so the
  session would run commands unsandboxed. Tell the user that, and ask. Only
  with their explicit yes, run the same command again with
  `--allow-unsandboxed`. Never add it yourself to get past the error.
- **"has a server".** Claude refuses a single session beside a Remote Control
  server in the same folder. Give the user the server's URL from the error:
  they open a new session there.
- **"already served".** A server or session in that folder stopped less than
  about 70 seconds ago. Try again in a minute.

## If rrc fails on the sandbox anyway

"Read-only file system", "Failed to connect to bus" or "Device or resource
busy" from a bare `rrc` call means `rrc *` is missing from
`sandbox.excludedCommands`: reinstalling the package adds it. Say so, and do
not retry with the sandbox disabled.
