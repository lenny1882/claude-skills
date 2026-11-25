# Uninstall keeps the config (C8.5, E8). Sourced by run-tests.sh; the installer tests
# have already shown install.sh and uninstall.sh work into $CLAUDE_DIR.

echo "uninstall keeps the config (C8.5)"
st="$CLAUDE_DIR/skills/git-scrub/state"
(cd "$REPO" && ./install.sh --yes) >/dev/null 2>&1
mkdir -p "$st/abc123"; printf 'zarnok\n' > "$st/abc123/values.txt"
(cd "$REPO" && KIT_SKIP_MACHINE_HOOKS=0 ./uninstall.sh --yes) >/dev/null 2>"$TMP/un.err" </dev/null; rc=$?
[ "$rc" != 0 ] && [ -f "$st/abc123/values.txt" ] && [ -f "$CLAUDE_DIR/skills/git-scrub/bin/git-scrub" ] \
  && ok "uninstall with no --keep-state and no typed confirmation refuses and removes nothing" || no "uninstall refuses" "exit $rc: $(cat "$TMP/un.err")"
(cd "$REPO" && KIT_SKIP_MACHINE_HOOKS=0 ./uninstall.sh --yes --keep-state) >/dev/null 2>&1; rc=$?
[ "$rc" = 0 ] && [ -f "$st/abc123/values.txt" ] && [ ! -f "$CLAUDE_DIR/skills/git-scrub/bin/git-scrub" ] \
  && ok "uninstall --keep-state removes the package and keeps the config" || no "uninstall --keep-state" "exit $rc"
(cd "$REPO" && ./install.sh --yes) >/dev/null 2>&1
[ -f "$st/abc123/values.txt" ] && ok "E8: reinstalling finds the config where it was" || no "reinstall keeps the config" "gone"
(cd "$REPO" && KIT_SKIP_MACHINE_HOOKS=0 ./uninstall.sh --yes --keep-state) >/dev/null 2>&1
rm -rf "$st"
