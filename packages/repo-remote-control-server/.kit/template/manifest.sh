# What this package installs. Sourced by install.sh and uninstall.sh.
#
# This is the skill variant: a directory under ~/.claude/skills. Skills need no
# settings.json entry — Claude Code reads anything under skills/ at startup.

PKG="repo-remote-control-server"
OWNS="repo-remote-control-server"

# A skill installs as a whole directory. install.sh copies or symlinks it.
DIRS=(
  "skill:$CLAUDE_DIR/skills/repo-remote-control-server"
)
FILES=()
# Other directories uninstall.sh removes. Not for state: uninstall.sh already
# removes the skill's state/ (unless --keep-state) and ~/.local/share/repo-remote-control-server.
# See reference/layout.md.
STATE_DIRS=()

# No settings entries for a skill. Leaving this undefined is what tells
# install.sh to skip settings.json entirely.
# settings_merge() { :; }

REGISTRATIONS=(
  "skills/repo-remote-control-server (no settings entry needed)"
)

# EDIT, or delete. Confirm the installed skill is well formed — a SKILL.md with
# frontmatter Claude Code can actually read.
verify_probe() {
  local f="$CLAUDE_DIR/skills/$PKG/SKILL.md"
  [ -f "$f" ] || return 1
  head -1 "$f" | grep -q '^---$' || return 1
  grep -q '^name:' "$f" && grep -q '^description:' "$f"
}
