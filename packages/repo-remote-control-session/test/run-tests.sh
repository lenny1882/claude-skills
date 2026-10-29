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
CLAUDE_DIR="$XD" "$REPO/uninstall.sh" --yes >"$TMP/out" 2>&1
jq -e '.sandbox.excludedCommands == ["docker *"] and .sandbox.enabled == true
  and .sandbox.network.allowedDomains == ["example.com"]' "$XD/settings.json" >/dev/null \
  && ok "uninstall removes \"rrc *\" and nothing else" || no "uninstall removes \"rrc *\" and nothing else" "$(cat "$XD/settings.json") $(tail -5 "$TMP/out")"
printf '{"sandbox":{"enabled":true}}\n' >"$XD/settings.json"
CLAUDE_DIR="$XD" "$REPO/install.sh" --yes >/dev/null 2>&1
CLAUDE_DIR="$XD" "$REPO/uninstall.sh" --yes >/dev/null 2>&1
jq -e '.sandbox == {"enabled": true}' "$XD/settings.json" >/dev/null \
  && ok "an exclusion list rrc alone made is removed whole" || no "an exclusion list rrc alone made is removed whole" "$(cat "$XD/settings.json")"

echo "rrc"
# Unit names hold systemd-escape's \x2d for every "-" in the path, so tests
# match calls with grep -F.
# systemctl is a stand-in: no systemd here, and the real one would start real
# sessions. It records each call, keeps unit state in files, and on start plays
# an output captured in the Docker checks into the unit's log, as the unit's
# StandardOutput=truncate: does. Everything else is real: git repos,
# systemd-escape, jq on a real ~/.claude.json.
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
    *) echo active >"$s.state"; return ;;
  esac
  n=$(( $(cat "$s.starts" 2>/dev/null || echo 0) + 1 )); echo "$n" >"$s.starts"
  f="$STUB/output.$n"; [ -f "$f" ] || f="$STUB/output"
  if [ -f "$f" ]; then cat "$f" >"$RRC_STATE/logs/$log"; fi
  if [ -n "${STUB_FAIL:-}" ]; then echo failed >"$s.state"; else echo active >"$s.state"; fi
}
show() { [ "$quiet" = 1 ] || echo "$1"; }
case $verb in
  daemon-reload|reset-failed) ;;
  start|restart) play ;;
  stop) echo inactive >"$s.state" ;;
  is-active) st=$(cat "$s.state" 2>/dev/null || echo inactive); show "$st"; [ "$st" = active ]; exit ;;
  is-failed) st=$(cat "$s.state" 2>/dev/null || echo inactive); show "$st"; [ "$st" = failed ]; exit ;;
  *) echo "stub systemctl: unexpected: $*" >&2; exit 1 ;;
esac
exit 0
EOF
chmod +x "$STUB/bin/systemctl"
fresh() { rm -rf "$STUB/units" "$STUB/calls" "$STUB"/output*; }
newcalls() { tail -n +"$(( ${1:-0} + 1 ))" "$STUB/calls" 2>/dev/null; }
ncalls() { wc -l <"$STUB/calls" 2>/dev/null || echo 0; }
repo() { # path: a git repo with one commit
  mkdir -p "$1"; git -C "$1" init -q; git -C "$1" commit -q --allow-empty -m init
  (cd "$1" && pwd -P)
}
inst() { systemd-escape --path "$1"; }

printf '{"sandbox":{"enabled":true}}\n' >"$CLAUDE_DIR/settings.json"
printf '{"numStartups":5,"projects":{"/elsewhere":{"hasTrustDialogAccepted":true}}}\n' >"$HOME/.claude.json"
SURL=https://claude.ai/code/session_01G8282bitpmbotQCQAB569H
SES=$(repo "$HOME/repos/one-off"); mkdir -p "$SES/src"; SI=$(inst "$SES"); SUNIT="rrc-session@$SI.service"

mkdir -p "$TMP/plain"
out=$("$RRC" session "$TMP/plain" 2>&1); rc=$?
[ "$rc" != 0 ] && grep -q 'not in a git repository' <<<"$out" \
  && ok "session refuses a directory outside git" || no "session refuses a directory outside git" "rc=$rc $out"

