#!/usr/bin/env bash
# Tests for repo-remote-control-session.
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
# rrc keeps every session's settings and output in the skill's state/, so a
# reinstall that dropped it would lose them. The kit's place() keeps it; this
# checks that against this package's own installer.
SD="$TMP/state-claude"
CLAUDE_DIR="$SD" "$REPO/install.sh" --yes >/dev/null 2>&1
mkdir -p "$SD/skills/repo-remote-control-session/state/sessions"
echo kept >"$SD/skills/repo-remote-control-session/state/sessions/x.env"
CLAUDE_DIR="$SD" "$REPO/install.sh" --yes >"$TMP/out" 2>&1
grep -q kept "$SD/skills/repo-remote-control-session/state/sessions/x.env" 2>/dev/null \
  && ok "a reinstall keeps state/" || no "a reinstall keeps state/" "$(tail -3 "$TMP/out")"
CLAUDE_DIR="$SD" "$REPO/uninstall.sh" --yes >/dev/null 2>&1

echo "the sandbox exclusion"
# rrc only works outside Claude's sandbox, so the install has to add it to
# sandbox.excludedCommands itself, next to whatever is there, and the
# uninstall has to take only it out again.
XD="$TMP/x-claude"; mkdir -p "$XD"
printf '{"sandbox":{"enabled":true,"network":{"allowedDomains":["example.com"]},"excludedCommands":["docker *"]},"model":"m"}\n' >"$XD/settings.json"
CLAUDE_DIR="$XD" "$REPO/install.sh" --yes >"$TMP/out" 2>&1
jq -e '.sandbox.excludedCommands == ["docker *","rrc *"] and .sandbox.enabled == true
  and .sandbox.network.allowedDomains == ["example.com"] and .model == "m"' "$XD/settings.json" >/dev/null \
  && ok "install adds \"rrc *\" beside the existing exclusions and leaves the rest of sandbox alone" \
  || no "install adds \"rrc *\" beside the existing exclusions and leaves the rest of sandbox alone" "$(cat "$XD/settings.json")"
cp "$XD/settings.json" "$TMP/before"
CLAUDE_DIR="$XD" "$REPO/install.sh" --yes >/dev/null 2>&1
cmp -s "$TMP/before" "$XD/settings.json" \
  && ok "a second install leaves settings.json byte-identical" || no "a second install leaves settings.json byte-identical" "$(diff "$TMP/before" "$XD/settings.json")"
CLAUDE_DIR="$XD" "$REPO/uninstall.sh" --yes --keep-settings >/dev/null 2>&1
jq -e '.sandbox.excludedCommands | index("rrc *")' "$XD/settings.json" >/dev/null \
  && ok "uninstall --keep-settings keeps the exclusion" || no "uninstall --keep-settings keeps the exclusion" "$(cat "$XD/settings.json")"
CLAUDE_DIR="$XD" "$REPO/install.sh" --yes >/dev/null 2>&1
# The exclusion comes out in pre_uninstall, which the tests' uninstalls skip
# (KIT_SKIP_MACHINE_HOOKS=1): it also runs rrc teardown, against the real
# systemd. So strip_excluded is called here on its own.
CLAUDE_DIR="$XD" "$REPO/uninstall.sh" --yes >"$TMP/out" 2>&1
(CLAUDE_DIR="$XD"; . "$REPO/manifest.sh"; strip_excluded) >>"$TMP/out" 2>&1
jq -e '.sandbox.excludedCommands == ["docker *"] and .sandbox.enabled == true
  and .sandbox.network.allowedDomains == ["example.com"]' "$XD/settings.json" >/dev/null \
  && ok "uninstall removes \"rrc *\" and nothing else" || no "uninstall removes \"rrc *\" and nothing else" "$(cat "$XD/settings.json") $(tail -5 "$TMP/out")"
printf '{"sandbox":{"enabled":true}}\n' >"$XD/settings.json"
CLAUDE_DIR="$XD" "$REPO/install.sh" --yes >/dev/null 2>&1
CLAUDE_DIR="$XD" "$REPO/uninstall.sh" --yes >/dev/null 2>&1
(CLAUDE_DIR="$XD"; . "$REPO/manifest.sh"; strip_excluded) >/dev/null 2>&1
jq -e '.sandbox == {"enabled": true}' "$XD/settings.json" >/dev/null \
  && ok "an exclusion list rrc alone made is removed whole" || no "an exclusion list rrc alone made is removed whole" "$(cat "$XD/settings.json")"

