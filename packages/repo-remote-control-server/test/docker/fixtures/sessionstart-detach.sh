#!/usr/bin/env bash
# stand-in for the package's SessionStart hook, for confirm.sh sessionstart-detach:
# logs what the hook is given, and in a server session's worktree
# (.claude/worktrees/bridge-*) detaches HEAD and deletes the generated
# worktree-bridge-* branch. The real hook does not exist yet; this one only has
# to show whether SessionStart fires there, with which cwd, and in time.

log=$HOME/rrc-hook.log
input=$(cat)
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)
[[ -n $cwd ]] || cwd=$PWD

{
	printf '=== %s\n' "$(date '+%F %T.%N')"
	printf 'PWD=%s\n' "$PWD"
	printf 'input=%s\n' "$input"
} >>"$log"

case $cwd in
	*/.claude/worktrees/bridge-*) ;;
	*) echo "not a bridge worktree, nothing done" >>"$log"; exit 0 ;;
esac

branch=$(git -C "$cwd" symbolic-ref --short -q HEAD)
echo "branch before: ${branch:-<detached>}" >>"$log"
git -C "$cwd" switch --detach -q >>"$log" 2>&1
if [[ $branch == worktree-bridge-* ]]; then
	git -C "$cwd" branch -D "$branch" >>"$log" 2>&1
fi
echo "branch after: $(git -C "$cwd" symbolic-ref --short -q HEAD || echo '<detached>')" >>"$log"
exit 0
