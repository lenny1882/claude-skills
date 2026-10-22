# What this package installs. Sourced by install.sh and uninstall.sh.
#
# The skill directory holds everything: SKILL.md, the rrc command, the unit
# template, and state/ (per-repo settings, server output, ~/.claude.json
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

# No settings entries for a skill. Leaving this undefined is what tells
# install.sh to skip settings.json entirely.
# settings_merge() { :; }

REGISTRATIONS=(
  "skills/repo-remote-control (no settings entry needed)"
)

# The skill is readable, rrc on PATH runs, and the unit template it links is
# there with the lines rrc depends on: where it reads per-repo settings and
# where it writes the output rrc reads the URL from.
verify_probe() {
  local d="$CLAUDE_DIR/skills/$PKG" u
  [ -f "$d/SKILL.md" ] || return 1
  head -1 "$d/SKILL.md" | grep -q '^---$' || return 1
  grep -q '^name:' "$d/SKILL.md" && grep -q '^description:' "$d/SKILL.md" || return 1
  "$HOME/.local/bin/rrc" --help 2>/dev/null | grep -q '^usage: rrc' || return 1
  u="$d/systemd/rrc-server@.service"
  grep -q '^EnvironmentFile=%h/.claude/skills/repo-remote-control/state/repos/%i.env$' "$u" \
    && grep -q '^StandardOutput=truncate:%h/.claude/skills/repo-remote-control/state/logs/%i.log$' "$u"
}
