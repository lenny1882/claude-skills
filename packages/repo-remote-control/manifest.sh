# What this package installs. Sourced by install.sh and uninstall.sh.
#
# The skill directory holds everything: SKILL.md, the rrc command, the unit
# template, the two hooks (registered in settings.json by their path inside
# the skill), and state/ (per-repo settings, server output, ~/.claude.json
# backups), which the installer keeps across reinstalls. rrc is also put on
# PATH, for use over SSH. The unit template is not installed here: rrc start
# links it into ~/.config/systemd/user itself, so systemd always reads the
# skill's current copy.

PKG="repo-remote-control"
OWNS="repo-remote-control"

# A skill installs as a whole directory. install.sh copies or symlinks it.
DIRS=(
  "skill:$CLAUDE_DIR/skills/repo-remote-control"
)
FILES=(
  "skill/bin/rrc:$HOME/.local/bin/rrc"
)
# Other directories uninstall.sh removes. Not for state: uninstall.sh already
# removes the skill's state/ (unless --keep-state) and ~/.local/share/repo-remote-control.
# See reference/layout.md.
STATE_DIRS=()

# The two hooks for Remote Control server sessions. Both act only inside
# .claude/worktrees/bridge-* and do nothing anywhere else, so they are
# registered for every session. SessionStart has no matcher: it also runs on
# resume, when it only re-states the branch instructions to a detached session.
settings_merge() {
  jq --arg ss "~/.claude/skills/$PKG/hooks/repo-remote-control-sessionstart.sh" \
     --arg cg "~/.claude/skills/$PKG/hooks/repo-remote-control-commit-guard.sh" '
    .hooks //= {}
    | .hooks.SessionStart = ((.hooks.SessionStart // []) + [
        { hooks: [{ type: "command", command: $ss }] }
      ])
    | .hooks.PreToolUse = ((.hooks.PreToolUse // []) + [
        { matcher: "Bash", hooks: [{ type: "command", command: $cg }] }
      ])
  '
}

REGISTRATIONS=(
  "skills/repo-remote-control"
  "SessionStart: hooks/repo-remote-control-sessionstart.sh"
  "PreToolUse (matcher: Bash): hooks/repo-remote-control-commit-guard.sh"
)

# Before uninstalling: every server, session and the update watcher stopped
# and disabled, and the units unlinked, so nothing keeps running a deleted
# skill. The kit's uninstall.sh does not call a hook like this yet (asked for
# on 22 Oct); until it does, run rrc teardown first.
pre_uninstall() {
  [ -x "$HOME/.local/bin/rrc" ] && "$HOME/.local/bin/rrc" teardown
  return 0
}

# The skill is readable, rrc on PATH runs, the unit template it links is
# there with the lines rrc depends on (where it reads per-repo settings and
# where it writes the output rrc reads the URL from), and the commit guard
# blocks a commit on a detached HEAD in a bridge-* worktree.
verify_probe() {
  local d="$CLAUDE_DIR/skills/$PKG" u t rc
  t=$(mktemp -d)
  git -C "$t" init -q && git -C "$t" -c user.name=p -c user.email=p@p commit -q --allow-empty -m p \
    && git -C "$t" worktree add -q --detach "$t/.claude/worktrees/bridge-probe" 2>/dev/null
  jq -n --arg c "$t/.claude/worktrees/bridge-probe" '{cwd: $c, tool_input: {command: "git commit -m probe"}}' \
    | "$d/hooks/repo-remote-control-commit-guard.sh" >/dev/null 2>&1
  rc=$?
  rm -rf "$t"
  [ "$rc" = 2 ] || return 1
  [ -f "$d/SKILL.md" ] || return 1
  head -1 "$d/SKILL.md" | grep -q '^---$' || return 1
  grep -q '^name:' "$d/SKILL.md" && grep -q '^description:' "$d/SKILL.md" || return 1
  "$HOME/.local/bin/rrc" --help 2>/dev/null | grep -q '^usage: rrc' || return 1
  u="$d/systemd/rrc-server@.service"
  grep -q '^EnvironmentFile=%h/.claude/skills/repo-remote-control/state/repos/%i.env$' "$u" \
    && grep -q '^StandardOutput=truncate:%h/.claude/skills/repo-remote-control/state/logs/%i.log$' "$u"
}
