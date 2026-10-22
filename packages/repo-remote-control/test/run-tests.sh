#!/usr/bin/env bash
# Tests for repo-remote-control.
#
# Redirects HOME and CLAUDE_DIR into a temp directory, so the real config is
# never touched. The installer tests come free, from installer-tests.sh, which
# claude-package-kit keeps up to date. This file is the package's own: add the
# behaviour tests below — they are the point.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home"; mkdir -p "$HOME"
export CLAUDE_DIR="$TMP/claude"; mkdir -p "$CLAUDE_DIR"

pass=0; fail=0
ok(){ printf '  ok    %s\n' "$1"; pass=$((pass+1)); }
no(){ printf '  FAIL  %s\n    %s\n' "$1" "$2"; fail=$((fail+1)); }

. "$REPO/test/installer-tests.sh"

echo "state/ across reinstalls"
# rrc keeps every repo's settings and output in the skill's state/, so a
# reinstall that dropped it would forget every server. The kit's place() keeps
# it; this checks that against this package's own installer.
SD="$TMP/state-claude"
CLAUDE_DIR="$SD" "$REPO/install.sh" --yes >/dev/null 2>&1
mkdir -p "$SD/skills/repo-remote-control/state/repos"
echo kept >"$SD/skills/repo-remote-control/state/repos/x.env"
CLAUDE_DIR="$SD" "$REPO/install.sh" --yes >"$TMP/out" 2>&1
grep -q kept "$SD/skills/repo-remote-control/state/repos/x.env" 2>/dev/null \
  && ok "a reinstall keeps state/" || no "a reinstall keeps state/" "$(tail -3 "$TMP/out")"
CLAUDE_DIR="$SD" "$REPO/uninstall.sh" --yes >/dev/null 2>&1

echo "rrc"
# Unit names hold systemd-escape's \x2d for every "-" in the path, so tests
# match calls with grep -F.
# systemctl is a stand-in: no systemd here, and the real one would start real
# servers. It records each call, keeps unit state in files, and on start plays
# a server output captured in the Docker checks into the unit's log, as the
# unit's StandardOutput=truncate: does. Everything else is real: git repos and
# worktrees, systemd-escape, jq on a real ~/.claude.json.
RRC="$REPO/skill/bin/rrc"
FIX="$REPO/test/fixtures"
STUB="$TMP/stub"; mkdir -p "$STUB/bin"
export RRC_SKILL_DIR="$REPO/skill" RRC_STATE="$TMP/rrc-state" RRC_WAIT=5 RRC_POLL=0.1 STUB
export PATH="$STUB/bin:$PATH"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
cat >"$STUB/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$STUB/calls"
verb="" unit="" now=0 quiet=0
for a in "$@"; do
  case $a in
    --user|-p|--value|MainPID) ;;
    --now) now=1 ;;
    --quiet) quiet=1 ;;
    *) if [ -z "$verb" ]; then verb=$a; else unit=$a; fi ;;
  esac
done
mkdir -p "$STUB/units"; s="$STUB/units/$unit"
play() {
  local inst n f log
  case $unit in
    rrc-session@*) inst=${unit#rrc-session@}; log="${inst%.service}.session.log" ;;
    rrc-server@*) inst=${unit#rrc-server@}; log="${inst%.service}.log" ;;
    *) echo active >"$s.state"; return ;;
  esac
  n=$(( $(cat "$s.starts" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$s.starts"
  f="$STUB/output.$n"; [ -f "$f" ] || f="$STUB/output"
  if [ -f "$f" ]; then cat "$f" >"$RRC_STATE/logs/$log"; fi
  if [ -n "${STUB_FAIL:-}" ]; then echo failed >"$s.state"; else echo active >"$s.state"; fi
}
show() { [ "$quiet" = 1 ] || echo "$1"; }
case $verb in
  daemon-reload) ;;
  start|restart) play ;;
  enable) echo enabled >"$s.enabled"; if [ "$now" = 1 ]; then play; fi ;;
  disable) echo disabled >"$s.enabled"; if [ "$now" = 1 ]; then echo inactive >"$s.state"; fi ;;
  stop) echo inactive >"$s.state" ;;
  is-active) st=$(cat "$s.state" 2>/dev/null || echo inactive); show "$st"; [ "$st" = active ]; exit ;;
  is-enabled) st=$(cat "$s.enabled" 2>/dev/null || echo disabled); show "$st"; [ "$st" = enabled ]; exit ;;
  is-failed) st=$(cat "$s.state" 2>/dev/null || echo inactive); show "$st"; [ "$st" = failed ]; exit ;;
  show) cat "$s.pid" 2>/dev/null || echo "${STUB_PID:-0}" ;;
  *) echo "stub systemctl: unexpected: $*" >&2; exit 1 ;;
esac
exit 0
EOF
chmod +x "$STUB/bin/systemctl"
fresh() { rm -rf "$STUB/units" "$STUB/calls" "$STUB"/output*; }
newcalls() { tail -n +"$(( ${1:-0} + 1 ))" "$STUB/calls" 2>/dev/null; }
ncalls() { wc -l <"$STUB/calls" 2>/dev/null || echo 0; }
repo() { # path: a git repo with one commit, pushed to its own bare origin
  mkdir -p "$1"; git -C "$1" init -q; git -C "$1" commit -q --allow-empty -m init
  git init -q --bare "$1.origin.git"; git -C "$1" remote add origin "$1.origin.git"
  git -C "$1" push -q origin HEAD 2>/dev/null
  (cd "$1" && pwd -P)
}
inst() { systemd-escape --path "$1"; }

