# What this package installs. Sourced by install.sh and uninstall.sh.
#
# This is the skill variant: a directory under ~/.claude/skills. Skills need no
# settings.json entry — Claude Code reads anything under skills/ at startup.

PKG="phase-worktrees"
OWNS="phase-worktrees"

# A skill installs as a whole directory. install.sh copies or symlinks it.
DIRS=(
  "skill:$CLAUDE_DIR/skills/phase-worktrees"
)
FILES=()
# Other directories uninstall.sh removes. Not for state: uninstall.sh already
# removes the skill's state/ (unless --keep-state) and ~/.local/share/phase-worktrees.
# See reference/layout.md.
STATE_DIRS=()

# No settings entries for a skill. Leaving this undefined is what tells
# install.sh to skip settings.json entirely.
# settings_merge() { :; }

REGISTRATIONS=(
  "skills/phase-worktrees (no settings entry needed)"
)

# Confirm the installed skill is well formed — a SKILL.md with frontmatter
# Claude Code can actually read — and that the script it wraps runs from where
# SKILL.md tells Claude to find it. A copy that lost the executable bit would
# otherwise pass.
verify_probe() {
  local f="$CLAUDE_DIR/skills/$PKG/SKILL.md"
  [ -f "$f" ] || return 1
  head -1 "$f" | grep -q '^---$' || return 1
  grep -q '^name:' "$f" && grep -q '^description:' "$f" || return 1
  "$CLAUDE_DIR/skills/$PKG/bin/phase-worktrees.sh" --help 2>/dev/null \
    | grep -q "one git worktree per GSD phase"
}
