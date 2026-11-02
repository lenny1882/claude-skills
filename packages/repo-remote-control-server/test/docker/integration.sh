#!/usr/bin/env bash
# The real rrcd and rrc, both packages installed into the rrcconfirm box, against the real Claude
# Code and systemd. test/run-tests.sh replaces systemctl with a stand-in; this
# is where they meet the real thing: a server's actual output, the units, the
# update watcher firing on a real `claude install`, and the hooks inside a real
# server session.
#
# usage:
#   test/docker/confirm.sh start           # or up, then its login steps
#   test/docker/integration.sh             # the parts that need nobody; works with !
#   test/docker/integration.sh --app       # also the parts that need you in the app
#
# Needs the box confirm.sh builds, logged in. Results go to
# test/docker/results/<time>/integration.txt, and everything it printed to
# run.log there. It ends with rrcd and rrc teardown, so
# nothing it started keeps running.
#
# Where to run it:
#   your own terminal   with or without --app
#   ! in Claude Code    without --app only: ! has no terminal for --app to ask
#                       on, so --app refuses to start
#   Claude's Bash tool  nothing: its sandbox blocks the Docker socket

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PKG=$(cd "$HERE/../.." && pwd)
SESSION_PKG=$(cd "$PKG/../repo-remote-control-session" && pwd)
BOX=rrcconfirm
DEV=dev
DEV_UID=1500
H=/home/$DEV
RESULTS=${RESULTS:-$HERE/results/$(date +%Y%m%d-%H%M%S)}
APP=no
[ "${1:-}" = --app ] && APP=yes

# everything printed goes to run.log too, so Claude can read a run done in your
# terminal. The questions read /dev/tty, so this does not get in their way.
mkdir -p "$RESULTS"
exec > >(tee -a "$RESULTS/run.log") 2>&1

asDev() {
	docker exec -i -u "$DEV" -w "$H" \
		-e XDG_RUNTIME_DIR=/run/user/$DEV_UID -e DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$DEV_UID/bus \
		"$BOX" bash -lc "$1"
}
userctl() { docker exec "$BOX" systemctl --machine="$DEV@" --user "$@"; }

result() {
	mkdir -p "$RESULTS"
	local verdict=$1 check=$2; shift 2
	printf '  %-6s %-24s %s\n' "$verdict" "$check" "$*" | tee -a "$RESULTS/integration.txt"
}
check() { # name description command...: PASS if the command succeeds
	local name=$1 what=$2; shift 2
	if "$@"; then result PASS "$name" "$what"; else result FAIL "$name" "$what"; fi
}

