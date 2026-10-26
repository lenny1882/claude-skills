# What this package installs. Sourced by install.sh and uninstall.sh.
#
# This is the skill variant: a directory under ~/.claude/skills. Skills need no
# settings.json entry — Claude Code reads anything under skills/ at startup.

PKG="owl"
OWNS="owl"

# A skill installs as a whole directory. install.sh copies or symlinks it.
DIRS=(
  "skill:$CLAUDE_DIR/skills/owl"
)
FILES=()
# Other directories uninstall.sh removes. Not for state: uninstall.sh already
# removes the skill's state/ (unless --keep-state) and ~/.local/share/owl.
# See reference/layout.md.
STATE_DIRS=()

# No settings entries for a skill. Leaving this undefined is what tells
# install.sh to skip settings.json entirely.
# settings_merge() { :; }

REGISTRATIONS=(
  "skills/owl (no settings entry needed)"
)

# Confirm the installed skill is well formed — a SKILL.md with frontmatter
# Claude Code can actually read — and that it is still typed-only. Its name
# must match the directory, or /<name> stops resolving, and without
# disable-model-invocation Claude would load it uninvited mid-answer.
verify_probe() {
  local f="$CLAUDE_DIR/skills/$PKG/SKILL.md"
  [ -f "$f" ] || return 1
  head -1 "$f" | grep -q '^---$' || return 1
  grep -qx "name: $PKG" "$f" && grep -q '^description:' "$f" || return 1
  grep -qx 'disable-model-invocation: true' "$f"
}
