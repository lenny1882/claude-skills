# repo-remote-control-server — backlog

Opened 9 Nov 2026. Items found while the package was being built are in
`DESIGN.md`, under "Still open".

---

## 1. Servers' sessions get the user's login-shell PATH — **IN PROGRESS, raised 9 Nov 2026**

**What happens in 2.0.2.** `rrc-server@.service` sets
`Environment=PATH=%h/.local/bin:/usr/local/bin:/usr/bin:/bin`, added so a
server's sessions can run `rrcd` by name (infra-box, 3 Nov). systemd can't
expand `$PATH` in `Environment=`, so the line replaces the user manager's
PATH: `/usr/sbin`, `/sbin` and `/snap/bin` go, and nothing from `~/.profile`
or `~/.bashrc` reaches a server. The servers' sessions miss nvm's `node`,
SDKs, asdf shims and the rest, and so does everything those sessions start:
one-off sessions from `rrc session`, which inherit the caller's PATH, and
further servers from `rrcd start`. A `claude` started in a terminal, and the
`rrc` sessions it starts, have the full PATH.

On the aws-workspace box, `setup.sh`'s `server-path` step covers this with a
drop-in (`rrc-server@.service.d/50-path.conf`) naming
`~/.nvm/current/bin` as well, so there the servers get Node and nothing else.

**The change.** `rrcd serve` runs `bash -l -i` once at each server start and
takes its PATH, with `~/.local/bin` put first; the unit's `Environment=PATH=`
line goes, so the shell starts from the manager's PATH, which has the system
directories. `-l` reads `~/.profile` (which on Ubuntu runs `~/.bashrc` and
adds `~/.local/bin`); `-i` gets past `.bashrc`'s return for shells that aren't
interactive. Works the same for a `.bashrc` with installers' lines inline and
for one that sources split files (this machine's `/mnt/sda/User/.bashrc_*`).
The shell runs with no terminal, its output thrown away, the PATH written to
a file, and a time limit; if it fails, the server keeps the manager's PATH
with `~/.local/bin` first. Cost: the user's whole `.bashrc` runs at every
server start, including the 30-second retries while a folder is refused;
loading nvm is about half a second.

**Still to do, in order:**

1. Release as 2.0.3 (`/release repo-remote-control-server`).
2. ~~Docker~~ **Done 9 Nov 2026**, on the uncommitted change (Ubuntu
   24.04, claude 2.1.305): `confirm.sh sandbox-rrc` passed
   (`results/20261109-145148`), `integration.sh --app` passed 27 of 27
   (`results/20261109-145231`), and a one-off check of a running server's
   `/proc/<pid>/environ` passed 4 of 4 (`results/server-path-20261109-151550.log`):
   `~/.local/bin` first, a line added below `.bashrc`'s interactive check
   present, `/usr/sbin` present, `rrcd` found by name. That PATH named
   `~/.local/bin` three times; `rrcd serve` now keeps each directory once.
   Rerun in Docker with that, 5 of 5, no repeats.
3. **Tell aws-workspace**, once 2.0.3 is released, through a session running
   there. Its side:
   - Remove `setup.sh`'s `server-path` step (`body_server_path`,
     `scripts/setup.sh:926`) and delete `50-path.conf` on boxes that have it.
     Left in place it sets the starting PATH to its own short list, so
     servers lose `/usr/sbin` and `/sbin`; and its `~/.nvm/current/bin` is no
     longer needed, since the login shell loads nvm's default.
   - Change the check at `scripts/ad-user-access-test.sh:559`, which looks for
     the drop-in's exact line. The one at line 863, which reads a running
     server's `/proc/<pid>/environ`, is what shows what a session gets.
   - Cache settings in `~/.profile` would now reach server sessions directly;
     `body_claude_settings` copies them into Claude's settings because they
     didn't (`setup.sh:868`). Its call whether to keep the copy.
   - The Master Control Program's unit (`setup.sh:1119`) runs `claude` through
     tmux, not `rrcd serve`, so it keeps its own PATH line.
   - An SDK added later needs only an export in the box's `~/.bashrc` or
     `~/.profile`, then `rrcd restart-all`.

   Sent 9 Nov 2026, before the release, to `aws-workspace-14` (session
   "server PATH and SDKs backlog"), as an update to the item it recorded
   earlier that day about the 2.0.2 behaviour and the drop-in. It was told
   to record, not implement, and that a second message follows when 2.0.3
   is released. **Still to do: that second message.**
