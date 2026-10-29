# What this package installs. Sourced by install.sh and uninstall.sh.
#
# The skill directory holds everything: SKILL.md, the rrcd command, the unit
# templates, the two hooks (registered in settings.json by their path inside
# the skill), and state/ (per-repo settings, server output, ~/.claude.json
# backups), which the installer keeps across reinstalls. rrcd is also put on
# PATH, for use over SSH. The unit templates are not installed here: rrcd
# start links them into ~/.config/systemd/user itself, so systemd always
# reads the skill's current copy.
#
# rrcd needs repo-remote-control-session's rrc on PATH: it sources it for the
# parts both share. verify_probe fails the install without it.

PKG="repo-remote-control-server"
OWNS="repo-remote-control-server"

# A skill installs as a whole directory. install.sh copies or symlinks it.
DIRS=(
  "skill:$CLAUDE_DIR/skills/repo-remote-control-server"
)
FILES=(
  "skill/bin/rrcd:$HOME/.local/bin/rrcd"
)
# Other directories uninstall.sh removes. Not for state: uninstall.sh already
# removes the skill's state/ (unless --keep-state) and ~/.local/share/repo-remote-control-server.
# See reference/layout.md.
STATE_DIRS=()

# rrcd has to run outside Claude's sandbox, which blocks the user bus,
# ~/.config/systemd/user and ~/.claude.json. Only the commands Claude is
# meant to run are excluded. remove (it can delete worktrees with work),
# restart-all (it ends every open session) and teardown stay sandboxed, so
# they fail from Claude and the user runs them. "rrcd restart *" does not
# cover restart-all: the space before * makes it a whole word.
EXCLUDED=("rrcd start *" "rrcd clone *" "rrcd list" "rrcd url *" "rrcd restart *" "rrcd stop *")

# The two hooks for Remote Control server sessions. Both act only inside
# .claude/worktrees/bridge-* and do nothing anywhere else, so they are
# registered for every session. SessionStart has no matcher: it also runs on
# resume, when it only re-states the branch instructions to a detached session.
# The exclusions are added to whatever is in sandbox.excludedCommands, once,
# leaving the rest of sandbox alone.
settings_merge() {
  jq --arg ss "~/.claude/skills/$PKG/hooks/$PKG-sessionstart.sh" \
     --arg cg "~/.claude/skills/$PKG/hooks/$PKG-commit-guard.sh" \
     --argjson ours "$(printf '%s\n' "${EXCLUDED[@]}" | jq -R . | jq -s .)" '
    .hooks //= {}
    | .hooks.SessionStart = ((.hooks.SessionStart // []) + [
        { hooks: [{ type: "command", command: $ss }] }
      ])
    | .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [
        { matcher: "Bash", hooks: [{ type: "command", command: $cg }] }
      ])
    | .sandbox //= {}
    | .sandbox.excludedCommands = (((.sandbox.excludedCommands // []) - $ours) + $ours)
  '
}

REGISTRATIONS=(
  "skills/repo-remote-control-server"
  "SessionStart: hooks/repo-remote-control-server-sessionstart.sh"
  "PreToolUse (matcher: Bash): hooks/repo-remote-control-server-commit-guard.sh"
  "sandbox.excludedCommands: ${EXCLUDED[*]}"
)

# Before uninstalling: every server and the update watcher stopped and
# disabled, and the units unlinked, so nothing keeps running a deleted skill.
# uninstall.sh runs this before removing anything, and stops with nothing
# removed if it fails. The exclusions are taken out here too: uninstall.sh's
# own settings step only knows about hooks. Skipped with --keep-settings.
pre_uninstall() {
  [ -x "$HOME/.local/bin/rrcd" ] && "$HOME/.local/bin/rrcd" teardown
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

# The skill is readable, rrc from repo-remote-control-session is on PATH and
# rrcd runs with it, the unit template rrcd links is there with the lines it
# depends on, the exclusions are in place, and the commit guard blocks a
# commit on a detached HEAD in a bridge-* worktree.
verify_probe() {
  local d="$CLAUDE_DIR/skills/$PKG" u t rc
  if ! command -v rrc >/dev/null 2>&1; then
    printf '  warn  rrc is not on PATH: install repo-remote-control-session first\n'
    return 1
  fi
  t=$(mktemp -d)
  git -C "$t" init -q && git -C "$t" -c user.name=p -c user.email=p@p commit -q --allow-empty -m p \
    && git -C "$t" worktree add -q --detach "$t/.claude/worktrees/bridge-probe" 2>/dev/null
  jq -n --arg c "$t/.claude/worktrees/bridge-probe" '{cwd: $c, tool_input: {command: "git commit -m probe"}}' \
    | "$d/hooks/$PKG-commit-guard.sh" >/dev/null 2>&1
  rc=$?
  rm -rf "$t"
  [ "$rc" = 2 ] || return 1
  [ -f "$d/SKILL.md" ] || return 1
  head -1 "$d/SKILL.md" | grep -q '^---$' || return 1
  grep -q '^name:' "$d/SKILL.md" && grep -q '^description:' "$d/SKILL.md" || return 1
  "$HOME/.local/bin/rrcd" --help 2>/dev/null | grep -q '^usage: rrcd' || return 1
  u="$d/systemd/rrc-server@.service"
  grep -q '^EnvironmentFile=%h/.claude/skills/repo-remote-control-server/state/repos/%i.env$' "$u" \
    && grep -q '^StandardOutput=truncate:%h/.claude/skills/repo-remote-control-server/state/logs/%i.log$' "$u" \
    || return 1
  jq -e '.sandbox.excludedCommands | index("rrcd start *")' "$CLAUDE_DIR/settings.json" >/dev/null
}
