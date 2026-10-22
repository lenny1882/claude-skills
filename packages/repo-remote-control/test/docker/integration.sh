#!/usr/bin/env bash
# The real rrc, installed into the rrcconfirm box, against the real Claude
# Code and systemd. test/run-tests.sh replaces systemctl with a stand-in; this
# is where rrc meets the real thing: a server's actual output, the units, the
# update watcher firing on a real `claude install`, and the hooks inside a real
# server session.
#
# usage:
#   test/docker/confirm.sh start           # or up, then its login steps
#   test/docker/integration.sh             # the parts that need nobody; works with !
#   test/docker/integration.sh --app       # also the parts that need you in the app
#
# Needs the box confirm.sh builds, logged in. Results go to
# test/docker/results/<time>/integration.txt. It ends with rrc teardown, so
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
BOX=rrcconfirm
DEV=dev
DEV_UID=1500
H=/home/$DEV
RESULTS=${RESULTS:-$HERE/results/$(date +%Y%m%d-%H%M%S)}
APP=no
[ "${1:-}" = --app ] && APP=yes

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

urlOf() { asDev "rrc list" | awk -v r="$1" '$0==r {f=1; next} /^[^ ]/ {f=0} f && /environment=env_/ {print $1}' | tail -1; }
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

echo "==> installing the package into the box"
asDev 'rm -rf ~/pkg && mkdir -p ~/pkg'
tar -C "$PKG" --exclude=./test/docker/results --exclude=.claude --exclude=.mcp.json -cf - . \
	| docker exec -i -u "$DEV" "$BOX" tar -C "$H/pkg" -xf -
asDev 'tmp=$(mktemp) && f=~/.claude/settings.json && { [ -f $f ] || echo "{}" > $f; } \
	&& jq ". * {\"sandbox\": {\"enabled\": true, \"excludedCommands\": [\"rrc\"]}}" $f > "$tmp" && mv "$tmp" $f'
asDev 'cd ~/pkg && ./install.sh --yes' >"$RESULTS/integration-install.txt" 2>&1 \
	&& grep -q 'it does what it is supposed to' "$RESULTS/integration-install.txt" \
	&& result PASS install "installed; the install probe passed" \
	|| { result FAIL install "see integration-install.txt"; exit 1; }

DEMO=$H/repos/demo
WEB=$H/repos/client_x/web
asDev "[ -d $WEB/.git ] || { mkdir -p $WEB && cd $WEB && git init -q -b main && git commit -q --allow-empty -m init \
	&& git init -q --bare $H/origin/web.git && git remote add origin $H/origin/web.git && git push -q origin main; }"

echo "==> rrc start"
out=$(asDev "rrc start $DEMO" 2>"$RESULTS/integration-start.err") || true
u1=$(sed -n 2p <<<"$out")
check start "rrc start prints the repo and its environment URL" grep -q 'environment=env_' <<<"$u1"
check start-active "the server unit is active and enabled" activeAndEnabled "$(unitOf "$DEMO")"
check watcher-enabled "the update watcher is enabled" userctl is-enabled --quiet rrc-update.path
out2=$(asDev "rrc start $DEMO" 2>/dev/null) || true
check start-again "rrc start again gives the same URL without restarting" test "$(sed -n 2p <<<"$out2")" = "$u1"
asDev "rrc start $WEB" >/dev/null 2>&1 || true
asDev 'rrc list' >"$RESULTS/integration-list.txt" 2>&1 || true
check list "rrc list shows both servers, idle, with their URLs" \
	test "$(grep -c 'sessions 0/32' "$RESULTS/integration-list.txt")-$(grep -c 'environment=env_' "$RESULTS/integration-list.txt")" = 2-2

echo "==> rrc session beside a server"
out=$(asDev "rrc session $DEMO" 2>&1) || true
check session-refused "rrc session in a repo with a server is refused and gives the server's URL" grep -qF "$u1" <<<"$out"

echo "==> rrc restart"
out=$(asDev "rrc restart $DEMO" 2>/dev/null) || true
u2=$(sed -n 2p <<<"$out")
check restart "rrc restart prints a new URL" newUrl "$u2" "$u1"

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
asDev 'cat ~/.claude/skills/repo-remote-control/state/logs/update.log' >>"$RESULTS/integration-update.txt" 2>&1 || true
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
	check update-asked "a busy server is left running and the orchestrator pane got the [rrc] message" \
		grep -q "\[rrc\] claude was updated.*$WEB (1 open)" "$RESULTS/integration-orchestrator.txt"
	asDev 'tmux kill-session -t orchestrator' || true
	tell "End that session in the app (archive or delete it)."
fi

echo "==> rrc remove and teardown"
asDev "rrc remove $WEB --worktrees" >"$RESULTS/integration-remove.txt" 2>&1 || true
trust=$(asDev "jq -r --arg p '$WEB' '.projects[\$p].hasTrustDialogAccepted // empty' ~/.claude.json")
check remove "rrc remove disables the server and clears its trust" \
	test "$(userctl is-active "$(unitOf "$WEB")" 2>/dev/null || true)-$trust" = "inactive-"
asDev 'rrc teardown' >/dev/null 2>&1 || true
userctl list-units --all --no-legend 'rrc-*' >"$RESULTS/integration-teardown.txt" 2>&1 || true
check teardown "rrc teardown leaves no rrc unit loaded (integration-teardown.txt lists any)" \
	test "$(userctl list-units --no-legend 'rrc-*' | wc -l)" = 0

echo
echo "Results ($RESULTS):"
cat "$RESULTS/integration.txt"