printf '{"sandbox":{"enabled":true}}\n' >"$CLAUDE_DIR/settings.json"
printf '{"numStartups":5,"projects":{"/elsewhere":{"hasTrustDialogAccepted":true}}}\n' >"$HOME/.claude.json"
WEB=$(repo "$HOME/repos/client_hugoboss/web"); mkdir -p "$WEB/src"
I=$(inst "$WEB"); UNIT="rrc-server@$I.service"
ENVF="$RRC_STATE/repos/$I.env"; LOGF="$RRC_STATE/logs/$I.log"
URL1=https://claude.ai/code?environment=env_01RC4TRVy72Uh3ogRs7kFsSG

mkdir -p "$TMP/plain"
out=$("$RRC" start "$TMP/plain" 2>&1); rc=$?
[ "$rc" != 0 ] && grep -q 'not in a git repository' <<<"$out" \
  && ok "start refuses a directory outside git" || no "start refuses a directory outside git" "rc=$rc $out"

printf '{}\n' >"$CLAUDE_DIR/settings.json"; fresh
out=$("$RRC" start "$WEB" 2>&1); rc=$?
[ "$rc" = 3 ] && grep -q 'Ask the user' <<<"$out" && [ ! -s "$STUB/calls" ] && [ ! -f "$ENVF" ] \
  && ! jq -e --arg p "$WEB" '.projects[$p]' "$HOME/.claude.json" >/dev/null \
  && ok "start with the sandbox off stops before trust, settings or systemd, and says to ask" \
  || no "start with the sandbox off stops before trust, settings or systemd, and says to ask" "rc=$rc $out"
printf '{"sandbox":{"enabled":true}}\n' >"$CLAUDE_DIR/settings.json"

fresh; cp "$FIX/server-ready.out" "$STUB/output"
out=$(cd "$WEB/src" && "$RRC" start 2>"$TMP/err"); rc=$?
[ "$rc" = 0 ] && [ "$out" = "$WEB"$'\n'"$URL1" ] \
  && ok "start from a subdirectory serves the repo root and prints its URL" \
  || no "start from a subdirectory serves the repo root and prints its URL" "rc=$rc out=$out err=$(cat "$TMP/err")"
grep -qx 'RRC_ARGS="--permission-mode auto --no-create-session-in-dir --remote-control-session-name-prefix client_hugoboss/web"' "$ENVF" \
  && ok "defaults: auto mode, no session in the checkout, prefix is the path under ~/repos" \
  || no "defaults: auto mode, no session in the checkout, prefix is the path under ~/repos" "$(cat "$ENVF" 2>&1)"
jq -e --arg p "$WEB" '.projects[$p].hasTrustDialogAccepted == true and .numStartups == 5
  and .projects["/elsewhere"].hasTrustDialogAccepted == true' "$HOME/.claude.json" >/dev/null \
  && ok "trust is set and the rest of ~/.claude.json kept" || no "trust is set and the rest of ~/.claude.json kept" "$(cat "$HOME/.claude.json")"
[ "$(ls "$RRC_STATE"/backups/claude.json.* 2>/dev/null | wc -l)" = 1 ] \
  && ok "~/.claude.json is backed up before the change" || no "~/.claude.json is backed up before the change" "$(ls "$RRC_STATE"/backups 2>&1)"
[ "$(readlink "$HOME/.config/systemd/user/rrc-server@.service")" = "$REPO/skill/systemd/rrc-server@.service" ] \
  && ok "the unit template is linked into ~/.config/systemd/user" || no "the unit template is linked into ~/.config/systemd/user" "$(ls -l "$HOME/.config/systemd/user" 2>&1)"
grep -qF -- "--user enable --quiet $UNIT" "$STUB/calls" && grep -qF -- "--user start $UNIT" "$STUB/calls" \
  && ok "the server is enabled and started" || no "the server is enabled and started" "$(cat "$STUB/calls")"

n=$(ncalls)
out=$("$RRC" start "$WEB" 2>/dev/null); rc=$?
[ "$rc" = 0 ] && [ "$out" = "$WEB"$'\n'"$URL1" ] && ! newcalls "$n" | grep -qE ' (start|stop) ' \
  && [ "$(ls "$RRC_STATE"/backups/claude.json.* | wc -l)" = 1 ] \
  && ok "start on a running server with the same settings restarts nothing and writes nothing" \
  || no "start on a running server with the same settings restarts nothing and writes nothing" "rc=$rc out=$out calls=$(newcalls "$n")"

n=$(ncalls)
out=$("$RRC" start "$WEB" --permission-mode plan 2>"$TMP/err"); rc=$?
[ "$rc" = 0 ] && grep -qx 'RRC_PERMISSION_MODE="plan"' "$ENVF" && grep -qx 'RRC_PREFIX="client_hugoboss/web"' "$ENVF" \
  && newcalls "$n" | grep -qF -- "--user stop $UNIT" && newcalls "$n" | grep -qF -- "--user start $UNIT" \
  && grep -q 'ends its open sessions' "$TMP/err" \
  && ok "a changed setting is saved, the rest kept, and the server restarted with a warning" \
  || no "a changed setting is saved, the rest kept, and the server restarted with a warning" "rc=$rc $(cat "$TMP/err") $(newcalls "$n")"

