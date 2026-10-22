#!/usr/bin/env bash
# confirm, in a systemd container, the Claude Code behaviour repo-remote-control
# is designed on but nobody has seen yet. Same container pattern as
# aws-workspace's scripts/remote-control-systemd-test.sh: Ubuntu 24.04 booting
# systemd, a user with linger, claude installed for that user, logged in by hand.
#
# usage:
#   test/docker/confirm.sh up                   # build, user, repos (then the login steps it prints)
#   test/docker/confirm.sh start                # start a stopped box again; the login survives
#   test/docker/confirm.sh untrusted-output     # "Workspace not trusted" reaches the output
#   test/docker/confirm.sh raw-output           # escape codes, screen boundaries, growth rate
#   test/docker/confirm.sh name-restart         # --name, environment ID across a restart
#   test/docker/confirm.sh folder-served        # session mode beside a running server
#   test/docker/confirm.sh tmux-queue           # send-keys to a busy session is queued
#   test/docker/confirm.sh sandbox-rrc          # rrc's writes from a sandboxed session; excludedCommands
#   test/docker/confirm.sh refused-exit         # a server refused as "already served" exits with an error
#   test/docker/confirm.sh idle-count           # Capacity count; title prefix         (app)
#   test/docker/confirm.sh sessionstart-detach  # SessionStart in a server worktree    (app)
#   test/docker/confirm.sh spawn-session        # --spawn session, --permission-mode   (app)
#   test/docker/confirm.sh sandbox-auto         # spawned sessions run auto, sandboxed (app)
#   test/docker/confirm.sh auto                 # the checks that need nobody in the app; work with !
#   test/docker/confirm.sh app                  # the four (app) checks; need a terminal
#   test/docker/confirm.sh all                  # every check
#   test/docker/confirm.sh down                 # log out, remove the box and its image
#
# (app) checks tell you what to do in claude.ai/code or the app, wait for
# Enter, and ask yes/no about what you saw. The answers are the results; there
# is nothing to write down.
#
# Where to run it:
#   your own terminal   every command
#   ! in Claude Code    every command except the (app) ones, app and all: ! has
#                       no terminal for them to ask on, so they refuse to start
#   Claude's Bash tool  nothing: its sandbox blocks the Docker socket
#
# One run of any command writes to test/docker/results/<time>/ (gitignored):
# summary.txt has one line per result; <name>.raw is server output as written,
# .catv the same through cat -v, .txt with escape codes stripped.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
BOX=rrcconfirm
IMAGE=rrcconfirm:latest
CLAUDE_VERSION=${CLAUDE_VERSION:-2.1.304}
DEV=dev
DEV_UID=1500
H=/home/$DEV
ORIGIN=$H/origin/demo.git
REPO=$H/repos/demo
SCRATCH=$H/repos/scratch
# what the app lists the box's server as: the repo folder's name, whatever --name says
ENV_NAME=demo
UNIT=rrc-confirm.service
OUT=$H/rrc-out
RESULTS=${RESULTS:-$HERE/results/$(date +%Y%m%d-%H%M%S)}

box() { docker exec "$BOX" bash -c "$1"; }
# docker exec gives no login session, so no XDG_RUNTIME_DIR and no user bus for
# systemctl --user; a user service on the box has both
asDev() {
	docker exec -i -u "$DEV" -w "$H" \
		-e XDG_RUNTIME_DIR=/run/user/$DEV_UID -e DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$DEV_UID/bus \
		"$BOX" bash -lc "$1"
}
userctl() { docker exec "$BOX" systemctl --machine="$DEV@" --user "$@"; }

result() {
	mkdir -p "$RESULTS"
	local verdict=$1 check=$2; shift 2
	printf '  %-6s %-22s %s\n' "$verdict" "$check" "$*" | tee -a "$RESULTS/summary.txt"
}

# --------------------------------
# talking to the person in the app

haveTty() { { : </dev/tty; } 2>/dev/null; }

# say where to run it instead, before anything starts
needDocker() {
	docker info >/dev/null 2>&1 && return 0
	echo "Can't reach Docker. Run this in your own terminal, or with ! in Claude Code."
	echo "Claude's own Bash tool can't: its sandbox blocks the Docker socket."
	exit 1
}
needTerminal() { # command
	haveTty && return 0
	echo "confirm.sh $1 needs your own terminal: it asks what you saw in the app, and"
	echo "! gives it no terminal to ask on. confirm.sh auto runs the rest, and works with !."
	exit 1
}

needTty() {
	haveTty && return 0
	result SKIP "$1" "needs you in the app: run it in your own terminal, not with !"
	return 1
}

