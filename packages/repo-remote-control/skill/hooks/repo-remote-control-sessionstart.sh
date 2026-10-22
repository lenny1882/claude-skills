#!/usr/bin/env bash
# SessionStart: takes a Remote Control server session off the branch Claude
# generated for it, so the session names its own.
#
# Why: a server session (claude remote-control --spawn worktree) starts in
# <repo>/.claude/worktrees/bridge-<id> on a new branch, worktree-bridge-<id>.
# Branches are meant to be named by convention (<type>/<KEY>-<description>,
# see DESIGN.md, "Branches"), and nothing in the app picks a branch when a
# session opens. So the session starts detached, with no branch, and is told
# to create its branch before it changes anything.
#
# Why not a WorktreeCreate hook: that replaces worktree creation for every
# caller on the machine, GSD's executor subagents included. This acts only on
# paths under .claude/worktrees/bridge-* and leaves everything else alone.
#
# Confirmed in Docker (sessionstart-detach, 22 Oct): it fires with the
# worktree as cwd, before the session's first command, and the server still
# removes an unused worktree at session end after the detach.
#
# A generated branch is only removed while it is empty: no commits of its own
# and no changes. A resumed session that somehow worked on it keeps it.

set -uo pipefail

input=$(cat)
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)
cwd=${cwd:-$PWD}

case $cwd in */.claude/worktrees/bridge-*) ;; *) exit 0 ;; esac
top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null) || exit 0
case $top in */.claude/worktrees/bridge-*) ;; *) exit 0 ;; esac

branch=$(git -C "$top" symbolic-ref --short -q HEAD 2>/dev/null || true)
if [[ $branch == worktree-bridge-* ]] \
	&& [ -z "$(git -C "$top" status --porcelain 2>/dev/null)" ] \
	&& [ "$(git -C "$top" rev-list HEAD --not --remotes 2>/dev/null | wc -l)" -eq 0 ]; then
	git -C "$top" switch --detach -q 2>/dev/null \
		&& git -C "$top" branch -D -q "$branch" 2>/dev/null
	branch=$(git -C "$top" symbolic-ref --short -q HEAD 2>/dev/null || true)
fi

# only a detached session needs telling; one on a named branch is under way
[ -z "$branch" ] || exit 0

context="This Remote Control session runs in its own git worktree, $top, on a detached HEAD at $(git -C "$top" log -1 --format='%h %s' 2>/dev/null). Commits on a detached HEAD are blocked.

Before changing any file, create this task's branch:
  git switch -c <type>/<KEY>-<description>
- type: feature (a feature; a GSD milestone), unit (a contained task within a feature; a GSD phase), bug, docs, or tmp (throwaway, never merged)
- KEY: the Jira ticket, from any project, when there is one; otherwise leave it out: <type>/<description>
- description: lower-case words joined by hyphens
Base it on the trunk unless the user says otherwise; a unit starts from its feature's branch.

If the user names an existing branch, git switch to it instead of creating one. A branch can be checked out in only one worktree at a time: if it is checked out elsewhere, say where and let the user choose."

jq -n --arg c "$context" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
exit 0
