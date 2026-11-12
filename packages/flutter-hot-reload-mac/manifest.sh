# What this package installs. Sourced by install.sh and uninstall.sh.
#
# This is the skill variant: a directory under ~/.claude/skills. Skills need no
# settings.json entry — Claude Code reads anything under skills/ at startup.

PKG="flutter-hot-reload-mac"
OWNS="flutter-hot-reload-mac"

# A skill installs as a whole directory. install.sh copies or symlinks it.
DIRS=(
  "skill:$CLAUDE_DIR/skills/flutter-hot-reload-mac"
)
FILES=()
# Other directories uninstall.sh removes. Not for state: uninstall.sh already
# removes the skill's state/ (unless --keep-state) and ~/.local/share/flutter-hot-reload-mac.
# See reference/layout.md.
STATE_DIRS=()

# No settings entries for a skill. Leaving this undefined is what tells
# install.sh to skip settings.json entirely.
# settings_merge() { :; }

REGISTRATIONS=(
  "skills/flutter-hot-reload-mac (no settings entry needed)"
)

# flutter-hot-reload-mac needs maestro-drive: bin/lib.sh sources that
# package's bin/lib.sh from its skill directory and checks its library version.
# verify_probe fails the install when it cannot load it, with lib.sh's own
# reason.
#
# It also confirms the installed skill is well formed — a SKILL.md with
# frontmatter Claude Code can read — and that every script SKILL.md tells
# Claude to run is there and parses. They are run as `bash <script>`, so no
# execute bit is needed. Nothing here can reach the Mac; the conf it loads
# with is a throwaway one naming no real host.
verify_probe() {
  local d="$CLAUDE_DIR/skills/$PKG" f s t out
  f="$d/SKILL.md"
  [ -f "$f" ] || return 1
  head -1 "$f" | grep -q '^---$' || return 1
  grep -q '^name:' "$f" && grep -q '^description:' "$f" || return 1
  for s in lib start watch reload status stop logs; do
    bash -n "$d/bin/$s.sh" 2>/dev/null || return 1
  done
  [ -f "$d/remote/frun.py" ] || return 1
  t=$(mktemp -d)
  printf ': "${MAC_HOST:=probe}"\n: "${MAC_FQDN:=probe.invalid}"\n: "${APP_ID:=probe.app}"\n' > "$t/probe.conf"
  out=$(cd "$t" && MAESTRO_DRIVE_CONF="$t/probe.conf" TMPDIR="$t" CLAUDE_DIR="$CLAUDE_DIR" \
        bash -c '. "$1" && echo loaded' _ "$d/bin/lib.sh" 2>&1)
  rm -rf "$t"
  if [ "$(tail -1 <<<"$out")" != loaded ]; then
    printf '  warn  %s\n' "$(grep -m1 'flutter-hot-reload-mac:' <<<"$out" || head -1 <<<"$out")"
    return 1
  fi
}