printf '{}\n' >"$CLAUDE_DIR/settings.json"; fresh
out=$("$RRC" session "$SES" 2>&1); rc=$?
[ "$rc" = 3 ] && grep -q 'Ask the user' <<<"$out" && ! grep -qvE ' is-active ' "$STUB/calls" 2>/dev/null \
  && [ ! -f "$RRC_STATE/sessions/$SI.env" ] && [ ! -e "$HOME/.config/systemd/user" ] \
  && ! jq -e --arg p "$SES" '.projects[$p]' "$HOME/.claude.json" >/dev/null \
  && ok "session with the sandbox off stops before trust, settings or systemd, and says to ask" \
  || no "session with the sandbox off stops before trust, settings or systemd, and says to ask" "rc=$rc $out"
printf '{"sandbox":{"enabled":true}}\n' >"$CLAUDE_DIR/settings.json"

out=$("$RRC" session "$SES" --permission-mode sometimes 2>&1); rc=$?
[ "$rc" != 0 ] && grep -q 'must be one of' <<<"$out" \
  && ok "session refuses an unknown permission mode" || no "session refuses an unknown permission mode" "rc=$rc $out"

fresh; cp "$FIX/session-ready.out" "$STUB/output"
out=$(cd "$SES/src" && "$RRC" session --name "fix the login page" 2>"$TMP/err"); rc=$?
[ "$rc" = 0 ] && [ "$out" = "$SES"$'\n'"$SURL" ] && grep -q 'never comes back at boot' "$TMP/err" \
  && ok "session from a subdirectory starts one session in the repo root and prints its URL" \
  || no "session from a subdirectory starts one session in the repo root and prints its URL" "rc=$rc $out $(cat "$TMP/err")"
grep -qx 'RRC_ARGS="--permission-mode auto --name fix-the-login-page"' "$RRC_STATE/sessions/$SI.env" \
  && ok "session: auto mode by default, its title as one argument" || no "session: auto mode by default, its title as one argument" "$(cat "$RRC_STATE/sessions/$SI.env")"
jq -e --arg p "$SES" '.projects[$p].hasTrustDialogAccepted == true and .numStartups == 5
  and .projects["/elsewhere"].hasTrustDialogAccepted == true' "$HOME/.claude.json" >/dev/null \
  && ok "trust is set and the rest of ~/.claude.json kept" || no "trust is set and the rest of ~/.claude.json kept" "$(cat "$HOME/.claude.json")"
[ "$(ls "$RRC_STATE"/backups/claude.json.* 2>/dev/null | wc -l)" = 1 ] \
  && ok "~/.claude.json is backed up before the change" || no "~/.claude.json is backed up before the change" "$(ls "$RRC_STATE"/backups 2>&1)"
grep -qF -- "--user start $SUNIT" "$STUB/calls" && ! grep -qF -- "enable" "$STUB/calls" \
  && [ "$(readlink "$HOME/.config/systemd/user/rrc-session@.service")" = "$REPO/skill/systemd/rrc-session@.service" ] \
  && ok "session runs from the linked session template and is never enabled" \
  || no "session runs from the linked session template and is never enabled" "$(cat "$STUB/calls")"
[ "$(ls "$HOME/.config/systemd/user")" = "rrc-session@.service" ] \
  && ok "session links only its own unit: no server units, no update watcher" \
  || no "session links only its own unit: no server units, no update watcher" "$(ls "$HOME/.config/systemd/user")"

n=$(ncalls)
out=$("$RRC" session "$SES" 2>"$TMP/err"); rc=$?
[ "$rc" = 0 ] && [ "${out#*$'\n'}" = "$SURL" ] && ! newcalls "$n" | grep -qF -- "--user start" && grep -q 'already running' "$TMP/err" \
  && ok "session while one is running hands out its URL instead of starting another" \
  || no "session while one is running hands out its URL instead of starting another" "rc=$rc $out $(newcalls "$n")"

out=$("$RRC" list 2>&1)
grep -qx "$SES" <<<"$out" && grep -qx '  one session, running' <<<"$out" && grep -qx "  $SURL" <<<"$out" \
  && ok "list shows a running session and its URL" || no "list shows a running session and its URL" "$out"

