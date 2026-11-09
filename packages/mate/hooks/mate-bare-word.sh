#!/usr/bin/env bash
# UserPromptSubmit: a message that is only "mate", "bruv" or "dude" runs the
# mate skill.
#
# Why this exists: typing the bare word is what the user actually does when an
# answer misses the point — the slash is the part that gets left off. Without
# this hook a bare "mate" is an ordinary message and Claude guesses at it.
#
# Why it injects the skill's text instead of telling Claude to call the Skill
# tool: the skill is disable-model-invocation, so Claude cannot load it, and
# that flag stays on so the skill is never pulled in uninvited mid-answer. A
# hook cannot rewrite the prompt either; additionalContext is the only route.
#
# Anything else, including "mate, why?" or a sentence containing the word,
# passes through untouched: the word is only an instruction when it stands
# alone. Never blocks, and fails open — a missing jq or skill file means the
# message goes through as typed.
set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null) || exit 0

# Trim whitespace, drop trailing punctuation, lower-case.
word=$(printf '%s' "$prompt" | tr -d '\r' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' \
  -e 's/[[:punct:]]*$//' | tr '[:upper:]' '[:lower:]')
case "$word" in
  mate|bruv|dude) ;;
  *) exit 0 ;;
esac

skill="${CLAUDE_DIR:-$HOME/.claude}/skills/mate/SKILL.md"
[ -f "$skill" ] || exit 0
# The body only: the frontmatter is for Claude Code's skill loader.
body=$(awk 'NR==1 && /^---$/ {fm=1; next} fm && /^---$/ {fm=0; next} !fm' "$skill")

jq -n --arg w "$word" --arg body "$body" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: ("The user'"'"'s message is only \"" + $w + "\", which runs the mate skill. Follow these instructions now:\n\n" + $body)
  }
}'