out=$("$RRC" start "$WEB" --permission-mode sometimes 2>&1); rc=$?
[ "$rc" != 0 ] && grep -q 'must be one of' <<<"$out" \
  && ok "start refuses an unknown permission mode" || no "start refuses an unknown permission mode" "rc=$rc $out"

git -C "$WEB" worktree add -q --detach "$WEB/.claude/worktrees/bridge-inside" 2>/dev/null
out=$("$RRC" start "$WEB/.claude/worktrees/bridge-inside" 2>/dev/null); rc=$?
[ "$rc" = 0 ] && [ "${out%%$'\n'*}" = "$WEB" ] \
  && ok "start from inside one of the repo's worktrees serves the main checkout" \
  || no "start from inside one of the repo's worktrees serves the main checkout" "rc=$rc $out"
git -C "$WEB" worktree remove --force "$WEB/.claude/worktrees/bridge-inside"

ODD=$(repo "$TMP/elsewhere/odd name"); OI=$(inst "$ODD"); fresh; cp "$FIX/server-ready.out" "$STUB/output"
out=$("$RRC" start "$ODD" 2>&1); rc=$?
[ "$rc" = 0 ] && grep -qx 'RRC_PREFIX="odd-name"' "$RRC_STATE/repos/$OI.env" && grep -qx "RRC_ROOT=\"$ODD\"" "$RRC_STATE/repos/$OI.env" \
  && ok "a repo outside ~/repos, with a space in its name, gets its folder name as a safe prefix" \
  || no "a repo outside ~/repos, with a space in its name, gets its folder name as a safe prefix" "rc=$rc $out"

DEMO=$(repo "$HOME/repos/demo"); DI=$(inst "$DEMO"); fresh
cp "$FIX/server-untrusted.out" "$STUB/output.1"; cp "$FIX/server-ready.out" "$STUB/output.2"
out=$("$RRC" start "$DEMO" 2>"$TMP/err"); rc=$?
[ "$rc" = 0 ] && [ "${out#*$'\n'}" = "$URL1" ] && grep -q 'not trusted' "$TMP/err" \
  && [ "$(grep -cF -- "--user start rrc-server@$DI.service" "$STUB/calls")" = 2 ] \
  && ok "\"Workspace not trusted\" in the output: trust set again, restarted once, URL printed" \
  || no "\"Workspace not trusted\" in the output: trust set again, restarted once, URL printed" "rc=$rc $out $(cat "$TMP/err")"

API=$(repo "$HOME/repos/api"); AI=$(inst "$API"); fresh
cp "$FIX/server-already-served.out" "$STUB/output"
( sleep 1; cat "$FIX/server-ready.out" >"$RRC_STATE/logs/$AI.log" ) &
out=$("$RRC" start "$API" 2>"$TMP/err"); rc=$?
wait
[ "$rc" = 0 ] && [ "${out#*$'\n'}" = "$URL1" ] && grep -q 'still registered' "$TMP/err" \
  && ok "refused as \"already served\": says why it waits, then prints the URL once systemd's retry is up" \
  || no "refused as \"already served\": says why it waits, then prints the URL once systemd's retry is up" "rc=$rc $out $(cat "$TMP/err")"