DEMO=$(repo "$HOME/repos/demo"); DI=$(inst "$DEMO"); fresh
cp "$FIX/server-untrusted.out" "$STUB/output.1"; cp "$FIX/session-ready.out" "$STUB/output.2"
out=$("$RRC" session "$DEMO" 2>"$TMP/err"); rc=$?
[ "$rc" = 0 ] && [ "${out#*$'\n'}" = "$SURL" ] && grep -q 'not trusted' "$TMP/err" \
  && [ "$(grep -cF -- "--user start rrc-session@$DI.service" "$STUB/calls")" = 2 ] \
  && ok "\"Workspace not trusted\" in the output: trust set again, restarted once, URL printed" \
  || no "\"Workspace not trusted\" in the output: trust set again, restarted once, URL printed" "rc=$rc $out $(cat "$TMP/err")"

SLOW=$(repo "$HOME/repos/slow"); fresh; printf 'Error: nothing yet\n' >"$STUB/output"
out=$(RRC_WAIT=1 "$RRC" session "$SLOW" 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q 'no URL after 1s. Last error: Error: nothing yet' <<<"$out" \
  && ok "no URL in time: fails with the last error" || no "no URL in time: fails with the last error" "rc=$rc $out"

LATE=$(repo "$HOME/repos/late"); fresh; cp "$FIX/server-already-served.out" "$STUB/output"
out=$(STUB_FAIL=1 "$RRC" session "$LATE" 2>&1); rc=$?
[ "$rc" = 1 ] && grep -q 'try again in a minute' <<<"$out" \
  && ok "a session refused as \"already served\" says to try again in a minute" \
  || no "a session refused as \"already served\" says to try again in a minute" "rc=$rc $out"

# A server in the folder belongs to repo-remote-control-server. A stand-in
# rrcd answers for its URL, as the real one does from the server's output.
SRV=$(repo "$HOME/repos/served"); SVI=$(inst "$SRV"); fresh
mkdir -p "$STUB/units"; echo active >"$STUB/units/rrc-server@$SVI.service.state"
printf '#!/usr/bin/env bash\n[ "$1" = url ] && echo https://claude.ai/code?environment=env_01SERVER\n' >"$STUB/bin/rrcd"; chmod +x "$STUB/bin/rrcd"
out=$("$RRC" session "$SRV" 2>&1); rc=$?
[ "$rc" != 0 ] && grep -q "has a server" <<<"$out" && grep -qF 'env_01SERVER' <<<"$out" && ! grep -qF -- "rrc-session@" "$STUB/calls" \
  && ok "session in a repo with a server is refused and hands out the server's URL from rrcd" \
  || no "session in a repo with a server is refused and hands out the server's URL from rrcd" "rc=$rc $out"
rm -f "$STUB/bin/rrcd"
out=$("$RRC" session "$SRV" 2>&1); rc=$?
[ "$rc" != 0 ] && grep -q 'run rrcd list' <<<"$out" \
  && ok "with no rrcd on PATH, the refusal says where the URL is" || no "with no rrcd on PATH, the refusal says where the URL is" "rc=$rc $out"

fresh; mkdir -p "$STUB/units"; echo active >"$STUB/units/$SUNIT.state"
n=$(ncalls)
out=$("$RRC" teardown 2>&1); rc=$?
[ "$rc" = 0 ] && newcalls "$n" | grep -qF -- "--user stop $SUNIT" \
  && newcalls "$n" | grep -qF -- "--user reset-failed rrc-session@*" \
  && [ ! -e "$HOME/.config/systemd/user/rrc-session@.service" ] && [ -f "$RRC_STATE/sessions/$SI.env" ] \
  && ok "teardown stops every session, unlinks the unit, keeps state" \
  || no "teardown stops every session, unlinks the unit, keeps state" "rc=$rc $out"
out=$("$RRC" list 2>&1)
grep -q 'no session is running' <<<"$out" && ok "list with nothing running says how to start one" || no "list with nothing running says how to start one" "$out"

out=$("$RRC" frobnicate 2>&1); rc=$?
[ "$rc" = 2 ] && grep -q 'usage: rrc' <<<"$out" && ok "an unknown command prints usage" || no "an unknown command prints usage" "rc=$rc"

out=$(bash -c '. "$1"; type -t setTrust; echo "prog=$PROG"' _ "$RRC" 2>&1); rc=$?
[ "$rc" = 0 ] && grep -qx function <<<"$out" && grep -qx 'prog=rrc' <<<"$out" && ! grep -q usage <<<"$out" \
  && ok "sourced, rrc defines its functions and runs nothing" || no "sourced, rrc defines its functions and runs nothing" "rc=$rc $out"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" = 0 ]
