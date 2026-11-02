# What this package installs. Sourced by install.sh and uninstall.sh.
#
# The skill directory holds SKILL.md, the rrc command, lib/rrc-lib.sh (the
# code rrc shares with repo-remote-control-server's rrcd, which sources it
# from here) and state/ (each session's PID file and output, ~/.claude.json
# backups), which the installer keeps across reinstalls. rrc is also put on
# PATH: Claude runs it by that name. Sessions run as detached processes, not
# systemd units: see the header of skill/bin/rrc.

PKG="repo-remote-control-session"
OWNS="repo-remote-control-session"

# A skill installs as a whole directory. install.sh copies or symlinks it.
DIRS=(
  "skill:$CLAUDE_DIR/skills/repo-remote-control-session"
)
FILES=(
  "skill/bin/rrc:$HOME/.local/bin/rrc"
)
# Other directories uninstall.sh removes. Not for state: uninstall.sh already
# removes the skill's state/ (unless --keep-state) and ~/.local/share/repo-remote-control-session.
# See reference/layout.md.
STATE_DIRS=()

# rrc has to run outside Claude's sandbox, which blocks ~/.claude.json and
# ends every process a call started when the call ends. An entry with no wildcard
# matches only the bare command with no arguments, so it is "rrc *". Every
# rrc command only touches one-off sessions, so all of them are excluded.
EXCLUDED=("rrc *")

# Added to whatever the other packages and the user have in
# sandbox.excludedCommands, once, leaving the rest of sandbox alone. Run
# twice, it changes nothing.
settings_merge() {
  jq --argjson ours "$(printf '%s\n' "${EXCLUDED[@]}" | jq -R . | jq -s .)" '
    .sandbox //= {}
    | .sandbox.excludedCommands = (((.sandbox.excludedCommands // []) - $ours) + $ours)
  '
}

REGISTRATIONS=(
  "skills/repo-remote-control-session"
  "sandbox.excludedCommands: ${EXCLUDED[*]}"
)

# Sessions stopped, so nothing keeps running a deleted skill, and the sandbox exclusion taken out: uninstall.sh's own settings
# step only knows about hooks, and a stale "rrc *" would let any later
# program called rrc run unsandboxed. Skipped with --keep-settings.
pre_uninstall() {
  [ -x "$HOME/.local/bin/rrc" ] && "$HOME/.local/bin/rrc" teardown
  strip_excluded
}

strip_excluded() {
  local s="$CLAUDE_DIR/settings.json" tmp
  [ "${KEEP_SETTINGS:-0}" = 1 ] && return 0
  [ -f "$s" ] && jq empty "$s" 2>/dev/null || return 0
  jq -e --argjson ours "$(printf '%s\n' "${EXCLUDED[@]}" | jq -R . | jq -s .)" \
    '(.sandbox.excludedCommands // []) | any(. as $e | $ours | index($e))' "$s" >/dev/null || return 0
  cp "$s" "$s.bak-$PKG"
  tmp=$(mktemp)
  jq --argjson ours "$(printf '%s\n' "${EXCLUDED[@]}" | jq -R . | jq -s .)" '
    .sandbox.excludedCommands -= $ours
    | if .sandbox.excludedCommands == [] then del(.sandbox.excludedCommands) else . end
  ' "$s" >"$tmp" && mv "$tmp" "$s"
  printf '  ok    removed %s from sandbox.excludedCommands\n' "${EXCLUDED[*]}"
}

# The skill is readable, rrc on PATH runs, setsid is there for rrc session
# to detach a session with, and the exclusion is in place.
verify_probe() {
  local d="$CLAUDE_DIR/skills/$PKG"
  [ -f "$d/SKILL.md" ] || return 1
  head -1 "$d/SKILL.md" | grep -q '^---$' || return 1
  grep -q '^name:' "$d/SKILL.md" && grep -q '^description:' "$d/SKILL.md" || return 1
  "$HOME/.local/bin/rrc" --help 2>/dev/null | grep -q '^usage: rrc' || return 1
  command -v setsid >/dev/null || return 1
  jq -e '.sandbox.excludedCommands | index("rrc *")' "$CLAUDE_DIR/settings.json" >/dev/null
}
