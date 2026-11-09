# What this package installs. Sourced by install.sh and uninstall.sh.
#
# Three skills and one hook. skill/ is mate itself; aliases/bruv and
# aliases/dude are thin skills that point at it, because /<name> only resolves
# when a skill directory of that name exists and its frontmatter name matches.
# hooks/mate-bare-word.sh is the UserPromptSubmit hook that turns a message of
# only "mate", "bruv" or "dude" into the skill: see its header for why it
# injects the skill text rather than calling the Skill tool.

PKG="mate"
# Matched as a whole word against hook commands. "mate" alone would also be
# safe, but the script's own name is what the entry actually contains.
OWNS="mate-bare-word"

DIRS=(
  "skill:$CLAUDE_DIR/skills/mate"
  "aliases/bruv:$CLAUDE_DIR/skills/bruv"
  "aliases/dude:$CLAUDE_DIR/skills/dude"
)
FILES=(
  "hooks/mate-bare-word.sh:$CLAUDE_DIR/hooks/mate-bare-word.sh"
)
STATE_DIRS=()

# No matcher: UserPromptSubmit has none, and the script itself decides whether
# the message is a bare word.
settings_merge() {
  jq --arg cmd "~/.claude/hooks/mate-bare-word.sh" '
    .hooks //= {}
    | .hooks.UserPromptSubmit = ((.hooks.UserPromptSubmit // []) + [
        { hooks: [{ type: "command", command: $cmd }] }
      ])
  '
}

REGISTRATIONS=(
  "skills/mate, skills/bruv, skills/dude"
  "UserPromptSubmit: hooks/mate-bare-word.sh"
)

# Each skill is well formed and typed-only, its name matching its directory,
# and the hook turns a bare "bruv" into the mate skill's text while leaving an
# ordinary message alone.
verify_probe() {
  local n f out
  for n in mate bruv dude; do
    f="$CLAUDE_DIR/skills/$n/SKILL.md"
    [ -f "$f" ] || return 1
    head -1 "$f" | grep -q '^---$' || return 1
    grep -qx "name: $n" "$f" && grep -q '^description:' "$f" || return 1
    grep -qx 'disable-model-invocation: true' "$f" || return 1
  done
  out=$(printf '{"prompt":"bruv"}' | CLAUDE_DIR="$CLAUDE_DIR" "$CLAUDE_DIR/hooks/mate-bare-word.sh") || return 1
  printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | contains("Name the fault")' >/dev/null || return 1
  out=$(printf '{"prompt":"mate, why is that?"}' | CLAUDE_DIR="$CLAUDE_DIR" "$CLAUDE_DIR/hooks/mate-bare-word.sh") || return 1
  [ -z "$out" ]
}

# Optional. Run by the release workflow at the tag, in this directory, with $1
# the version, before the tarball is packed. Each path in BUILD_OUTPUTS is then
# added to the tarball — for files that are generated, not committed. Non-zero
# stops the release.
# BUILD_OUTPUTS=(bin/mate)
# build() {
#   go build -ldflags "-X main.version=$1" -o bin/mate ./cmd/mate
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
# ~/.local/state/mate/update_available.log. Skipped when
# KIT_SKIP_MACHINE_HOOKS=1.
# update_available() {
#   notify-send "mate v$2 is available" "$3" 2>/dev/null || true
# }

# Optional. Run in the background at session start when Claude Code's version
# has changed since last time, with $1 the old version and $2 the new one.
# Output goes to ~/.local/state/mate/claude_updated.log. Skipped when
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
