# Visibility check tests (C2.3). Sourced by run-tests.sh. A fake curl on PATH answers
# with FAKE_CURL_CODE and keeps the URL and arguments it was given.

echo "visibility check (C2.3)"
mkdir -p "$TMP/curlbin"
cat > "$TMP/curlbin/curl" <<'FAKE'
#!/bin/sh
printf '%s\n' "$@" > "$FAKE_CLAUDE_DIR/curl-args"; env > "$FAKE_CLAUDE_DIR/curl-env"
printf '%s' "${FAKE_CURL_CODE:-404}"
FAKE
chmod 755 "$TMP/curlbin/curl"
R=$TMP/pv1; rm -rf "$R"; git init -q "$R"
pv() { (cd "$R" && PATH="$TMP/curlbin:$PATH" GITHUB_TOKEN=secret-token FAKE_CURL_CODE=$1 "$GS" private) >/dev/null 2>&1; }
for u in git@github.com:own/rep.git https://github.com/own/rep ssh://git@github.com/own/rep.git; do
  git -C "$R" remote remove origin 2>/dev/null; git -C "$R" remote add origin "$u"
  pv 404; rc=$?
  [ "$rc" = 0 ] && /usr/bin/grep -qx 'https://api.github.com/repos/own/rep' "$TMP/curl-args" && ok "404 passes, asking for own/rep from $u" || no "404 passes for $u" "exit $rc: $(tail -1 "$TMP/curl-args")"
done
/usr/bin/grep -q 'secret-token' "$TMP/curl-env" && no "the request carries no token" "GITHUB_TOKEN reached curl" || ok "the request carries no token"
pv 200; rc=$?; [ "$rc" = 1 ] && ok "200 (public) fails with exit 1" || no "200 fails" "exit $rc"
pv 500; rc=$?; [ "$rc" = 2 ] && ok "any other answer exits 2" || no "other answers exit 2" "exit $rc"
git -C "$R" remote set-url origin https://bitbucket.org/own/rep.git
pv 404; rc=$?; [ "$rc" = 2 ] && ok "a remote that is not GitHub exits 2" || no "non-GitHub exits 2" "exit $rc"