echo "rrc"
# claude is a stand-in: the real one would open real sessions. It records its
# directory and arguments, prints an output captured in the Docker checks, as
# claude remote-control does, and stays running until killed, unless
# STUB_EXIT is set. systemctl is a stand-in too, for the server check and the
# 1.0.0 cleanup in teardown. Everything else is real: git repos, setsid, the
# PID files, /proc, jq on a real ~/.claude.json.
RRC="$REPO/skill/bin/rrc"
FIX="$REPO/test/fixtures"
STUB="$TMP/stub"; mkdir -p "$STUB/bin"
export RRC_SKILL_DIR="$REPO/skill" RRC_STATE="$TMP/rrc-state" RRC_WAIT=5 RRC_POLL=0.1 STUB
export RRC_CLAUDE="$STUB/bin/claude"
export PATH="$STUB/bin:$PATH"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com
trap 'pkill -f -- "$STUB/bin/claude" 2>/dev/null; rm -rf "$TMP"' EXIT
cat >"$STUB/bin/claude" <<'EOF'
#!/usr/bin/env bash
n=$(( $(cat "$STUB/starts" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$STUB/starts"
pwd >"$STUB/cwd.$n"; printf '%s\n' "$@" >"$STUB/args.$n"
f="$STUB/output.$n"; [ -f "$f" ] || f="$STUB/output"
[ -f "$f" ] && cat "$f"
[ -n "${STUB_EXIT:-}" ] && exit 1
while :; do sleep 0.2; done
EOF
cat >"$STUB/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$STUB/calls"
case " $* " in
  *" is-active "*) for a in "$@"; do u=$a; done; [ "$(cat "$STUB/units/$u.state" 2>/dev/null)" = active ] ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$STUB/bin/claude" "$STUB/bin/systemctl"
stopAll() { pkill -f -- "$STUB/bin/claude" 2>/dev/null; sleep 0.3; rm -f "$RRC_STATE"/sessions/*.pid; }
fresh() { stopAll; rm -rf "$STUB/units" "$STUB/calls" "$STUB"/output* "$STUB"/starts "$STUB"/args.* "$STUB"/cwd.*; }
starts() { cat "$STUB/starts" 2>/dev/null || echo 0; }
repo() { # path: a git repo with one commit
  mkdir -p "$1"; git -C "$1" init -q; git -C "$1" commit -q --allow-empty -m init
  (cd "$1" && pwd -P)
}
inst() { systemd-escape --path "$1"; }
pidIn() { sed -n 's/^RRC_PID=//p' "$RRC_STATE/sessions/$1.pid" 2>/dev/null; }
alive() { [ -n "$1" ] && [ -d "/proc/$1" ] && tr '\0' ' ' <"/proc/$1/cmdline" 2>/dev/null | grep -q remote-control; }

printf '{"sandbox":{"enabled":true}}\n' >"$CLAUDE_DIR/settings.json"
printf '{"numStartups":5,"projects":{"/elsewhere":{"hasTrustDialogAccepted":true}}}\n' >"$HOME/.claude.json"
SURL=https://claude.ai/code/session_01G8282bitpmbotQCQAB569H
SES=$(repo "$HOME/repos/one-off"); mkdir -p "$SES/src"; SI=$(inst "$SES")

mkdir -p "$TMP/plain"
out=$("$RRC" session "$TMP/plain" 2>&1); rc=$?
[ "$rc" != 0 ] && grep -q 'not in a git repository' <<<"$out" \
  && ok "session refuses a directory outside git" || no "session refuses a directory outside git" "rc=$rc $out"

printf '{}\n' >"$CLAUDE_DIR/settings.json"; fresh
out=$("$RRC" session "$SES" 2>&1); rc=$?
[ "$rc" = 3 ] && grep -q 'Ask the user' <<<"$out" && [ "$(starts)" = 0 ] \
  && [ ! -f "$RRC_STATE/sessions/$SI.pid" ] \
  && ! jq -e --arg p "$SES" '.projects[$p]' "$HOME/.claude.json" >/dev/null \
  && ok "session with the sandbox off stops before trust or starting anything, and says to ask" \
  || no "session with the sandbox off stops before trust or starting anything, and says to ask" "rc=$rc $out"
printf '{"sandbox":{"enabled":true}}\n' >"$CLAUDE_DIR/settings.json"

out=$("$RRC" session "$SES" --permission-mode sometimes 2>&1); rc=$?
[ "$rc" != 0 ] && grep -q 'must be one of' <<<"$out" \
  && ok "session refuses an unknown permission mode" || no "session refuses an unknown permission mode" "rc=$rc $out"

fresh; cp "$FIX/session-ready.out" "$STUB/output"
out=$(cd "$SES/src" && "$RRC" session --name "fix the login page" 2>"$TMP/err"); rc=$?
[ "$rc" = 0 ] && [ "$out" = "$SES"$'\n'"$SURL" ] && grep -q 'never comes back at boot' "$TMP/err" \
  && ok "session from a subdirectory starts one session in the repo root and prints its URL" \
  || no "session from a subdirectory starts one session in the repo root and prints its URL" "rc=$rc $out $(cat "$TMP/err")"
[ "$(cat "$STUB/cwd.1")" = "$SES" ] \
  && [ "$(cat "$STUB/args.1")" = $'remote-control\n--spawn\nsession\n--permission-mode\nauto\n--name\nfix the login page' ] \
  && ok "session: claude runs in the root, auto mode by default, its title one argument with its spaces" \
  || no "session: claude runs in the root, auto mode by default, its title one argument with its spaces" "$(cat "$STUB/cwd.1") $(cat "$STUB/args.1")"
pid=$(pidIn "$SI")
alive "$pid" && [ "$(readlink "/proc/$pid/cwd")" = "$SES" ] && [ "$(ps -o sid= -p "$pid" | tr -d ' ')" = "$pid" ] \
  && ok "the PID file names the claude process, in a session of its own, after rrc has exited" \
  || no "the PID file names the claude process, in a session of its own, after rrc has exited" "pid=$pid $(cat "$RRC_STATE/sessions/$SI.pid" 2>&1)"
jq -e --arg p "$SES" '.projects[$p].hasTrustDialogAccepted == true and .numStartups == 5
  and .projects["/elsewhere"].hasTrustDialogAccepted == true' "$HOME/.claude.json" >/dev/null \
  && ok "trust is set and the rest of ~/.claude.json kept" || no "trust is set and the rest of ~/.claude.json kept" "$(cat "$HOME/.claude.json")"
[ "$(ls "$RRC_STATE"/backups/claude.json.* 2>/dev/null | wc -l)" = 1 ] \
  && ok "~/.claude.json is backed up before the change" || no "~/.claude.json is backed up before the change" "$(ls "$RRC_STATE"/backups 2>&1)"
[ ! -e "$HOME/.config/systemd/user" ] && ! grep -qvE ' is-active ' "$STUB/calls" 2>/dev/null \
  && ok "session links no unit and asks systemd nothing but whether a server runs" \
  || no "session links no unit and asks systemd nothing but whether a server runs" "$(cat "$STUB/calls" 2>&1) $(ls "$HOME/.config/systemd/user" 2>&1)"

s0=$SECONDS
out=$("$RRC" session "$SES" 2>"$TMP/err"); rc=$?
[ "$rc" = 0 ] && [ "${out#*$'\n'}" = "$SURL" ] && [ "$(starts)" = 1 ] && grep -q 'already running' "$TMP/err" \
  && [ $((SECONDS - s0)) -lt 5 ] \
  && ok "session while one is running hands out its URL at once, without starting another" \
  || no "session while one is running hands out its URL at once, without starting another" "rc=$rc $out starts=$(starts) $((SECONDS - s0))s"

out=$("$RRC" list 2>&1)
grep -qx "$SES" <<<"$out" && grep -qx '  one session, running' <<<"$out" && grep -qx "  $SURL" <<<"$out" \
  && ok "list shows a running session and its URL" || no "list shows a running session and its URL" "$out"

# a PID file whose PID now belongs to something else
fresh; (cd "$SES" && exec sleep 30) & other=$!
mkdir -p "$RRC_STATE/sessions"; printf 'RRC_PID=%s\nRRC_ROOT="%s"\n' "$other" "$SES" >"$RRC_STATE/sessions/$SI.pid"
out=$("$RRC" list 2>&1)
grep -q 'no session is running' <<<"$out" && [ ! -f "$RRC_STATE/sessions/$SI.pid" ] \
  && ok "a reused PID is not a session: list ignores it and drops the PID file" \
  || no "a reused PID is not a session: list ignores it and drops the PID file" "$out"
printf 'RRC_PID=%s\nRRC_ROOT="%s"\n' "$other" "$SES" >"$RRC_STATE/sessions/$SI.pid"
cp "$FIX/session-ready.out" "$STUB/output"
out=$("$RRC" session "$SES" 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$(starts)" = 1 ] && [ -d "/proc/$other" ] \
  && ok "session over a reused PID starts a new one and leaves that process alone" \
  || no "session over a reused PID starts a new one and leaves that process alone" "rc=$rc starts=$(starts) $out"
kill "$other" 2>/dev/null

# claude's pointer to the folder's last session: resumed by the next start
fresh; ODD=$(repo "$HOME/repos/my_app.v2"); OI=$(inst "$ODD")
PD="$CLAUDE_DIR/projects/$(printf '%s' "$ODD" | sed 's/[^A-Za-z0-9]/-/g')"
case $PD in */-*-repos-my-app-v2) ;; *) no "the pointer's folder name" "$PD" ;; esac
mkdir -p "$PD"; printf '{"sessionId":"session_old","pid":999999999}\n' >"$PD/bridge-pointer.json"
cp "$FIX/session-ready.out" "$STUB/output"
out=$("$RRC" session "$ODD" 2>&1); rc=$?
[ "$rc" = 0 ] && [ ! -f "$PD/bridge-pointer.json" ] \
  && ok "a pointer to a session no live process holds is deleted before the start" \
  || no "a pointer to a session no live process holds is deleted before the start" "rc=$rc $out $(ls "$PD")"
pid=$(pidIn "$OI"); printf '{"sessionId":"session_live","pid":%s}\n' "$pid" >"$PD/bridge-pointer.json"
rm -f "$RRC_STATE/sessions/$OI.pid"; cp "$FIX/session-ready.out" "$STUB/output"
"$RRC" session "$ODD" >/dev/null 2>&1
grep -q session_live "$PD/bridge-pointer.json" 2>/dev/null \
  && ok "a pointer a live remote-control holds is left alone" || no "a pointer a live remote-control holds is left alone" "$(cat "$PD/bridge-pointer.json" 2>&1)"

DEMO=$(repo "$HOME/repos/demo"); DI=$(inst "$DEMO"); fresh
cp "$FIX/server-untrusted.out" "$STUB/output.1"; cp "$FIX/session-ready.out" "$STUB/output.2"
out=$("$RRC" session "$DEMO" 2>"$TMP/err"); rc=$?
[ "$rc" = 0 ] && [ "${out#*$'\n'}" = "$SURL" ] && grep -q 'not trusted' "$TMP/err" && [ "$(starts)" = 2 ] \
  && [ "$(pgrep -fc -- "$STUB/bin/claude")" = 1 ] \
  && ok "\"Workspace not trusted\" in the output: trust set again, restarted once, the first one stopped" \
  || no "\"Workspace not trusted\" in the output: trust set again, restarted once, the first one stopped" "rc=$rc $out $(cat "$TMP/err") starts=$(starts)"

SLOW=$(repo "$HOME/repos/slow"); SLI=$(inst "$SLOW"); fresh; printf 'Error: nothing yet\n' >"$STUB/output"
out=$(RRC_WAIT=1 "$RRC" session "$SLOW" 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q 'no URL after 1s, so the session was stopped. Last error: Error: nothing yet' <<<"$out" \
  && ! pgrep -f -- "$STUB/bin/claude" >/dev/null && [ ! -f "$RRC_STATE/sessions/$SLI.pid" ] \
  && ok "no URL in time: stops the session and fails with the last error" || no "no URL in time: stops the session and fails with the last error" "rc=$rc $out"

EARLY=$(repo "$HOME/repos/early"); fresh; printf 'Error: boom\n' >"$STUB/output"
out=$(STUB_EXIT=1 "$RRC" session "$EARLY" 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q 'the session exited. Last error: Error: boom' <<<"$out" \
  && ok "a session that exits before its URL fails with the last error" || no "a session that exits before its URL fails with the last error" "rc=$rc $out"

# A folder is refused for up to about 3 minutes after its last session stops
# (Docker, 2 Nov), so rrc waits that out, retrying.
LATE=$(repo "$HOME/repos/late"); LTI=$(inst "$LATE"); fresh
cp "$FIX/server-already-served.out" "$STUB/output.1"; cp "$FIX/server-already-served.out" "$STUB/output.2"
cp "$FIX/session-ready.out" "$STUB/output.3"
out=$(RRC_REFUSED_RETRY=0.2 "$RRC" session "$LATE" 2>"$TMP/err"); rc=$?
[ "$rc" = 0 ] && [ "${out#*$'\n'}" = "$SURL" ] && [ "$(starts)" = 3 ] && grep -q 'still registered' "$TMP/err" \
  && [ "$(grep -c 'still registered' "$TMP/err")" = 1 ] && [ "$(pgrep -fc -- "$STUB/bin/claude")" = 1 ] \
  && ok "a session refused as \"already served\" is stopped and retried until the folder is free, saying so once" \
  || no "a session refused as \"already served\" is stopped and retried until the folder is free, saying so once" "rc=$rc $out starts=$(starts) $(cat "$TMP/err")"
fresh; cp "$FIX/server-already-served.out" "$STUB/output"
out=$(RRC_REFUSED_WAIT=1 RRC_REFUSED_RETRY=0.2 "$RRC" session "$LATE" 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q 'still refused after 1s' <<<"$out" && ! pgrep -f -- "$STUB/bin/claude" >/dev/null \
  && [ ! -f "$RRC_STATE/sessions/$LTI.pid" ] \
  && ok "still refused when the wait runs out: stopped, and says to try again in a few minutes" \
  || no "still refused when the wait runs out: stopped, and says to try again in a few minutes" "rc=$rc $out"

# A server in the folder belongs to repo-remote-control-server. A stand-in
# rrcd answers for its URL, as the real one does from the server's output.
SRV=$(repo "$HOME/repos/served"); SVI=$(inst "$SRV"); fresh
mkdir -p "$STUB/units"; echo active >"$STUB/units/rrc-server@$SVI.service.state"
printf '#!/usr/bin/env bash\n[ "$1" = url ] && echo https://claude.ai/code?environment=env_01SERVER\n' >"$STUB/bin/rrcd"; chmod +x "$STUB/bin/rrcd"
out=$("$RRC" session "$SRV" 2>&1); rc=$?
[ "$rc" != 0 ] && grep -q "has a server" <<<"$out" && grep -qF 'env_01SERVER' <<<"$out" && [ "$(starts)" = 0 ] \
  && ok "session in a repo with a server is refused and hands out the server's URL from rrcd" \
  || no "session in a repo with a server is refused and hands out the server's URL from rrcd" "rc=$rc $out"
rm -f "$STUB/bin/rrcd"
out=$("$RRC" session "$SRV" 2>&1); rc=$?
[ "$rc" != 0 ] && grep -q 'run rrcd list' <<<"$out" \
  && ok "with no rrcd on PATH, the refusal says where the URL is" || no "with no rrcd on PATH, the refusal says where the URL is" "rc=$rc $out"

fresh; cp "$FIX/session-ready.out" "$STUB/output"; "$RRC" session "$SES" >/dev/null 2>&1; pid=$(pidIn "$SI")
mkdir -p "$HOME/.config/systemd/user"; ln -s "$REPO/skill/missing@.service" "$HOME/.config/systemd/user/rrc-session@.service"
out=$("$RRC" teardown 2>&1); rc=$?
sleep 0.3
[ "$rc" = 0 ] && ! alive "$pid" && [ ! -f "$RRC_STATE/sessions/$SI.pid" ] && [ -f "$RRC_STATE/logs/$SI.session.log" ] \
  && ok "teardown stops every session and drops its PID file, keeping its output" \
  || no "teardown stops every session and drops its PID file, keeping its output" "rc=$rc $out"
[ ! -L "$HOME/.config/systemd/user/rrc-session@.service" ] && grep -qF -- "--user stop rrc-session@*" "$STUB/calls" \
  && grep -qF -- "--user reset-failed rrc-session@*" "$STUB/calls" \
  && ok "teardown stops and unlinks a 1.0.0 session unit" || no "teardown stops and unlinks a 1.0.0 session unit" "$(cat "$STUB/calls" 2>&1)"
out=$("$RRC" list 2>&1)
grep -q 'no session is running' <<<"$out" && ok "list with nothing running says how to start one" || no "list with nothing running says how to start one" "$out"

out=$("$RRC" frobnicate 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q 'usage: rrc' <<<"$out" && ok "an unknown command prints usage" || no "an unknown command prints usage" "rc=$rc"

# repo-remote-control-server's rrcd sources the library, so loading it must
# only define things: no output, no set -e, no PROG of its own.
LIB="$REPO/skill/lib/rrc-lib.sh"
out=$(bash -c 'before=$-; . "$1"; type -t setTrust; type -t waitForUrl; echo "v=$RRC_LIB_VERSION prog=${PROG:-unset} opts=$([ "$-" = "$before" ] && echo same)"' _ "$LIB" 2>&1); rc=$?
[ "$rc" = 0 ] && [ "$out" = $'function\nfunction\nv=1 prog=unset opts=same' ] \
  && ok "loading the library defines its functions and version, and runs nothing" \
  || no "loading the library defines its functions and version, and runs nothing" "rc=$rc $out"
mkdir -p "$TMP/no-lib"
out=$(RRC_SKILL_DIR="$TMP/no-lib" "$RRC" list 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q 'not installed: no .*/lib/rrc-lib.sh' <<<"$out" \
  && ok "rrc without its library says the skill is not installed" || no "rrc without its library says the skill is not installed" "rc=$rc $out"

echo "the shared ~/.claude.json lock"
# rrc and rrcd hold different package locks, so editClaudeJson takes one of
# its own. Two writers with separate STATE directories stand in for rrc and
# rrcd, each trusting its own repos at the same time; without the shared lock
# a later mv drops keys the other wrote.
LJ="$TMP/lock-claude.json"; printf '{"projects":{}}\n' >"$LJ"
writer() { # name
	RRC_CLAUDE_JSON="$LJ" bash -c 'PROG=$1 STATE=$2; . "$3"
		for i in $(seq 1 15); do setTrust "/$1/$i"; done' _ "$1" "$TMP/lock-state-$1" "$LIB"
}
writer rrc & p1=$!; writer rrcd & p2=$!; wait "$p1" "$p2"
n=$(jq '[.projects[] | select(.hasTrustDialogAccepted == true)] | length' "$LJ")
[ "$n" = 30 ] && ok "two writers at once keep every trust key (30 of 30)" || no "two writers at once keep every trust key (30 of 30)" "$n of 30: $(jq -c '.projects | keys' "$LJ")"
out=$(RRC_CLAUDE_JSON="$LJ" bash -c 'PROG=t STATE=$1; . "$2"; setTrust /after; flock -n "$CLAUDE_JSON_LOCK" true && echo free' _ "$TMP/lock-state-t" "$LIB" 2>&1)
[ "$out" = free ] && ok "the lock is released as soon as the edit is done" || no "the lock is released as soon as the edit is done" "$out"
flock "$CLAUDE_DIR/.rrc-claude-json.lock" sleep 1 & p=$!; sleep 0.2
s0=$(date +%s%N)
RRC_CLAUDE_JSON="$LJ" bash -c 'PROG=t STATE=$1; . "$2"; setTrust /waited' _ "$TMP/lock-state-t" "$LIB"
ms=$(( ($(date +%s%N) - s0) / 1000000 )); wait "$p"
[ "$ms" -ge 600 ] && jq -e '.projects["/waited"].hasTrustDialogAccepted' "$LJ" >/dev/null \
  && ok "an edit waits while another holds the lock, then goes ahead" || no "an edit waits while another holds the lock, then goes ahead" "waited ${ms}ms"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