haveTty() { { : </dev/tty; } 2>/dev/null; }
tell() {
	printf '\n  >  %s\n' "$1"; shift
	(($#)) && printf '     %s\n' "$@"
	read -r -p '     Press Enter when done. ' _ </dev/tty
}
ask() { # check expect question
	local check=$1 expect=$2 question=$3 a note=
	printf '\n  ?  %s\n' "$question"
	while :; do read -r -p '     [y/n] ' a </dev/tty; a=${a,,}; [[ $a == y || $a == n ]] && break; done
	if [[ $a == "$expect" ]]; then result PASS "$check" "$question $a"
	else read -r -p '     What did you see? (Enter to skip) ' note </dev/tty; result FAIL "$check" "$question $a${note:+ - $note}"; fi
}

urlOf() { asDev "rrcd list" | awk -v r="$1" '$0==r {f=1; next} /^[^ ]/ {f=0} f && /environment=env_/ {print $1}' | tail -1; }
unitOf() { printf 'rrc-server@%s.service' "$(asDev "systemd-escape --path '$1'")"; }
exeOf() { asDev "readlink /proc/\$(systemctl --user show -p MainPID --value '$(unitOf "$1")')/exe" 2>/dev/null || true; }
activeAndEnabled() { userctl is-active --quiet "$1" && userctl is-enabled --quiet "$1"; }
newUrl() { [[ $1 == *environment=env_* && $1 != "$2" ]]; }

# --------------------------------

# say where to run it instead, before anything starts
docker info >/dev/null 2>&1 || {
	echo "Can't reach Docker. Run this in your own terminal, or with ! in Claude Code."
	echo "Claude's own Bash tool can't: its sandbox blocks the Docker socket."
	exit 1
}
[ "$APP" = no ] || haveTty || {
	echo "integration.sh --app needs your own terminal: it asks what you saw in the app,"
	echo "and ! gives it no terminal to ask on. Without --app it works with !."
	exit 1
}
[[ $(docker inspect -f '{{.State.Running}}' "$BOX" 2>/dev/null) == true ]] \
	|| { echo "$BOX is not running: test/docker/confirm.sh start (or up)"; exit 1; }
asDev 'claude auth status' >/dev/null 2>&1 \
	|| { echo "claude in $BOX is not logged in: docker exec -it -u $DEV $BOX bash -lc 'claude auth login'"; exit 1; }
mkdir -p "$RESULTS"
echo "  claude $(asDev 'claude --version' | head -1)" >>"$RESULTS/integration.txt"

echo "==> clearing what earlier runs left"
# A run stopped part-way leaves its servers, sessions, test repos and their
# origins behind, and the next run's checks then meet those instead of their
# own: a push to an origin with another history, a server still holding a
# folder. Everything this script makes is removed first, and stopped again on
# exit, however it exits. The [c] keeps pkill from matching its own shell.
cleanup() {
	asDev 'command -v rrcd >/dev/null && rrcd teardown; command -v rrc >/dev/null && rrc teardown
		pkill -f "[c]laude remote-control"; true' >/dev/null 2>&1 || true
}
cleanup
asDev "rm -rf $H/repos/client-x $H/repos/one-off-x $H/origin/my-web.git \
	~/.claude/skills/repo-remote-control-session/state/sessions ~/.claude/skills/repo-remote-control-server/state/repos"
trap cleanup EXIT

echo "==> installing both packages into the box"
# the session package first: rrcd sources its rrc-lib.sh, and the server install
# fails without it. The installers add the sandbox exclusions themselves.
asDev 'rm -rf ~/pkg ~/session-pkg && mkdir -p ~/pkg ~/session-pkg'
tar -C "$SESSION_PKG" --exclude=.claude --exclude=.mcp.json -cf - . \
	| docker exec -i -u "$DEV" "$BOX" tar -C "$H/session-pkg" -xf -
tar -C "$PKG" --exclude=./test/docker/results --exclude=.claude --exclude=.mcp.json -cf - . \
	| docker exec -i -u "$DEV" "$BOX" tar -C "$H/pkg" -xf -
asDev 'tmp=$(mktemp) && f=~/.claude/settings.json && { [ -f $f ] || echo "{}" > $f; } \
	&& jq ". * {\"sandbox\": {\"enabled\": true}}" $f > "$tmp" && mv "$tmp" $f'
# The box's user has had linger since confirm.sh up, so without this the server
# install's post_install only ever takes its already-on path. Off, it has to run
# loginctl enable-linger as the user, which polkit allows: Ubuntu ships
# polkitd, a box built before 2 Nov does not have it.
# Installed into a running box, systemd and D-Bus have to be told about it, or
# logind's call to polkit waits for a service nothing starts and times out.
docker exec "$BOX" bash -c 'command -v pkcheck >/dev/null || {
	apt-get update -qq && apt-get install -y -qq polkitd >/dev/null 2>&1; }
	systemctl daemon-reload && systemctl reload dbus && systemctl start polkit'
docker exec "$BOX" systemctl status --no-pager polkit >"$RESULTS/integration-polkit.txt" 2>&1 || true
docker exec "$BOX" loginctl disable-linger "$DEV"
asDev 'cd ~/session-pkg && ./install.sh --yes && cd ~/pkg && ./install.sh --yes' >"$RESULTS/integration-install.txt" 2>&1 \
	&& [ "$(grep -c 'it does what it is supposed to' "$RESULTS/integration-install.txt")" = 2 ] \
	&& result PASS install "both installed; both install probes passed" \
	|| { result FAIL install "see integration-install.txt"; exit 1; }
check linger "the server install turned linger on, as the user" \
	test "$(grep -c 'turned on linger' "$RESULTS/integration-install.txt")-$(docker exec "$BOX" loginctl show-user "$DEV" -p Linger --value 2>/dev/null)" = 1-yes
# Linger back on starts the user's systemd again, and rrcd start needs it.
# The bus socket can be left from the instance linger off stopped, so its
# being there proves nothing ("Transport endpoint is not connected", 2 Nov):
# wait for the manager itself to answer.
state=""
for _ in $(seq 1 60); do
	state=$(userctl is-system-running 2>/dev/null || true)
	[[ $state == running || $state == degraded ]] && break
	sleep 1
done
[[ $state == running || $state == degraded ]] \
	|| { result FAIL user-systemd "the user's systemd did not come back after linger: ${state:-no answer}"; exit 1; }

DEMO=$H/repos/demo
# hyphens in the path: the 2.0.0 unit's %i.env was not found for one (2 Nov)
WEB=$H/repos/client-x/my-web
asDev "mkdir -p $WEB && cd $WEB && git init -q -b main && git commit -q --allow-empty -m init \
	&& git init -q --bare $H/origin/my-web.git && git remote add origin $H/origin/my-web.git && git push -q origin main"

echo "==> rrcd start"
out=$(asDev "rrcd start $DEMO" 2>"$RESULTS/integration-start.err") || true
u1=$(sed -n 2p <<<"$out")
check start "rrcd start prints the repo and its environment URL" grep -q 'environment=env_' <<<"$u1"
check start-active "the server unit is active and enabled" activeAndEnabled "$(unitOf "$DEMO")"
check watcher-enabled "the update watcher is enabled" userctl is-enabled --quiet rrc-update.path
out2=$(asDev "rrcd start $DEMO" 2>/dev/null) || true
check start-again "rrcd start again gives the same URL without restarting" test "$(sed -n 2p <<<"$out2")" = "$u1"
asDev "rrcd start $WEB" >/dev/null 2>&1 || true
asDev 'rrcd list' >"$RESULTS/integration-list.txt" 2>&1 || true
check list "rrcd list shows both servers, idle, with their URLs" \
	test "$(grep -c 'sessions 0/32' "$RESULTS/integration-list.txt")-$(grep -c 'environment=env_' "$RESULTS/integration-list.txt")" = 2-2

echo "==> rrc session beside a server"
out=$(asDev "rrc session $DEMO" 2>&1) || true
check session-refused "rrc session in a repo with a server is refused and gives the server's URL, from rrcd url" grep -qF "$u1" <<<"$out"

echo "==> rrc session, a detached process"
# hyphens in the path too; and each start must open a new session, not
# resume the folder's last one from claude's bridge-pointer.json
SES=$H/repos/one-off-x
asDev "mkdir -p $SES && cd $SES && git init -q -b main && git commit -q --allow-empty -m init"
sessionPid() { asDev "sed -n 's/^RRC_PID=//p' ~/.claude/skills/repo-remote-control-session/state/sessions/*.pid 2>/dev/null | head -1"; }
liveRc() { [ -n "$1" ] && asDev "tr '\\0' ' ' 2>/dev/null </proc/$1/cmdline | grep -q remote-control"; }
# A folder is refused for up to about 3 minutes after its last session stops
# (131 to 194 s, 2 Nov), and rrc session waits that out itself. This times
# each start, so the run log keeps the refusal's length.
sessionWhenFree() { # n: prints the URL
	local out t0=$SECONDS
	out=$(asDev "rrc session $SES" 2>"$RESULTS/integration-session-$1.err") || true
	echo "     rrc session took $((SECONDS - t0))s$(grep -q 'still registered' "$RESULTS/integration-session-$1.err" && echo ', waiting out a refused folder')" >&2
	sed -n 2p <<<"$out"
}

s1=$(sessionWhenFree 1)
check session-start "rrc session prints the repo and a session URL" grep -q '^https://claude.ai/code/session_' <<<"$s1"
p1=$(sessionPid)
check session-detached "the session keeps running after rrc returns, and links no unit" \
	eval 'liveRc "$p1" && ! asDev "test -e ~/.config/systemd/user/rrc-session@.service"'
asDev 'rrc list' >"$RESULTS/integration-session-list.txt" 2>&1 || true
check session-list "rrc list shows it with its URL" grep -qF "$s1" "$RESULTS/integration-session-list.txt"
asDev 'rrc teardown' >/dev/null 2>&1 || true
sleep 1
check session-teardown "rrc teardown stops it" eval '! liveRc "$p1"'
s2=$(sessionWhenFree 2)
check session-new "a second rrc session in the folder opens a new session, not the last one again" \
	eval 'grep -q "^https://claude.ai/code/session_" <<<"$s2" && [ "$s2" != "$s1" ]'
if [ "$APP" = yes ]; then
	echo "==> rrc session after a session was ended in the app (you, in the app)"
	# On 2 Nov a session started in a folder whose last session had been ended
	# in the app resumed that ended one from bridge-pointer.json, got a 404,
	# and showed "this session couldn't be found". rrc now deletes the pointer
	# first. Ending a session in the app is the part only you can do.
	p2=$(sessionPid)
	tell "Open $s2" \
		"It is a single session in ${SES##*/}, already started by rrc session: there is no environment to pick." \
		"Send it exactly:" \
		"  Run these and show me the output verbatim: pwd; git branch --show-current" \
		"When it has answered, end the session: archive or delete it from the session list in claude.ai or the app."
	ask session-answered y "Did it answer with $SES and main?"
	sleep 5
	check session-ended "ending the session in the app ended its process" eval '! liveRc "$p2"'
	s3=$(sessionWhenFree 3)
	check session-new-after-ended "a session after one was ended in the app gets a new URL, not the ended one's" \
		eval 'grep -q "^https://claude.ai/code/session_" <<<"$s3" && [ "$s3" != "$s2" ]'
	p3=$(sessionPid)
	tell "Open $s3" \
		"This is the case that failed on 2 Nov: a new session in a folder whose last session was ended in the app." \
		"Before the fix, this page said \"this session couldn't be found\"." \
		"Send it exactly:" \
		"  Run these and show me the output verbatim: pwd; git branch --show-current" \
		"When it has answered, archive or delete this session too."
	ask session-after-ended y "Did it answer with $SES and main, rather than say \"this session couldn't be found\"?"
	sleep 5
	check session-ended-again "ending that one in the app ended its process too" eval '! liveRc "$p3"'
fi
asDev 'rrc teardown' >/dev/null 2>&1 || true

echo "==> rrcd restart"
out=$(asDev "rrcd restart $DEMO" 2>/dev/null) || true
u2=$(sed -n 2p <<<"$out")
check restart "rrcd restart prints a new URL" newUrl "$u2" "$u1"

echo "==> the update watcher, on a real claude install"
before=$(asDev 'readlink -f ~/.local/bin/claude')
exe1=$(exeOf "$DEMO")
target=2.1.305
[[ $before == *2.1.305* ]] && target=2.1.308
asDev "claude install $target" >"$RESULTS/integration-update.txt" 2>&1 || true
after=$(asDev 'readlink -f ~/.local/bin/claude')
echo "     claude: $before -> $after; waiting 60s for the watcher"
sleep 60
exe2=$(exeOf "$DEMO")
asDev 'cat ~/.claude/skills/repo-remote-control-server/state/logs/update.log' >>"$RESULTS/integration-update.txt" 2>&1 || true
userctl status --no-pager rrc-update.path rrc-update.service >>"$RESULTS/integration-update.txt" 2>&1 || true
check update-installed "claude install changed the binary" test "$before" != "$after"
check update-fired "the path unit fired: update.log names the idle servers" \
	grep -q "restarted (idle): $DEMO" "$RESULTS/integration-update.txt"
check update-restarted "the idle server now runs the new binary" test "$exe2" = "$after" -a "$exe1" != "$exe2"

if [ "$APP" = yes ]; then
	echo "==> in a real server session (you, in the app)"
	asDev "tmux kill-session -t orchestrator 2>/dev/null; tmux new-session -d -s orchestrator -x 250 -y 50 cat"
	urlW=$(urlOf "$WEB")
	tell "Open $urlW and start a new session there: the environment called ${WEB##*/}, not ${DEMO##*/}." \
		"Use that URL, not the list: earlier runs can leave stale ones called ${WEB##*/}." \
		"Send it exactly:" \
		"  Run these and show me the output verbatim: git branch --show-current; git status | head -2" \
		"Then send: Make an empty commit with git commit --allow-empty -m test, and show me exactly what happened." \
		"Leave the session open."
	ask hook-detached y "Did git status say HEAD detached, with an empty branch name?"
	ask guard-blocked y "Was the commit blocked with 'Create the task's branch first'?"
	before=$(asDev 'readlink -f ~/.local/bin/claude')
	target=2.1.305; [[ $before == *2.1.305* ]] && target=2.1.308
	asDev "claude install $target" >>"$RESULTS/integration-update.txt" 2>&1 || true
	echo "     waiting 60s for the watcher"
	sleep 60
	asDev 'tmux capture-pane -p -t orchestrator:0 -S -50' >"$RESULTS/integration-orchestrator.txt" 2>&1 || true
	check update-asked "a busy server is left running and the orchestrator pane got the [rrcd] message" \
		grep -q "\[rrcd\] claude was updated.*$WEB (1 open)" "$RESULTS/integration-orchestrator.txt"
	asDev 'tmux kill-session -t orchestrator' || true
	tell "End that session in the app (archive or delete it)."
fi

echo "==> rrcd remove and teardown"
asDev "rrcd remove $WEB --worktrees" >"$RESULTS/integration-remove.txt" 2>&1 || true
trust=$(asDev "jq -r --arg p '$WEB' '.projects[\$p].hasTrustDialogAccepted // empty' ~/.claude.json")
check remove "rrcd remove disables the server and clears its trust" \
	test "$(userctl is-active "$(unitOf "$WEB")" 2>/dev/null || true)-$trust" = "inactive-"
asDev 'rrcd teardown && rrc teardown' >/dev/null 2>&1 || true
userctl list-units --all --no-legend 'rrc-*' >"$RESULTS/integration-teardown.txt" 2>&1 || true
check teardown "rrcd and rrc teardown leave no rrc unit loaded (integration-teardown.txt lists any)" \
	test "$(userctl list-units --no-legend 'rrc-*' | wc -l)" = 0

echo
echo "Results ($RESULTS):"
cat "$RESULTS/integration.txt"