# what to do in the app, then wait until it's done
tell() {
	printf '\n  >  %s\n' "$1"
	shift
	(($#)) && printf '     %s\n' "$@"
	read -r -p '     Press Enter when done. ' _ </dev/tty
}

# a yes/no question about what you saw; the answer is the result.
# expect is the answer that means the assumption held.
ask() { # check expect(y|n) question
	local check=$1 expect=$2 question=$3 a note=
	if ! haveTty; then
		result SKIP "$check" "no terminal to ask: $question"
		return 0
	fi
	printf '\n  ?  %s\n' "$question"
	while :; do
		read -r -p '     [y/n] ' a </dev/tty
		a=${a,,}
		[[ $a == y || $a == n ]] && break
	done
	if [[ $a == "$expect" ]]; then
		result PASS "$check" "$question $a"
	else
		read -r -p '     What did you see? (Enter to skip) ' note </dev/tty
		result FAIL "$check" "$question $a${note:+ - $note}"
	fi
}

# --------------------------------
# the box's server and its output

strip() { sed -E 's/\x1b\[[0-9;?<>=]*[ -\/]*[@-~]//g; s/\x1b\][^\x07\x1b]*(\x07|\x1b\\)//g; s/\x1b[()][A-Z0-9]//g; s/\x1b[=>78DEHMc]//g; s/\r/\n/g'; }

# copy a unit's output file out of the box as <name>.raw, .catv and .txt
evidence() {
	local name=$1 file=${2:-$OUT/server.log}
	mkdir -p "$RESULTS"
	docker exec "$BOX" cat "$file" >"$RESULTS/$name.raw" 2>/dev/null || : >"$RESULTS/$name.raw"
	cat -v "$RESULTS/$name.raw" >"$RESULTS/$name.catv"
	strip <"$RESULTS/$name.raw" >"$RESULTS/$name.txt"
}

envUrl() { grep -o 'https://claude\.ai/code?environment=env_[A-Za-z0-9_-]*' "$RESULTS/$1.txt" | tail -1 || true; }
# the running server's own environment: other environments with the same name
# can be left over from earlier servers, and a session opened in one goes nowhere
serverUrl() {
	docker exec "$BOX" cat "$OUT/server.log" 2>/dev/null | strip \
		| grep -o 'https://claude\.ai/code?environment=env_[A-Za-z0-9_-]*' | tail -1 || true
}
capacity() { grep -o 'Capacity: [0-9]*/[0-9]*' "$RESULTS/$1.txt" | tail -1 || true; }

setTrust() { # path true|unset
	local expr='.projects //= {} | .projects[$p] //= {} | .projects[$p].hasTrustDialogAccepted = true'
	[[ $2 == unset ]] && expr='del(.projects[$p].hasTrustDialogAccepted)'
	asDev "tmp=\$(mktemp) && jq --arg p '$1' '$expr' ~/.claude.json > \"\$tmp\" && mv \"\$tmp\" ~/.claude.json"
}

# merge a JSON fragment into the box user's ~/.claude/settings.json
mergeSettings() {
	asDev "mkdir -p ~/.claude && f=~/.claude/settings.json && [ -f \$f ] || echo '{}' > \$f; \
		tmp=\$(mktemp) && jq --argjson add '$1' '. * \$add' \$f > \"\$tmp\" && mv \"\$tmp\" \$f"
}
resetSettings() { asDev 'echo "{}" > ~/.claude/settings.json'; }

# one server unit, rewritten per check: workdir, then claude remote-control args
runServer() {
	local dir=$1; shift
	stopServer
	asDev "rm -f $OUT/debug.log"
	asDev "mkdir -p $OUT ~/.config/systemd/user && cat > ~/.config/systemd/user/$UNIT" <<-EOF
		[Unit]
		Description=repo-remote-control confirm: claude remote-control in $dir

		[Service]
		WorkingDirectory=$dir
		Environment=DISABLE_AUTOUPDATER=1
		ExecStart=%h/.local/bin/claude remote-control --debug-file $OUT/debug.log $*
		StandardOutput=truncate:$OUT/server.log
		StandardError=inherit
		Restart=no
	EOF
	userctl daemon-reload
	userctl reset-failed "$UNIT" >/dev/null 2>&1 || true
	userctl start "$UNIT"
	# the previous check's server stays registered for a while after it exits,
	# and a new one in the same folder refuses to start until that clears
	local tries=0
	sleep 5
	while asDev "grep -q 'already served' $OUT/server.log 2>/dev/null"; do
		((++tries > 3)) && { echo "     the folder is still served by another server after 4 tries"; exit 1; }
		echo "     the previous server is still registered; waiting 80s and starting again"
		stopServer
		sleep 80
		userctl start "$UNIT"
		sleep 5
	done
}
stopServer() {
	userctl stop "$UNIT" >/dev/null 2>&1 || true
	userctl reset-failed "$UNIT" >/dev/null 2>&1 || true
}

waitBoot() {
	local state=
	for _ in $(seq 1 60); do
		state=$(docker exec "$BOX" systemctl is-system-running 2>/dev/null || true)
		[[ $state == running || $state == degraded ]] && return 0
		sleep 2
	done
	echo "box did not finish booting (state: $state)"
	exit 1
}

# every check needs the box up and logged in; say which is missing
needBox() {
	needDocker
	if [[ $(docker inspect -f '{{.State.Running}}' "$BOX" 2>/dev/null) != true ]]; then
		docker inspect "$BOX" >/dev/null 2>&1 \
			&& echo "$BOX is stopped: run test/docker/confirm.sh start" \
			|| echo "$BOX does not exist: run test/docker/confirm.sh up"
		exit 1
	fi
	if ! asDev 'claude auth status' >/dev/null 2>&1; then
		echo "claude in $BOX is not logged in: docker exec -it -u $DEV $BOX bash -lc 'claude auth login'"
		exit 1
	fi
	mkdir -p "$RESULTS"
	echo "  claude $(asDev 'claude --version' 2>&1 | head -1)" >>"$RESULTS/summary.txt"
}

# --------------------------------
# up / start / down

up() {
	down quiet

	echo "==> building the box image (systemd, git, jq, tmux, bubblewrap, socat)"
	docker build -q -t "$IMAGE" - >/dev/null <<-'EOF'
		FROM ubuntu:24.04
		ENV DEBIAN_FRONTEND=noninteractive
		RUN apt-get update -qq && apt-get install -y -qq \
			systemd systemd-sysv dbus git jq curl ca-certificates procps sudo \
			tmux bubblewrap socat >/dev/null \
			&& apt-get clean
		RUN systemctl mask getty@tty1.service console-getty.service
		CMD ["/sbin/init"]
	EOF

	echo "==> starting the box with systemd"
	docker run -d --name "$BOX" --hostname "$BOX" \
		--privileged --cgroupns=host -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
		--tmpfs /run --tmpfs /run/lock "$IMAGE" >/dev/null
	waitBoot

	echo "==> user $DEV with linger, Claude Code $CLAUDE_VERSION"
	box "useradd -m -u $DEV_UID -s /bin/bash $DEV && loginctl enable-linger $DEV"
	asDev "curl -fsSL https://claude.ai/install.sh | bash -s $CLAUDE_VERSION >/dev/null"
	asDev 'echo "export PATH=\$HOME/.local/bin:\$PATH" >> ~/.profile'
	# the tmux session updated itself mid-run on 20 Oct; keep $CLAUDE_VERSION
	asDev 'echo "export DISABLE_AUTOUPDATER=1" >> ~/.profile'

	echo "==> a bare origin with main, cloned to $REPO; a scratch repo"
	asDev "git config --global user.name test && git config --global user.email test@example.com \
		&& git init -q --bare -b main $ORIGIN \
		&& git clone -q $ORIGIN $REPO 2>/dev/null && cd $REPO \
		&& git commit -q --allow-empty -m init && git push -q origin main \
		&& git remote set-head origin main"
	asDev "mkdir -p $SCRATCH && cd $SCRATCH && git init -q -b main && git commit -q --allow-empty -m init"

	docker cp "$HERE/fixtures/sessionstart-detach.sh" "$BOX:$H/sessionstart-detach.sh"
	box "chown $DEV: $H/sessionstart-detach.sh && chmod +x $H/sessionstart-detach.sh"

	asDev 'claude --version'
	cat <<-EOF

		Two steps by hand, in your own terminal (not with !):

		  1. Log in with your claude.ai account:

		       docker exec -it -u $DEV $BOX bash -lc 'claude auth login'

		  2. Accept "Enable Remote Control?" once, in the scratch repo. Answer y to
		     both questions, wait for the session URL, then Ctrl+C:

		       docker exec -it -u $DEV -w $SCRATCH $BOX bash -lc 'claude remote-control'

		Then: test/docker/confirm.sh all   (or one check at a time)
	EOF
}

start() {
	needDocker
	docker start "$BOX" >/dev/null
	waitBoot
	echo "$BOX is running"
}

down() {
	needDocker
	if docker exec "$BOX" true >/dev/null 2>&1; then
		stopServer
		docker exec -u "$DEV" "$BOX" bash -lc 'tmux kill-server; claude auth logout' >/dev/null 2>&1 || true
	fi
	docker rm -f "$BOX" >/dev/null 2>&1 || true
	docker rmi "$IMAGE" >/dev/null 2>&1 || true
	[[ ${1:-} == quiet ]] || echo "logged out, removed $BOX and $IMAGE"
}

# --------------------------------
# untrusted-output: does "Workspace not trusted" reach the unit's output, where
# start can read it

untrustedOutput() {
	echo "==> untrusted-output"
	setTrust "$REPO" unset
	runServer "$REPO" --spawn worktree || true
	sleep 15
	evidence untrusted-output
	stopServer
	setTrust "$REPO" true
	if grep -q 'Workspace not trusted' "$RESULTS/untrusted-output.txt"; then
		result PASS untrusted-output "message is in the output: $(grep -m1 'Workspace not trusted' "$RESULTS/untrusted-output.txt" | cut -c1-100)"
	else
		result FAIL untrusted-output "no 'Workspace not trusted' in the output; see untrusted-output.txt"
	fi
}

# --------------------------------
# raw-output: raw output with no terminal: escape codes, how screens are
# delimited, growth

rawOutput() {
	echo "==> raw-output"
	setTrust "$REPO" true
	runServer "$REPO" --spawn worktree --no-create-session-in-dir
	sleep 20
	evidence raw-output-20s
	local a b
	a=$(wc -c <"$RESULTS/raw-output-20s.raw")
	sleep 30
	evidence raw-output-50s
	b=$(wc -c <"$RESULTS/raw-output-50s.raw")
	stopServer

	local raw=$RESULTS/raw-output-50s.raw esc clear home hide
	esc=$(grep -c $'\e' "$raw" || true)
	clear=$(grep -c $'\e\\[2J' "$raw" || true)
	home=$(grep -c $'\e\\[H' "$raw" || true)
	hide=$(grep -c $'\e\\[?25l' "$raw" || true)
	{
		echo "bytes after 20s: $a, after 50s: $b, growth: $(( (b - a) / 30 )) bytes/s"
		echo "lines with ESC: $esc; clear-screen (ESC[2J): $clear; cursor-home (ESC[H): $home; hide-cursor (ESC[?25l): $hide"
		echo "distinct escape sequences:"
		grep -o $'\e\\[[0-9;?]*[A-Za-z]' "$raw" | sort | uniq -c | sort -rn | head -20 | cat -v
		echo "env URL: $(envUrl raw-output-50s)"
		echo "capacity: $(capacity raw-output-50s)"
	} >"$RESULTS/raw-output.stats"
	result INFO raw-output "$a bytes after 20s, $b after 50s; details in raw-output.stats"
	if [[ -n $(envUrl raw-output-50s) ]]; then
		result PASS raw-output "environment URL readable after stripping escape codes"
	else
		result FAIL raw-output "no environment URL after stripping; read raw-output-50s.catv"
	fi
}

# --------------------------------
# name-restart: what --name does, and whether the environment survives a restart

nameRestart() {
	echo "==> name-restart"
	runServer "$REPO" --spawn worktree --no-create-session-in-dir --name rrc-confirm-name
	sleep 20
	evidence name-restart-1
	local u1 u2
	u1=$(envUrl name-restart-1)
	userctl restart "$UNIT"
	sleep 20
	evidence name-restart-2
	u2=$(envUrl name-restart-2)
	grep -q 'rrc-confirm-name' "$RESULTS/name-restart-1.txt" \
		&& result PASS name-restart "--name rrc-confirm-name is in the server output" \
		|| result FAIL name-restart "--name rrc-confirm-name is not in the server output"
	if [[ -n $u1 && $u1 == "$u2" ]]; then
		result PASS name-restart "same environment URL across the restart: $u1"
	else
		result FAIL name-restart "environment URL changed: ${u1:-none} -> ${u2:-none}"
	fi
	if haveTty; then
		tell "In claude.ai/code or the app, start a new session and open the environment selector." \
			"Don't open a session; just look at the list."
		ask name-restart y "Is exactly one environment called $ENV_NAME listed (not two after the restart)?"
		ask name-restart n "Is any environment called rrc-confirm-name listed?"
	fi
	stopServer
}

# --------------------------------
# folder-served: a session-mode process in a repo that already has a server

folderServed() {
	echo "==> folder-served"
	runServer "$REPO" --spawn worktree --no-create-session-in-dir
	sleep 20
	mkdir -p "$RESULTS"
	asDev "cd $REPO && timeout 30 script -qfec 'claude remote-control --spawn session' /dev/null" \
		>"$RESULTS/folder-served.raw" 2>&1 || true
	cat -v "$RESULTS/folder-served.raw" >"$RESULTS/folder-served.catv"
	strip <"$RESULTS/folder-served.raw" >"$RESULTS/folder-served.txt"
	stopServer
	if grep -qiE 'already (being )?served|already_served|already running' "$RESULTS/folder-served.txt"; then
		result INFO folder-served "REFUSED beside a server: $(grep -m1 -iE 'already' "$RESULTS/folder-served.txt" | cut -c1-100)"
	elif grep -q 'https://claude\.ai/code' "$RESULTS/folder-served.txt"; then
		result INFO folder-served "ALLOWED: session mode started beside the server; see folder-served.txt"
	else
		result FAIL folder-served "neither refused nor started; see folder-served.txt"
	fi
}

# --------------------------------
# tmux-queue: text sent with tmux send-keys to a busy interactive session waits
# its turn

tmuxQueue() {
	echo "==> tmux-queue"
	setTrust "$SCRATCH" true
	mkdir -p "$RESULTS"
	asDev "tmp=\$(mktemp) && jq '.hasCompletedOnboarding = true' ~/.claude.json > \"\$tmp\" && mv \"\$tmp\" ~/.claude.json"
	# the harness refuses a foreground sleep and backgrounds it, which leaves the
	# turn idle; timeout+tail holds the Bash call in the foreground instead. The
	# marker file says the call has started, so the second message is only sent
	# once the turn is busy.
	asDev "rm -f ~/rrc-busy-started; tmux kill-session -t orchestrator 2>/dev/null; \
		tmux new-session -d -s orchestrator -x 200 -y 50 -c $SCRATCH \
		\"claude --allowedTools 'Bash(touch:*)' 'Bash(timeout:*)'\""
	sleep 15
	asDev "tmux send-keys -t orchestrator:0 -l 'Run exactly this as one foreground Bash call, not in the background: touch ~/rrc-busy-started && timeout 45 tail -f /dev/null; echo held. Then reply with exactly BUSY-DONE.' && tmux send-keys -t orchestrator:0 Enter"
	local started=no
	for _ in $(seq 1 30); do
		asDev 'test -e ~/rrc-busy-started' && { started=yes; break; }
		sleep 1
	done
	sleep 3
	asDev "tmux capture-pane -p -t orchestrator:0 -S -200" >"$RESULTS/tmux-queue-busy.txt" || true
	if [[ $started == no ]]; then
		asDev "tmux kill-session -t orchestrator" || true
		result FAIL tmux-queue "the busy command never started; read tmux-queue-busy.txt"
		return 0
	fi
	asDev "tmux send-keys -t orchestrator:0 -l 'Reply with exactly QUEUED-OK.' && tmux send-keys -t orchestrator:0 Enter"
	sleep 90
	asDev "tmux capture-pane -p -t orchestrator:0 -S -400" >"$RESULTS/tmux-queue.txt" || true
	asDev "tmux kill-session -t orchestrator; rm -f ~/rrc-busy-started" || true

	local f=$RESULTS/tmux-queue.txt busy queued
	busy=$(grep -n 'BUSY-DONE' "$f" | grep -v 'reply with exactly' | tail -1 | cut -d: -f1 || true)
	queued=$(grep -n 'QUEUED-OK' "$f" | grep -v 'Reply with exactly' | tail -1 | cut -d: -f1 || true)
	if [[ -n $busy && -n $queued && $queued -gt $busy ]]; then
		result PASS tmux-queue "the second message waited and was answered after BUSY-DONE"
	else
		result FAIL tmux-queue "BUSY-DONE line: ${busy:-none}, QUEUED-OK line: ${queued:-none}; read tmux-queue.txt and tmux-queue-busy.txt"
	fi
}

# --------------------------------
# idle-count: does the Capacity count follow sessions opening and closing; and
# does --remote-control-session-name-prefix give the titles rrc will use

idleCount() {
	needTty idle-count || return 0
	echo "==> idle-count"
	runServer "$REPO" --spawn worktree --no-create-session-in-dir \
		--remote-control-session-name-prefix client_hugoboss/web
	sleep 20
	evidence idle-count-0
	local c0 c1 c2
	c0=$(capacity idle-count-0)
	echo "     capacity at start: ${c0:-none}"
	tell "Open $(serverUrl) and start a new session there. Don't pick $ENV_NAME from the list: there can be stale ones." \
		"Send it: reply with OK. Wait for the reply."
	evidence idle-count-1
	c1=$(capacity idle-count-1)
	echo "     capacity with one session: ${c1:-none}"
	ask session-prefix y "Is that session titled client-hugoboss-web-<two words>?"
	tell "End that session in the app (archive or delete it), then wait about 30 seconds."
	evidence idle-count-2
	c2=$(capacity idle-count-2)
	echo "     capacity after ending it: ${c2:-none}"
	stopServer
	if [[ ${c0%%/*} == 'Capacity: 0' && ${c1%%/*} == 'Capacity: 1' && ${c2%%/*} == 'Capacity: 0' ]]; then
		result PASS idle-count "0 -> 1 -> 0: $c0 / $c1 / $c2"
	else
		result FAIL idle-count "expected 0 -> 1 -> 0, got: ${c0:-none} / ${c1:-none} / ${c2:-none}"
	fi
}

# --------------------------------
# sessionstart-detach: SessionStart in a server-spawned worktree: fires, with
# which cwd, in time, and what the server's cleanup does once the generated
# branch is gone

sessionstartDetach() {
	needTty sessionstart-detach || return 0
	echo "==> sessionstart-detach"
	asDev ': > ~/rrc-hook.log'
	mergeSettings "{\"hooks\":{\"SessionStart\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"$H/sessionstart-detach.sh\"}]}]}}"
	runServer "$REPO" --spawn worktree --no-create-session-in-dir
	sleep 20
	tell "Open $(serverUrl) and start a new session there. Don't pick $ENV_NAME from the list: there can be stale ones." \
		"Send it exactly:" \
		"  Run these and show me the output verbatim: pwd; git status | head -3; git branch --show-current; git branch --list 'worktree-*'" \
		"Approve the commands if it asks. Wait for the reply." \
		"Ask it nothing else: the worktree has to stay unchanged for the cleanup part."
	docker exec "$BOX" cat "$H/rrc-hook.log" >"$RESULTS/sessionstart-hook.log" 2>/dev/null || true
	asDev "cd $REPO && git worktree list && echo --- && git branch --list" >"$RESULTS/sessionstart-worktrees.txt" 2>&1 || true

	if ! grep -q '^=== ' "$RESULTS/sessionstart-hook.log"; then
		result FAIL sessionstart-detach "SessionStart did not fire at all (empty hook log)"
	elif ! grep -q '/.claude/worktrees/bridge-' "$RESULTS/sessionstart-hook.log"; then
		result FAIL sessionstart-detach "fired, but not with a .claude/worktrees/bridge-* cwd; see sessionstart-hook.log"
	elif grep -q 'worktree-bridge-' <(asDev "cd $REPO && git branch --list 'worktree-bridge-*'"); then
		result FAIL sessionstart-detach "fired in the worktree, but a worktree-bridge-* branch still exists"
	else
		result PASS sessionstart-detach "fired with the worktree as cwd, HEAD detached, generated branch deleted"
	fi
	# the hook could finish after the session's first command ran
	ask sessionstart-in-time y "Did the session's git status say 'HEAD detached', with an empty branch name and no worktree-bridge-* branch?"

	tell "End that session in the app (archive or delete it), then wait about 30 seconds."
	evidence sessionstart-cleanup
	asDev "cd $REPO && git worktree list && echo --- && git branch --list" >"$RESULTS/sessionstart-after-end.txt" 2>&1 || true
	if grep -qiE 'error|fail' "$RESULTS/sessionstart-cleanup.txt"; then
		result INFO sessionstart-cleanup "server output mentions an error after the session ended; see sessionstart-cleanup.txt"
	fi

	# the session changed nothing, so the only difference from a plain server
	# worktree is the hook's detach. The server keeps a worktree whose "checkout
	# moved"; if the detach counts as that, every unused server worktree is kept
	# and the server's own cleanup never removes one.
	local verdict
	verdict=$(grep -oE '(kept worktree [^ ]*/\.claude/worktrees/bridge-[^ ]* · [^\r\n]*|removed worktree [^ ]*/\.claude/worktrees/bridge-[^ \r\n]*)' \
		"$RESULTS/sessionstart-cleanup.txt" | tail -1 || true)
	if grep -q '/\.claude/worktrees/bridge-' "$RESULTS/sessionstart-after-end.txt"; then
		result FAIL detached-unused-kept "unused detached worktree was KEPT at session end${verdict:+ (server: $verdict)}: the hook's detach blocks the server's cleanup"
	else
		result PASS detached-unused-kept "unused detached worktree was removed at session end${verdict:+ (server: $verdict)}"
	fi
	stopServer
	resetSettings
}

# --------------------------------
# spawn-session: --spawn session is one session that ends the process when it
# ends; --permission-mode applies to it

spawnSession() {
	needTty spawn-session || return 0
	echo "==> spawn-session"
	runServer "$REPO" --spawn session --name rrc-confirm-single --permission-mode plan
	sleep 20
	evidence spawn-session-1
	userctl is-active "$UNIT" >/dev/null 2>&1 \
		&& result PASS spawn-session "process still running 20s after start, with the session open" \
		|| result FAIL spawn-session "process not running 20s after start; see spawn-session-1.txt"
	tell "In claude.ai/code or the app, look at the session list."
	ask spawn-session y "Is there a session already open, without you starting one, in $ENV_NAME?"
	ask spawn-session-name y "Is that session titled rrc-confirm-single?"
	tell "In that session, send: Create a file named plan-mode-check.txt containing hello." \
		"Wait for the reply. Don't approve a plan if it offers one."
	asDev "test -e $REPO/plan-mode-check.txt" \
		&& result FAIL spawn-session "plan-mode-check.txt was written: --permission-mode plan not applied" \
		|| result PASS spawn-session "plan mode held: no file written"
	tell "End that session in the app (archive or delete it), then wait about 30 seconds."
	evidence spawn-session-2
	local state
	state=$(userctl is-active "$UNIT" 2>/dev/null || true)
	[[ $state != active ]] \
		&& result PASS spawn-session "process exited after the session ended (unit: $state)" \
		|| result FAIL spawn-session "process still running after the session ended"
	stopServer
	asDev "rm -f $REPO/plan-mode-check.txt"
}

# --------------------------------
# sandbox-auto: spawned sessions run in auto mode with the sandbox on, under a
# user service. A session sent to a server with both on never arrived on
# 22 Oct, so one run does everything needed to say why: checks that need
# nobody first (bwrap in the box, the sandbox in a plain claude -p), then the
# server three ways: both on, auto alone, sandbox alone. Everything each one
# logs is saved, so nothing has to be run a second time to find out more.

# everything the box has about the server and its sessions, as sandbox-<v>.*
sandboxEvidence() {
	local v=$1
	evidence "sandbox-$v"
	docker exec "$BOX" cat "$OUT/debug.log" >"$RESULTS/sandbox-$v.debug" 2>/dev/null || true
	box "ps -u $DEV -o pid,ppid,etime,args --forest" >"$RESULTS/sandbox-$v.ps" 2>&1 || true
	box "journalctl --user-unit=$UNIT _UID=$DEV_UID --since '-10 min' --no-pager -o short-precise; \
		journalctl _UID=$DEV_UID --since '-10 min' --no-pager -o short-precise | tail -200" \
		>"$RESULTS/sandbox-$v.journal" 2>&1 || true
	# the spawned sessions' own debug logs, newest first, written since the server started
	asDev "find ~/.claude/debug -type f -newer $OUT/server.unit-started 2>/dev/null \
		| xargs -r ls -t | head -5 | while read -r f; do echo \"=== \$f\"; tail -300 \"\$f\"; done" \
		>"$RESULTS/sandbox-$v.session-debug" 2>&1 || true
	asDev "cat ~/.claude/settings.json" >"$RESULTS/sandbox-$v.settings" 2>&1 || true
}

# one server variant: settings fragment ('{}' for none), then --permission-mode
sandboxVariant() {
	local v=$1 settings=$2 mode=$3 mark=$H/outside-sandbox-check-$1
	echo
	echo "==> sandbox-auto, variant $v: settings $settings, --permission-mode $mode"
	resetSettings
	[[ $settings == '{}' ]] || mergeSettings "$settings"
	asDev "rm -f $mark"
	runServer "$REPO" --spawn worktree --no-create-session-in-dir --permission-mode "$mode"
	asDev "touch $OUT/server.unit-started"
	sleep 15
	tell "Open $(serverUrl) and start a new session there. Don't pick $ENV_NAME from the list." \
		"Send it exactly:" \
		"  Tell me your permission mode. Then run, as one Bash call: touch $mark; echo exit=\$?" \
		"Don't approve anything it asks for. Wait up to a minute for a reply, then press Enter either way."
	sandboxEvidence "$v"
	if grep -q 'Capacity: [1-9]' "$RESULTS/sandbox-$v.txt"; then
		result PASS "sandbox-$v" "the session reached the server"
	else
		result FAIL "sandbox-$v" "the session never reached the server (Capacity stayed 0); see sandbox-$v.debug and .session-debug"
	fi
	ask "sandbox-$v" y "Did the session reply at all?"
	ask "sandbox-$v" y "Did it say its permission mode is $mode?"
	if asDev "test -e $mark"; then
		result INFO "sandbox-$v" "the touch outside the worktree ran: $mark exists"
	else
		result INFO "sandbox-$v" "the touch outside the worktree did not run"
	fi
	[[ $settings == '{}' ]] || ask "sandbox-$v" y "Did it say the sandbox blocked the touch, without asking you to approve it?"
	stopServer
	asDev "rm -f $mark"
}

sandboxAuto() {
	needTty sandbox-auto || return 0
	echo "==> sandbox-auto"

	# can bwrap run at all in the box, as the user the server runs as
	asDev "bwrap --ro-bind / / --dev /dev --proc /proc --unshare-net true" >"$RESULTS/sandbox-bwrap.txt" 2>&1 \
		&& result PASS sandbox-bwrap "bwrap runs in the box" \
		|| result FAIL sandbox-bwrap "bwrap fails in the box: $(head -1 "$RESULTS/sandbox-bwrap.txt")"

	# the sandbox in a plain non-interactive session, with no server involved
	setTrust "$REPO" true
	resetSettings
	mergeSettings '{"sandbox":{"enabled":true}}'
	asDev "rm -f $H/outside-sandbox-check-p"
	asDev "cd $REPO && DISABLE_AUTOUPDATER=1 timeout 180 claude -p --permission-mode auto \
		'Tell me your permission mode. Then run, as one Bash call: touch $H/outside-sandbox-check-p; echo exit=\$?. Report the output and any error verbatim.'" \
		>"$RESULTS/sandbox-print.txt" 2>&1 || true
	if asDev "test -e $H/outside-sandbox-check-p"; then
		result FAIL sandbox-print "claude -p with the sandbox on wrote outside the repo; see sandbox-print.txt"
	elif [[ -s $RESULTS/sandbox-print.txt ]]; then
		result PASS sandbox-print "claude -p with the sandbox on ran and the write outside was stopped: $(tr '\n' ' ' <"$RESULTS/sandbox-print.txt" | cut -c1-160)"
	else
		result FAIL sandbox-print "claude -p with the sandbox on printed nothing; see sandbox-print.txt"
	fi
	asDev "rm -f $H/outside-sandbox-check-p"

	sandboxVariant both '{"sandbox":{"enabled":true}}' auto
	sandboxVariant auto-only '{}' auto
	sandboxVariant sandbox-only '{"sandbox":{"enabled":true}}' default
	resetSettings
}

# --------------------------------
# sandbox-rrc: can the orchestrator run rrc from inside its sandbox. rrc start
# reloads systemd over the user bus, writes a unit to ~/.config/systemd/user and
# sets trust in ~/.claude.json; the sandbox may block all three. Runs a stand-in
# rrc that does exactly those through claude -p twice: sandbox on, then sandbox
# on with rrc in sandbox.excludedCommands, which is the fix setup.sh would add.
# The stream-json transcript shows whether Claude ran it as asked or retried
# it outside the sandbox.

sandboxRrc() {
	echo "==> sandbox-rrc"
	setTrust "$REPO" true
	asDev "mkdir -p ~/.local/bin && cat > ~/.local/bin/rrc && chmod +x ~/.local/bin/rrc" <<-'EOF2'
		#!/usr/bin/env bash
		# stand-in for rrc, from confirm.sh sandbox-rrc: what rrc start does outside the repo
		systemctl --user daemon-reload 2>&1 && echo bus-ok || echo bus-FAILED
		mkdir -p ~/.config/systemd/user 2>&1 && touch ~/.config/systemd/user/rrc-probe.service 2>&1 \
			&& echo unit-dir-ok || echo unit-dir-FAILED
		tmp=~/.claude.json.rrc-probe
		jq '.rrcProbe = true' ~/.claude.json >"$tmp" 2>&1 && mv "$tmp" ~/.claude.json 2>&1 \
			&& echo claude-json-ok || { rm -f "$tmp" 2>/dev/null; echo claude-json-FAILED; }
	EOF2

	local v settings out bus unit json calls unsandboxed
	for v in sandboxed excluded; do
		case $v in
			sandboxed) settings='{"sandbox":{"enabled":true}}' ;;
			excluded) settings='{"sandbox":{"enabled":true,"excludedCommands":["rrc"]}}' ;;
		esac
		echo "     $v: $settings"
		resetSettings
		mergeSettings "$settings"
		asDev "rm -f ~/.config/systemd/user/rrc-probe.service; \
			tmp=\$(mktemp) && jq 'del(.rrcProbe)' ~/.claude.json > \"\$tmp\" && mv \"\$tmp\" ~/.claude.json"
		out=$RESULTS/sandbox-rrc-$v.jsonl
		asDev "cd $REPO && DISABLE_AUTOUPDATER=1 timeout 180 claude -p --permission-mode auto \
			--allowedTools 'Bash(rrc:*)' --output-format stream-json --verbose \
			'Run the command rrc, exactly as written, as one Bash call with the default sandbox setting. Show me its output verbatim. If it fails, do not retry it in any other way.' \
			</dev/null" >"$out" 2>"$RESULTS/sandbox-rrc-$v.stderr" || true

		# what Claude actually ran, and the output it got back
		jq -r 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use") | .input | tostring' \
			"$out" >"$RESULTS/sandbox-rrc-$v.calls" 2>/dev/null || true
		jq -r 'select(.type=="user") | .message.content[]? | select(.type=="tool_result") | .content | if type=="array" then map(.text? // "") | join("\n") else . end' \
			"$out" >"$RESULTS/sandbox-rrc-$v.output" 2>/dev/null || true
		calls=$(wc -l <"$RESULTS/sandbox-rrc-$v.calls")
		unsandboxed=$(grep -c '"dangerouslyDisableSandbox":true' "$RESULTS/sandbox-rrc-$v.calls" || true)

		# the box's own state says whether each write happened, whatever Claude reported
		bus=FAILED; unit=FAILED; json=FAILED
		grep -q 'bus-ok' "$RESULTS/sandbox-rrc-$v.output" && bus=ok
		asDev 'test -e ~/.config/systemd/user/rrc-probe.service' && unit=ok
		asDev "jq -e '.rrcProbe == true' ~/.claude.json >/dev/null" && json=ok

		if ((calls == 0)); then
			result FAIL "sandbox-rrc-$v" "Claude never ran rrc; see sandbox-rrc-$v.jsonl and .stderr"
		elif ((calls > 1 || unsandboxed > 0)); then
			result FAIL "sandbox-rrc-$v" "Claude made $calls Bash calls, $unsandboxed with the sandbox off: the result below is not the sandbox's; see sandbox-rrc-$v.calls"
		fi
		result INFO "sandbox-rrc-$v" "user bus: $bus, unit dir write: $unit, ~/.claude.json write: $json"
		[[ $v == sandboxed && $bus == FAILED && $unit == FAILED && $json == FAILED ]] \
			&& result INFO sandbox-rrc "the sandbox blocks all three: rrc cannot run sandboxed"
		if [[ $v == excluded ]]; then
			[[ $bus == ok && $unit == ok && $json == ok ]] \
				&& result PASS sandbox-rrc "excludedCommands [\"rrc\"] lets rrc do all three from the sandboxed session" \
				|| result FAIL sandbox-rrc "with rrc in excludedCommands: bus $bus, unit dir $unit, ~/.claude.json $json"
		fi
	done

	asDev "rm -f ~/.local/bin/rrc ~/.config/systemd/user/rrc-probe.service; systemctl --user daemon-reload; \
		tmp=\$(mktemp) && jq 'del(.rrcProbe)' ~/.claude.json > \"\$tmp\" && mv \"\$tmp\" ~/.claude.json" || true
	resetSettings
}

# --------------------------------
# refused-exit: a server refused as "already served" exits in about 70
# seconds. rrc relies on Restart=on-failure to retry it, which only happens if
# it exits with an error. A second unit in the same folder as a running server
# is refused the same way, so this starts one and reads how it ended.

refusedExit() {
	echo "==> refused-exit"
	local second=rrc-confirm-second.service status result
	setTrust "$REPO" true
	runServer "$REPO" --spawn worktree --no-create-session-in-dir
	sleep 15
	asDev "cat > ~/.config/systemd/user/$second" <<-EOF2
		[Unit]
		Description=repo-remote-control confirm: a second server in $REPO

		[Service]
		WorkingDirectory=$REPO
		ExecStart=%h/.local/bin/claude remote-control --spawn worktree --no-create-session-in-dir
		StandardOutput=truncate:$OUT/second.log
		StandardError=inherit
		Restart=no
	EOF2
	userctl daemon-reload
	userctl reset-failed "$second" >/dev/null 2>&1 || true
	userctl start "$second"
	echo "     waiting up to 120s for the refused server to exit"
	for _ in $(seq 1 60); do
		userctl is-active --quiet "$second" || break
		sleep 2
	done
	evidence refused-exit "$OUT/second.log"
	status=$(userctl show -p ExecMainStatus --value "$second" 2>/dev/null || true)
	result=$(userctl show -p Result --value "$second" 2>/dev/null || true)
	userctl stop "$second" >/dev/null 2>&1 || true
	stopServer
	if ! grep -q 'already served' "$RESULTS/refused-exit.txt"; then
		result FAIL refused-exit "the second server was not refused; see refused-exit.txt"
	elif [[ $status != 0 && -n $status ]]; then
		result PASS refused-exit "refused server exited with status $status (Result=$result): Restart=on-failure retries it"
	else
		result FAIL refused-exit "refused server exited with status ${status:-unknown} (Result=$result): Restart=on-failure would not retry it"
	fi
}

# --------------------------------

auto() {
	untrustedOutput
	rawOutput
	nameRestart
	folderServed
	tmuxQueue
	sandboxRrc
	refusedExit
}

app() {
	idleCount
	sessionstartDetach
	spawnSession
	sandboxAuto
}

case ${1:-} in
	idle-count | sessionstart-detach | spawn-session | sandbox-auto | app | all) needTerminal "$1" ;;
esac

case ${1:-} in
	up) up; exit 0 ;;
	start) start; exit 0 ;;
	down) down; exit 0 ;;
	untrusted-output) needBox; untrustedOutput ;;
	raw-output) needBox; rawOutput ;;
	name-restart) needBox; nameRestart ;;
	folder-served) needBox; folderServed ;;
	tmux-queue) needBox; tmuxQueue ;;
	sandbox-rrc) needBox; sandboxRrc ;;
	refused-exit) needBox; refusedExit ;;
	idle-count) needBox; idleCount ;;
	sessionstart-detach) needBox; sessionstartDetach ;;
	spawn-session) needBox; spawnSession ;;
	sandbox-auto) needBox; sandboxAuto ;;
	auto) needBox; auto ;;
	app) needBox; app ;;
	all) needBox; auto; app ;;
	*) sed -n '2,/^$/p' "$0"; exit 1 ;;
esac

echo
echo "Results ($RESULTS):"
cat "$RESULTS/summary.txt"
