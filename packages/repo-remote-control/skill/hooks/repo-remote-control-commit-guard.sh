#!/usr/bin/env bash
# PreToolUse on Bash: blocks `git commit` on a detached HEAD in a Remote
# Control server session's worktree (.claude/worktrees/bridge-*).
#
# Why: the SessionStart hook leaves those sessions detached so each names its
# own branch. A commit made before that lands on no branch, and is easy to
# lose when the server cleans the worktree up. This is the backstop for the
# session's instructions, not the main defence.
#
# Advisory, by decision (DESIGN.md, 22 Oct): it sees only commands Claude runs
# through Bash. A commit made another way gets past it: a GSD MCP tool such as
# gsd_commit_docs, a git alias, a script that commits inside it.
#
# What it reads: the command split at && || ; | and newlines; `cd <dir>`
# moves where later git commands run; `git -C <dir>` sets it for one. A
# `git switch` or `git checkout` earlier in the same command, without
# --detach, puts HEAD on a branch before the commit, so that commit is let
# through. Quoting is not parsed, so quoted text that looks like a command is
# read as one: in a detached bridge worktree, `echo "a && git commit"` is
# blocked too. The session can say it another way; a missed real commit would
# be worse.

set -uo pipefail

input=$(cat)
cmd=$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null)
case $cmd in *commit*) ;; *) exit 0 ;; esac
cwd=$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)
cwd=${cwd:-$PWD}

resolve() { # base dir
	case $2 in
		/*) printf '%s' "$2" ;;
		"~"|"~/"*) printf '%s' "$HOME${2#\~}" ;;
		*) printf '%s/%s' "$1" "$2" ;;
	esac
}

# a bridge-* worktree with HEAD on no branch
detachedBridge() {
	local top
	top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) || return 1
	case $top in */.claude/worktrees/bridge-*) ;; *) return 1 ;; esac
	! git -C "$top" symbolic-ref -q HEAD >/dev/null 2>&1
}

dir=$cwd switched=no
while IFS= read -r seg; do
	read -r -a w <<<"$seg" || true
	[ "${#w[@]}" -gt 0 ] || continue
	i=0
	while [ "$i" -lt "${#w[@]}" ] && [[ ${w[$i]} == *=* && ${w[$i]} != -* ]]; do i=$((i + 1)); done
	[ "$i" -lt "${#w[@]}" ] || continue
	case ${w[$i]} in
		cd) dir=$(resolve "$dir" "${w[$((i + 1))]:-$HOME}"); continue ;;
		git) ;;
		*) continue ;;
	esac
	gdir=$dir sub=""
	i=$((i + 1))
	while [ "$i" -lt "${#w[@]}" ]; do
		case ${w[$i]} in
			-C) gdir=$(resolve "$gdir" "${w[$((i + 1))]:-}"); i=$((i + 2)) ;;
			-c|--git-dir|--work-tree|--namespace) i=$((i + 2)) ;;
			-*) i=$((i + 1)) ;;
			*) sub=${w[$i]}; break ;;
		esac
	done
	case $sub in
		switch|checkout)
			case " ${w[*]} " in *" --detach "*|*" -d "*) ;; *) switched=yes ;; esac ;;
		commit)
			if [ "$switched" = no ] && detachedBridge "$gdir"; then
				cat >&2 <<-'EOF'
					Blocked: this Remote Control worktree is on a detached HEAD, so the commit would be on no branch.
					Create the task's branch first, then commit:
					  git switch -c <type>/<KEY>-<description>
					type is feature, unit, bug, docs or tmp; KEY is the Jira ticket if there is one, otherwise <type>/<description>.
				EOF
				exit 2
			fi ;;
	esac
done < <(printf '%s\n' "$cmd" | sed -E 's/(&&|\|\||;|\|)/\n/g')
exit 0
