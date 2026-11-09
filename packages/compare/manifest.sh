# What this package installs. Sourced by install.sh and uninstall.sh.
#
# Two skills. skill/ is compare itself, with bin/side-by-side.py, which does
# the column layout so it is never done by hand. aliases/side-by-side is a thin
# skill pointing at it, because /<name> only resolves when a skill directory
# of that name exists and its frontmatter name matches. No settings entries.

PKG="compare"
OWNS="compare"

DIRS=(
  "skill:$CLAUDE_DIR/skills/compare"
  "aliases/side-by-side:$CLAUDE_DIR/skills/side-by-side"
)
FILES=()
STATE_DIRS=()

REGISTRATIONS=(
  "skills/compare, skills/side-by-side (no settings entry needed)"
)

# Both skills are well formed and typed-only, with names matching their
# directories, and the installed script lays a changed line out level with its
# twin and marks it.
verify_probe() {
  local n f d out
  for n in compare side-by-side; do
    f="$CLAUDE_DIR/skills/$n/SKILL.md"
    [ -f "$f" ] || return 1
    head -1 "$f" | grep -q '^---$' || return 1
    grep -qx "name: $n" "$f" && grep -q '^description:' "$f" || return 1
    grep -qx 'disable-model-invocation: true' "$f" || return 1
  done
  d=$(mktemp -d)
  printf 'same\nold\n' >"$d/a"; printf 'same\nnew\n' >"$d/b"
  out=$(python3 "$CLAUDE_DIR/skills/compare/bin/side-by-side.py" "$d/a" "$d/b" 2>/dev/null)
  rm -rf "$d"
  printf '%s\n' "$out" | grep -q '^old  *\* new$'
}

# Optional. Run by the release workflow at the tag, in this directory, with $1
# the version, before the tarball is packed. Each path in BUILD_OUTPUTS is then
# added to the tarball — for files that are generated, not committed. Non-zero
# stops the release.
# BUILD_OUTPUTS=(bin/compare)
# build() {
#   go build -ldflags "-X main.version=$1" -o bin/compare ./cmd/compare
# }

# Optional, both. Changes outside $HOME around a real install. pre_install
# runs before any file is placed — stop services running from the package's
# directory, which a reinstall deletes and copies again; non-zero stops the
# install with nothing placed. post_install runs after the files and settings,
# before verify_probe; non-zero fails the install. Each gets $1: "install" the
# first time, "reinstall" when the package's files were already there. Neither
# runs on --dry-run or when KIT_SKIP_MACHINE_HOOKS=1 (the tests set it). Both
# must be safe to run again.
# pre_install() {
#   [ "$1" = reinstall ] && systemctl --user stop "$PKG.service" 2>/dev/null
#   return 0
# }
# post_install() {
#   loginctl enable-linger "$USER" && systemctl --user restart "$PKG.service"
# }

# Optional. Runs when install.sh stops after pre_install has run, with $1 the
# mode and $2 the reason, so services pre_install stopped are not left down.
# Skipped when KIT_SKIP_MACHINE_HOOKS=1.
# install_failed() {
#   systemctl --user start "$PKG.service" 2>/dev/null || true
# }

# Optional, both. Run by update.sh with $1 the installed version and $2 the
# new one, from the new release's manifest.sh. pre_update runs before the new
# files are unpacked; non-zero stops the update with nothing changed.
# post_update runs after install.sh succeeds; use it to migrate from an older
# version. Skipped with --dry-run and when KIT_SKIP_MACHINE_HOOKS=1.
# pre_update() {
#   systemctl --user stop "$PKG.service" 2>/dev/null || true
# }
# post_update() {
#   case "$1" in 1.*) mv "$CLAUDE_DIR/$PKG/old.conf" "$CLAUDE_DIR/$PKG/new.conf" 2>/dev/null ;; esac
#   return 0
# }

# Optional. Run by lib/update-check.sh check, in the background, once for each
# newly found release, with $1 the installed version, $2 the new one and $3 the
# release URL. It cannot show anything in a session; output goes to
# ~/.local/state/compare/update_available.log. Skipped when
# KIT_SKIP_MACHINE_HOOKS=1.
# update_available() {
#   notify-send "compare v$2 is available" "$3" 2>/dev/null || true
# }

# Optional. Run in the background at session start when Claude Code's version
# has changed since last time, with $1 the old version and $2 the new one.
# Output goes to ~/.local/state/compare/claude_updated.log. Skipped when
# KIT_SKIP_MACHINE_HOOKS=1.
# claude_updated() {
#   systemctl --user restart "$PKG.service" 2>/dev/null || true
# }

# install.sh registers lib/update-check.sh on SessionStart, to show a waiting
# release and run the daily check. Set this to 0 to leave that out.
# UPDATE_NOTICE=0

# Optional. Runs in uninstall.sh before anything is removed, while the files
# are still installed: stop services started from the package's directory.
# Non-zero stops the uninstall with nothing removed. Skipped when
# KIT_SKIP_MACHINE_HOOKS=1 (the tests set it).
# pre_uninstall() {
#   systemctl --user stop "$PKG.service" 2>/dev/null || true
# }

# Optional. Runs in uninstall.sh after everything is removed, to undo a change
# outside $HOME that needs none of the package's files. Skipped when
# KIT_SKIP_MACHINE_HOOKS=1. Non-zero is reported; nothing is put back.
# post_uninstall() {
#   loginctl disable-linger "$USER"
# }