STUCK=$(repo "$HOME/repos/stuck"); fresh
cp "$FIX/server-already-served.out" "$STUB/output"
out=$(RRC_WAIT=1 "$RRC" start "$STUCK" 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q 'no environment URL after 1s. Last error: Error: This folder is already served' <<<"$out" \
  && ok "no URL in time: fails with the server's last error" || no "no URL in time: fails with the server's last error" "rc=$rc $out"

BOOM=$(repo "$HOME/repos/boom"); fresh
printf 'Error: something else broke\n' >"$STUB/output"
out=$(STUB_FAIL=1 "$RRC" start "$BOOM" 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q 'failed. Last error: Error: something else broke' <<<"$out" \
  && ok "a failed unit: stops waiting and reports the error" || no "a failed unit: stops waiting and reports the error" "rc=$rc $out"

# list: one older binary running, to see the update warning
mkdir -p "$TMP/versions" "$HOME/.local/bin"
cp "$(command -v sleep)" "$TMP/versions/2.1.304"; cp "$(command -v sleep)" "$TMP/versions/2.1.308"
ln -sfn "$TMP/versions/2.1.308" "$HOME/.local/bin/claude"
"$TMP/versions/2.1.304" 30 & OLD=$!
cp "$FIX/server-one-session.out" "$LOGF"
# later starts reset the stand-in's units; web is the one running here
mkdir -p "$STUB/units"; echo active >"$STUB/units/$UNIT.state"; echo enabled >"$STUB/units/$UNIT.enabled"
out=$(STUB_PID=$OLD "$RRC" list 2>&1); rc=$?
kill "$OLD" 2>/dev/null; wait "$OLD" 2>/dev/null
grep -qx "$WEB" <<<"$out" && grep -qx '  active, enabled, sessions 1/32' <<<"$out" \
  && grep -qx '  https://claude.ai/code?environment=env_01TrdNGvD5hh3Tdp4ppMHToF' <<<"$out" \
  && ok "list: repo, state, open sessions and the current URL" || no "list: repo, state, open sessions and the current URL" "$out"
grep -q 'runs an older claude (2.1.304; 2.1.308 is installed)' <<<"$out" \
  && ok "list: a server running an older claude says so" || no "list: a server running an older claude says so" "$out"
grep -q 'last error: Error: This folder is already served' <<<"$out" \
  && ok "list: a server's last error" || no "list: a server's last error" "$out"

n=$(ncalls)
out=$("$RRC" stop "$WEB" 2>&1); rc=$?
[ "$rc" = 0 ] && newcalls "$n" | grep -qF -- "--user stop $UNIT" && grep -q 'next boot' <<<"$out" \
  && ok "stop stops it and says it comes back at boot" || no "stop stops it and says it comes back at boot" "rc=$rc $out"
n=$(ncalls)
out=$("$RRC" disable "$WEB" 2>&1); rc=$?
[ "$rc" = 0 ] && newcalls "$n" | grep -qF -- "--user disable --now --quiet $UNIT" && [ -f "$ENVF" ] \
  && jq -e --arg p "$WEB" '.projects[$p].hasTrustDialogAccepted == true' "$HOME/.claude.json" >/dev/null \
  && ok "disable turns it off and keeps its trust and settings" || no "disable turns it off and keeps its trust and settings" "rc=$rc $out"
out=$("$RRC" stop "$TMP/elsewhere" 2>&1); rc=$?
mkdir -p "$TMP/never"; NEVER=$(repo "$TMP/never/repo")
out=$("$RRC" stop "$NEVER" 2>&1); rc=$?
[ "$rc" != 0 ] && grep -q 'no server for' <<<"$out" \
  && ok "stop on a repo rrc never started says so" || no "stop on a repo rrc never started says so" "rc=$rc $out"

# remove: three server worktrees (clean and detached, with work, clean on a
# generated branch) and one that is not the server's
W="$WEB/.claude/worktrees"
git -C "$WEB" worktree add -q --detach "$W/bridge-clean"
git -C "$WEB" worktree add -q --detach "$W/bridge-work"; echo wip >"$W/bridge-work/wip.txt"
git -C "$WEB" worktree add -q -b worktree-bridge-gen "$W/bridge-gen"
git -C "$WEB" worktree add -q --detach "$TMP/not-the-servers"
n=$(ncalls)
out=$("$RRC" remove "$WEB" 2>&1); rc=$?
[ "$rc" = 0 ] && newcalls "$n" | grep -qF -- "--user disable --now --quiet $UNIT" && [ ! -f "$ENVF" ] && [ ! -f "$LOGF" ] \
  && jq -e --arg p "$WEB" '(.projects[$p] | has("hasTrustDialogAccepted") | not) and .projects["/elsewhere"].hasTrustDialogAccepted == true' "$HOME/.claude.json" >/dev/null \
  && ok "remove: disabled, settings and output gone, its trust cleared, other trust kept" \
  || no "remove: disabled, settings and output gone, its trust cleared, other trust kept" "rc=$rc $out"
grep -q "$W/bridge-clean  detached, 0 uncommitted, 0 unpushed" <<<"$out" \
  && grep -q "$W/bridge-work  detached, 1 uncommitted, 0 unpushed" <<<"$out" \
  && grep -q "$W/bridge-gen  worktree-bridge-gen, 0 uncommitted, 0 unpushed" <<<"$out" \
  && ! grep -q 'not-the-servers' <<<"$out" && [ -d "$W/bridge-clean" ] && [ -d "$W/bridge-work" ] && [ -d "$W/bridge-gen" ] \
  && ok "remove lists only the server's worktrees, with their work, and deletes none" \
  || no "remove lists only the server's worktrees, with their work, and deletes none" "$out"
out=$("$RRC" remove "$WEB" --worktrees 2>&1); rc=$?
[ "$rc" = 0 ] && [ ! -d "$W/bridge-clean" ] && [ ! -d "$W/bridge-gen" ] && [ -f "$W/bridge-work/wip.txt" ] \
  && ! git -C "$WEB" show-ref -q --verify refs/heads/worktree-bridge-gen && [ -d "$TMP/not-the-servers" ] \
  && grep -q 'bridge-work.*kept: it has work' <<<"$out" \
  && ok "remove --worktrees deletes the clean ones and their generated branch, keeps the one with work" \
  || no "remove --worktrees deletes the clean ones and their generated branch, keeps the one with work" "rc=$rc $out"
out=$("$RRC" remove "$WEB" --force 2>&1); rc=$?
[ "$rc" != 0 ] && [ -d "$W/bridge-work" ] \
  && ok "remove --force without --worktrees is refused" || no "remove --force without --worktrees is refused" "rc=$rc $out"
out=$("$RRC" remove "$WEB" --worktrees --force 2>&1); rc=$?
[ "$rc" = 0 ] && [ ! -d "$W/bridge-work" ] \
  && ok "remove --worktrees --force deletes the one with work too" || no "remove --worktrees --force deletes the one with work too" "rc=$rc $out"

out=$("$RRC" frobnicate 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q 'usage: rrc' <<<"$out" && ok "an unknown command prints usage" || no "an unknown command prints usage" "rc=$rc"

echo "rrc clone and session"
REMOTES="$TMP/remotes"; mkdir -p "$REMOTES"
seedRemote() { # name: a bare repo with one commit, as a host would hold it
  local w="$TMP/seed-$1"; git init -q "$w"; git -C "$w" commit -q --allow-empty -m init
  git init -q --bare "$REMOTES/$1.git"; git -C "$w" push -q "$REMOTES/$1.git" HEAD:refs/heads/main 2>/dev/null
  git -C "$REMOTES/$1.git" symbolic-ref HEAD refs/heads/main
}
seedRemote shop; seedRemote web
mkdir -p "$RRC_STATE"; printf 'CLONE_BASE="%s/"\n' "$REMOTES" >"$RRC_STATE/config"

fresh; cp "$FIX/server-ready.out" "$STUB/output"
out=$("$RRC" clone shop client_acme 2>"$TMP/err"); rc=$?
SHOP="$HOME/repos/client_acme/shop"
[ "$rc" = 0 ] && [ -d "$SHOP/.git" ] && [ "${out%%$'\n'*}" = "$SHOP" ] && [ "${out#*$'\n'}" = "$URL1" ] \
  && grep -qx 'RRC_PREFIX="client_acme/shop"' "$RRC_STATE/repos/$(inst "$SHOP").env" \
  && ok "clone of a slug: CLONE_BASE + slug + .git into ~/repos/<path>/<name>, then started, URL printed" \
  || no "clone of a slug: CLONE_BASE + slug + .git into ~/repos/<path>/<name>, then started, URL printed" "rc=$rc $out $(cat "$TMP/err")"

out=$("$RRC" clone shop client_acme 2>&1); rc=$?
[ "$rc" != 0 ] && grep -q 'already exists' <<<"$out" \
  && ok "clone into an existing folder is refused" || no "clone into an existing folder is refused" "rc=$rc $out"

fresh; cp "$FIX/server-ready.out" "$STUB/output"
out=$("$RRC" clone "$REMOTES/shop.git" client_other --permission-mode plan 2>"$TMP/err"); rc=$?
OSHOP="$HOME/repos/client_other/shop"
[ "$rc" = 0 ] && grep -q 'same folder name' "$TMP/err" && grep -q "$SHOP" "$TMP/err" \
  && grep -qx 'RRC_PERMISSION_MODE="plan"' "$RRC_STATE/repos/$(inst "$OSHOP").env" \
  && ok "clone of a URL with the same folder name as another repo warns, and passes start's options on" \
  || no "clone of a URL with the same folder name as another repo warns, and passes start's options on" "rc=$rc $(cat "$TMP/err")"

fresh; cp "$FIX/server-ready.out" "$STUB/output"
out=$("$RRC" clone shop client_third --name shop-eu 2>"$TMP/err"); rc=$?
[ "$rc" = 0 ] && [ -d "$HOME/repos/client_third/shop-eu/.git" ] \
  && ok "clone --name picks the folder name" || no "clone --name picks the folder name" "rc=$rc $(cat "$TMP/err")"

printf '{}\n' >"$CLAUDE_DIR/settings.json"; fresh
out=$("$RRC" clone web 2>&1); rc=$?
[ "$rc" = 3 ] && [ ! -e "$HOME/repos/web" ] \
  && ok "clone with the sandbox off stops before cloning" || no "clone with the sandbox off stops before cloning" "rc=$rc $out"
printf '{"sandbox":{"enabled":true}}\n' >"$CLAUDE_DIR/settings.json"

SURL=https://claude.ai/code/session_01G8282bitpmbotQCQAB569H
SES=$(repo "$HOME/repos/one-off"); SI=$(inst "$SES"); SUNIT="rrc-session@$SI.service"
fresh; cp "$FIX/session-ready.out" "$STUB/output"
out=$("$RRC" session "$SES" --name "fix the login page" 2>"$TMP/err"); rc=$?
[ "$rc" = 0 ] && [ "${out#*$'\n'}" = "$SURL" ] && grep -q 'never comes back at boot' "$TMP/err" \
  && ok "session starts one session and prints its URL" || no "session starts one session and prints its URL" "rc=$rc $out $(cat "$TMP/err")"
grep -qx 'RRC_ARGS="--permission-mode auto --name fix-the-login-page"' "$RRC_STATE/sessions/$SI.env" \
  && ok "session: auto mode by default, its title as one argument" || no "session: auto mode by default, its title as one argument" "$(cat "$RRC_STATE/sessions/$SI.env")"
grep -qF -- "--user start $SUNIT" "$STUB/calls" && ! grep -qF -- "enable --quiet $SUNIT" "$STUB/calls" \
  && [ "$(readlink "$HOME/.config/systemd/user/rrc-session@.service")" = "$REPO/skill/systemd/rrc-session@.service" ] \
  && ok "session runs from the linked session template and is never enabled" \
  || no "session runs from the linked session template and is never enabled" "$(cat "$STUB/calls")"

n=$(ncalls)
out=$("$RRC" session "$SES" 2>"$TMP/err"); rc=$?
[ "$rc" = 0 ] && [ "${out#*$'\n'}" = "$SURL" ] && ! newcalls "$n" | grep -qF -- "--user start" && grep -q 'already running' "$TMP/err" \
  && ok "session while one is running hands out its URL instead of starting another" \
  || no "session while one is running hands out its URL instead of starting another" "rc=$rc $out $(newcalls "$n")"

out=$("$RRC" list 2>&1)
grep -qx "$SES" <<<"$out" && grep -qx '  one session, running' <<<"$out" && grep -qx "  $SURL" <<<"$out" \
  && ok "list shows a running session and its URL" || no "list shows a running session and its URL" "$out"

SRV=$(repo "$HOME/repos/served"); fresh; cp "$FIX/server-ready.out" "$STUB/output"
"$RRC" start "$SRV" >/dev/null 2>&1
n=$(ncalls)
out=$("$RRC" session "$SRV" 2>&1); rc=$?
[ "$rc" != 0 ] && grep -q "has a server" <<<"$out" && grep -qF "$URL1" <<<"$out" && ! newcalls "$n" | grep -qF -- "rrc-session@" \
  && ok "session in a repo with a server is refused and hands out the server's URL" \
  || no "session in a repo with a server is refused and hands out the server's URL" "rc=$rc $out"

LATE=$(repo "$HOME/repos/late"); fresh; cp "$FIX/server-already-served.out" "$STUB/output"
out=$(STUB_FAIL=1 "$RRC" session "$LATE" 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q 'try again in a minute' <<<"$out" \
  && ok "a session refused as \"already served\" says to try again in a minute" \
  || no "a session refused as \"already served\" says to try again in a minute" "rc=$rc $out"

echo "rrc updates"
# Three running servers: idle on the old claude, busy on the old claude, and
# one already on the new one. Each "server" is a real process started from a
# copy of a binary named after a claude version, so /proc/<pid>/exe says which
# version it runs, as it would for the real server.
cat >"$STUB/bin/tmux" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$STUB/tmux"
[ "$1" = has-session ] && { [ -n "${STUB_TMUX_UP:-}" ]; exit; }
exit 0
EOF
chmod +x "$STUB/bin/tmux"
fresh; rm -f "$STUB/tmux"; cp "$FIX/server-ready.out" "$STUB/output"
IDLE=$(repo "$HOME/repos/up-idle"); BUSY=$(repo "$HOME/repos/up-busy"); NEWR=$(repo "$HOME/repos/up-new")
for r in "$IDLE" "$BUSY" "$NEWR"; do "$RRC" start "$r" >/dev/null 2>&1; done
grep -qF -- "--user enable --now --quiet rrc-update.path" "$STUB/calls" \
  && [ "$(readlink "$HOME/.config/systemd/user/rrc-update.path")" = "$REPO/skill/systemd/rrc-update.path" ] \
  && ok "start links and enables the update watcher" || no "start links and enables the update watcher" "$(cat "$STUB/calls")"
grep -qx 'PathChanged=%h/.local/bin/claude' "$REPO/skill/systemd/rrc-update.path" \
  && grep -qx 'PathChanged=%h/.local/share/claude/versions' "$REPO/skill/systemd/rrc-update.path" \
  && grep -qx 'ExecStart=%h/.local/bin/rrc on-update' "$REPO/skill/systemd/rrc-update.service" \
  && ok "the watcher watches the claude symlink and its versions directory, and runs rrc on-update" \
  || no "the watcher watches the claude symlink and its versions directory, and runs rrc on-update" "units differ"
cp "$FIX/server-one-session.out" "$RRC_STATE/logs/$(inst "$BUSY").log"
"$TMP/versions/2.1.304" 60 & P1=$!
"$TMP/versions/2.1.304" 60 & P2=$!
"$TMP/versions/2.1.308" 60 & P3=$!
echo "$P1" >"$STUB/units/rrc-server@$(inst "$IDLE").service.pid"
echo "$P2" >"$STUB/units/rrc-server@$(inst "$BUSY").service.pid"
echo "$P3" >"$STUB/units/rrc-server@$(inst "$NEWR").service.pid"

n=$(ncalls)
STUB_TMUX_UP=1 "$RRC" on-update >"$TMP/out" 2>&1; rc=$?
newcalls "$n" >"$TMP/new"
[ "$rc" = 0 ] && grep -qF -- "--user start rrc-server@$(inst "$IDLE").service" "$TMP/new" \
  && ! grep -qF -- "start rrc-server@$(inst "$BUSY").service" "$TMP/new" && ! grep -qF -- "stop rrc-server@$(inst "$BUSY").service" "$TMP/new" \
  && ! grep -qF -- "start rrc-server@$(inst "$NEWR").service" "$TMP/new" && ! grep -qF -- "stop rrc-server@$(inst "$NEWR").service" "$TMP/new" \
  && ok "on-update restarts the idle server on the old claude only" \
  || no "on-update restarts the idle server on the old claude only" "rc=$rc $(cat "$TMP/out") $(cat "$TMP/new")"
grep -q 'send-keys -t orchestrator:0 -l \[rrc\] claude was updated to 2.1.308' "$STUB/tmux" \
  && grep -q "$BUSY (1 open)" "$STUB/tmux" && grep -q "Idle servers restarted: $IDLE" "$STUB/tmux" \
  && grep -q 'rrc restart-all' "$STUB/tmux" && grep -q 'send-keys -t orchestrator:0 Enter' "$STUB/tmux" \
  && ok "on-update asks the orchestrator, in its tmux pane, about the busy server" \
  || no "on-update asks the orchestrator, in its tmux pane, about the busy server" "$(cat "$STUB/tmux" 2>&1)"
grep -q "restarted (idle): $IDLE" "$RRC_STATE/logs/update.log" && grep -q "still on the old version: $BUSY" "$RRC_STATE/logs/update.log" \
  && ok "on-update records what it did in state/logs/update.log" || no "on-update records what it did in state/logs/update.log" "$(cat "$RRC_STATE/logs/update.log")"

rm -f "$STUB/tmux"; printf 'ORCHESTRATOR_TMUX="work:2"\nCLONE_BASE="%s/"\n' "$REMOTES" >"$RRC_STATE/config"
: >"$RRC_STATE/logs/$(inst "$BUSY").log"
"$RRC" on-update >/dev/null 2>&1
grep -q "$BUSY (unknown open)" "$RRC_STATE/logs/update.log" && grep -q 'could not reach the orchestrator at work:2' "$RRC_STATE/logs/update.log" \
  && ! grep -q 'send-keys' "$STUB/tmux" 2>/dev/null \
  && ok "no session count means busy, the pane comes from ORCHESTRATOR_TMUX, and a missing orchestrator is logged" \
  || no "no session count means busy, the pane comes from ORCHESTRATOR_TMUX, and a missing orchestrator is logged" "$(tail -4 "$RRC_STATE/logs/update.log")"

echo "$P3" >"$STUB/units/rrc-server@$(inst "$IDLE").service.pid"; echo "$P3" >"$STUB/units/rrc-server@$(inst "$BUSY").service.pid"
n=$(ncalls); lines=$(wc -l <"$RRC_STATE/logs/update.log")
"$RRC" on-update >/dev/null 2>&1
! newcalls "$n" | grep -qF -- "--user start" && [ "$(wc -l <"$RRC_STATE/logs/update.log")" = "$lines" ] \
  && ok "on-update with every server current does nothing" || no "on-update with every server current does nothing" "$(newcalls "$n")"
kill "$P1" "$P2" "$P3" 2>/dev/null; wait "$P1" "$P2" "$P3" 2>/dev/null

n=$(ncalls)
out=$("$RRC" restart "$BUSY" 2>"$TMP/err"); rc=$?
[ "$rc" = 0 ] && [ "${out#*$'\n'}" = "$URL1" ] && newcalls "$n" | grep -qF -- "--user start rrc-server@$(inst "$BUSY").service" \
  && grep -q 'ends its open sessions' "$TMP/err" \
  && ok "restart restarts one server, warns, and prints its URL" || no "restart restarts one server, warns, and prints its URL" "rc=$rc $out"
n=$(ncalls)
out=$("$RRC" restart-all 2>/dev/null); rc=$?
started=$(newcalls "$n" | grep -cF -- "--user start rrc-server@")
active=$(cat "$STUB"/units/rrc-server@*.state | grep -c active)
[ "$rc" = 0 ] && [ "$started" = "$active" ] && [ "$started" -ge 3 ] && grep -qx "$IDLE" <<<"$out" && grep -qx "$NEWR" <<<"$out" \
  && ok "restart-all restarts every running server and prints each URL" \
  || no "restart-all restarts every running server and prints each URL" "rc=$rc started=$started active=$active $out"

n=$(ncalls)
out=$("$RRC" teardown 2>&1); rc=$?
[ "$rc" = 0 ] && newcalls "$n" | grep -qF -- "--user disable --now --quiet rrc-server@$(inst "$IDLE").service" \
  && newcalls "$n" | grep -qF -- "--user stop rrc-session@$SI.service" \
  && newcalls "$n" | grep -qF -- "--user disable --now --quiet rrc-update.path" \
  && [ ! -e "$HOME/.config/systemd/user/rrc-server@.service" ] && [ ! -e "$HOME/.config/systemd/user/rrc-update.path" ] \
  && [ -f "$RRC_STATE/repos/$(inst "$IDLE").env" ] \
  && ok "teardown disables every server, stops sessions and the watcher, unlinks the units, keeps state" \
  || no "teardown disables every server, stops sessions and the watcher, unlinks the units, keeps state" "rc=$rc $out"

echo "hooks"
# Real git: a repo pushed to its own origin, and the worktrees a server makes:
# .claude/worktrees/bridge-<id> on a generated worktree-bridge-<id> branch.
SS="$REPO/skill/hooks/repo-remote-control-sessionstart.sh"
CG="$REPO/skill/hooks/repo-remote-control-commit-guard.sh"
H=$(repo "$TMP/hooks/app"); HW="$H/.claude/worktrees"
startHook() { jq -n --arg c "$1" --arg s "${2:-startup}" '{cwd: $c, source: $s, hook_event_name: "SessionStart"}' | "$SS"; }
guard() { jq -n --arg c "$1" --arg x "$2" '{cwd: $c, tool_name: "Bash", tool_input: {command: $x}}' | "$CG" 2>"$TMP/guard.err"; }
onBranch() { git -C "$1" symbolic-ref --short -q HEAD; }

git -C "$H" worktree add -q -b worktree-bridge-new "$HW/bridge-new"
out=$(startHook "$HW/bridge-new"); rc=$?
[ "$rc" = 0 ] && [ -z "$(onBranch "$HW/bridge-new")" ] && ! git -C "$H" show-ref -q --verify refs/heads/worktree-bridge-new \
  && ok "SessionStart in a new server worktree: HEAD detached, generated branch deleted" \
  || no "SessionStart in a new server worktree: HEAD detached, generated branch deleted" "rc=$rc branch=$(onBranch "$HW/bridge-new")"
jq -e '.hookSpecificOutput.hookEventName == "SessionStart"
  and (.hookSpecificOutput.additionalContext | test("git switch -c <type>/<KEY>-<description>"))' <<<"$out" >/dev/null 2>&1 \
  && ok "SessionStart tells the session to create its branch first" \
  || no "SessionStart tells the session to create its branch first" "$out"

mkdir -p "$HW/bridge-new/sub"; out=$(startHook "$HW/bridge-new/sub" resume)
[ -n "$out" ] && ok "SessionStart on resume, still detached, says it again" || no "SessionStart on resume, still detached, says it again" "no output"

git -C "$H" worktree add -q -b worktree-bridge-used "$HW/bridge-used"
git -C "$HW/bridge-used" commit -q --allow-empty -m "work"
out=$(startHook "$HW/bridge-used" resume)
[ "$(onBranch "$HW/bridge-used")" = worktree-bridge-used ] && [ -z "$out" ] \
  && ok "SessionStart leaves a generated branch that already has commits" \
  || no "SessionStart leaves a generated branch that already has commits" "branch=$(onBranch "$HW/bridge-used") $out"

git -C "$H" worktree add -q -b feature/HB-1-named "$HW/bridge-named"
out=$(startHook "$HW/bridge-named" resume)
[ "$(onBranch "$HW/bridge-named")" = feature/HB-1-named ] && [ -z "$out" ] \
  && ok "SessionStart leaves a session already on a named branch alone, silently" \
  || no "SessionStart leaves a session already on a named branch alone, silently" "$out"

git -C "$H" worktree add -q -b worktree-agent-x "$TMP/hooks/agent-x"
git -C "$H" worktree add -q -b worktree-bridge-elsewhere "$TMP/hooks/elsewhere/.claude/worktrees/not-bridge"
out=$(startHook "$TMP/hooks/agent-x"); out2=$(startHook "$H")
[ "$(onBranch "$TMP/hooks/agent-x")" = worktree-agent-x ] && [ -z "$out$out2" ] \
  && ok "SessionStart does nothing outside .claude/worktrees/bridge-*" \
  || no "SessionStart does nothing outside .claude/worktrees/bridge-*" "$out$out2"

D="$HW/bridge-new"
guard "$D" 'git commit -m "first"'; rc=$?
[ "$rc" = 2 ] && grep -q 'git switch -c <type>/<KEY>-<description>' "$TMP/guard.err" \
  && ok "guard blocks git commit on a detached HEAD in a server worktree, saying what to do" \
  || no "guard blocks git commit on a detached HEAD in a server worktree, saying what to do" "rc=$rc $(cat "$TMP/guard.err")"
guard "$H" "git -C $D commit -am x"; rc1=$?
guard "$H" "cd $D && git add . && git commit -m x"; rc2=$?
guard "$D/.." "cd bridge-new; git --no-pager -c core.editor=true commit"; rc3=$?
guard "$D" "GIT_AUTHOR_NAME=x git commit -m x"; rc4=$?
[ "$rc1$rc2$rc3$rc4" = 2222 ] \
  && ok "guard follows git -C, cd, git's own options and env assignments" \
  || no "guard follows git -C, cd, git's own options and env assignments" "rc=$rc1$rc2$rc3$rc4"
guard "$D" 'git switch -c feature/HB-2-thing && git commit -m x'; rc1=$?
guard "$D" 'git checkout -b bug/fix && git commit -m x'; rc2=$?
guard "$D" 'git switch --detach && git commit -m x'; rc3=$?
[ "$rc1$rc2" = 00 ] && [ "$rc3" = 2 ] \
  && ok "guard lets a commit through after git switch -c / checkout -b in the same command, not after --detach" \
  || no "guard lets a commit through after git switch -c / checkout -b in the same command, not after --detach" "rc=$rc1$rc2$rc3"
guard "$HW/bridge-named" 'git commit -m x'; rc1=$?
guard "$H" 'git commit -m x'; rc2=$?
git -C "$H" worktree add -q --detach "$TMP/hooks/detached-elsewhere"
guard "$TMP/hooks/detached-elsewhere" 'git commit -m x'; rc3=$?
[ "$rc1$rc2$rc3" = 000 ] \
  && ok "guard allows commits on a branch, and anywhere outside server worktrees" \
  || no "guard allows commits on a branch, and anywhere outside server worktrees" "rc=$rc1$rc2$rc3"
guard "$D" 'git log --grep commit'; rc1=$?
guard "$D" 'git commit-tree HEAD^{tree} -m x'; rc2=$?
guard "$D" 'echo git commit'; rc3=$?
guard "$D" 'git status'; rc4=$?
[ "$rc1$rc2$rc3$rc4" = 0000 ] \
  && ok "guard ignores commands that only mention commit" \
  || no "guard ignores commands that only mention commit" "rc=$rc1$rc2$rc3$rc4"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
