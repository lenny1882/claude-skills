#!/usr/bin/env bash
#
# phase-worktrees — create one git worktree per GSD phase so phases can be
# executed in parallel, each on its own branch, from its own Claude session.
#
# Every path is derived at runtime from `git rev-parse`. Nothing is hardcoded.

set -euo pipefail

PROG=${0##*/}

# ---------------------------------------------------------------- usage ----

usage() {
  cat <<EOF
$PROG — one git worktree per GSD phase

USAGE
  $PROG [options] <phase> [<phase> ...]
  $PROG --remove [--force] <phase> [<phase> ...]

  Phases are given as they appear in .planning/phases/ — "1", "01" and
  "999.1" all work.

OPTIONS
  --base <ref>     Base for new branches (default: current branch)
  --root <dir>     Worktree parent directory
                   (default: <repo>/.worktrees, kept out of git status
                   through .git/info/exclude)
  --remove         Remove the worktrees for these phases instead of creating
  --force          With --remove, remove even with uncommitted changes
  --dry-run        Print what would happen, change nothing
  -h, --help       This text

WHAT EACH WORKTREE GETS
  * Its own branch, named from the phase directory:
      01-new-settings-page-abc-123
        -> unit/ABC-123-new-settings-page-phase
    Phases with no ticket id fall back to gsd/phase-<n>-<slug>.
  * .claude as a symlink to the main checkout's .claude, so permission
    approvals carry between the phases and the main checkout. When the repo
    tracks anything under .claude/ in git, a real .claude/ directory with
    copies of settings.json and settings.local.json instead: a symlink there
    would show the tracked files as deleted in the worktree.
  * Symlinks to gitignored build directories in the main checkout
    (vendor, node_modules, .venv, target, build) so they are not duplicated.
  * .planning/STATE.md and .planning/ROADMAP.md marked skip-worktree, so
    phase commits never carry shared milestone bookkeeping.

NOT COPIED
  Gitignored config files such as .env. Copy those yourself if the phase
  needs to run the app.
EOF
}

die() { printf '%s: %s\n' "$PROG" "$*" >&2; exit 1; }
say() { printf '%s\n' "$*"; }

# ------------------------------------------------------------- options ----

BASE=""
WT_ROOT=""
MODE="create"
FORCE=0
DRY=0
PHASES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --base)    [ $# -ge 2 ] || die "--base needs a value"; BASE=$2; shift 2 ;;
    --root)    [ $# -ge 2 ] || die "--root needs a value"; WT_ROOT=$2; shift 2 ;;
    --remove)  MODE="remove"; shift ;;
    --force)   FORCE=1; shift ;;
    --dry-run) DRY=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [ $# -gt 0 ]; do PHASES+=("$1"); shift; done ;;
    -*) die "unknown option: $1 (try --help)" ;;
    *)  PHASES+=("$1"); shift ;;
  esac
done

[ ${#PHASES[@]} -gt 0 ] || { usage >&2; die "no phases given"; }

run() {
  if [ "$DRY" -eq 1 ]; then
    printf '  would run:'; printf ' %q' "$@"; printf '\n'
  else
    "$@"
  fi
}

# ------------------------------------------------------------ preflight ----

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) \
  || die "not inside a git repository"
GIT_COMMON=$(cd "$REPO_ROOT" && git rev-parse --git-common-dir)
case "$GIT_COMMON" in
  /*) ;;
  *) GIT_COMMON="$REPO_ROOT/$GIT_COMMON" ;;
esac

PHASE_DIR_ROOT="$REPO_ROOT/.planning/phases"
[ -d "$PHASE_DIR_ROOT" ] \
  || die "no .planning/phases in $REPO_ROOT — is this a GSD project?"

# Inside the repo by default. The old default, <repo-parent>/<repo-name>-worktrees,
# was outside every sandboxed session's writable area: mkdir and git worktree
# add both failed with "Read-only file system", so the skill only worked with
# --root. Inside the repo, git would list the whole worktree as untracked, so
# exclude_entries adds the root to info/exclude alongside .claude/.
[ -n "$WT_ROOT" ] || WT_ROOT="$REPO_ROOT/.worktrees"
case "$WT_ROOT" in
  /*) ;;
  *) WT_ROOT="$REPO_ROOT/$WT_ROOT" ;;
esac

if [ -z "$BASE" ]; then
  BASE=$(cd "$REPO_ROOT" && git rev-parse --abbrev-ref HEAD)
  [ "$BASE" != "HEAD" ] || die "detached HEAD — pass --base explicitly"
fi

# ------------------------------------------------------ phase resolution ----

# Print the single .planning/phases entry matching $1. Returns non-zero and
# explains on stderr if the argument matches none or several.
resolve_phase_dir() {
  local want=$1 d name num
  local matches=()
  for d in "$PHASE_DIR_ROOT"/*/; do
    [ -d "$d" ] || continue
    d=${d%/}
    name=${d##*/}
    num=${name%%-*}
    # Match the literal argument, or the same number without zero padding.
    if [ "$num" = "$want" ] || [ "${num#0}" = "${want#0}" ]; then
      matches+=("$d")
    fi
  done
  case ${#matches[@]} in
    1) printf '%s\n' "${matches[0]}"; return 0 ;;
    0) printf '%s: no phase directory matches "%s"\n' "$PROG" "$want" >&2 ;;
    *) printf '%s: "%s" matches %d phase directories — be more specific\n' \
         "$PROG" "$want" "${#matches[@]}" >&2 ;;
  esac
  return 1
}

# Set NUM, SLUG, TICKET, BRANCH, WT_PATH from a phase directory path.
derive_names() {
  local name=${1##*/} raw rest
  raw=${name%%-*}
  NUM=${raw#0}                       # 01 -> 1, 999.1 -> 999.1
  rest=${name#*-}
  # A trailing "<letters><digits>-<digits>" is a Jira-style ticket id.
  if [[ $rest =~ ^(.+)-([a-z][a-z0-9]*-[0-9]+)$ ]]; then
    SLUG=${BASH_REMATCH[1]}
    TICKET=$(printf '%s' "${BASH_REMATCH[2]}" | tr '[:lower:]' '[:upper:]')
    BRANCH="unit/${TICKET}-${SLUG}-phase"
  else
    SLUG=$rest
    TICKET=""
    BRANCH="gsd/phase-${NUM}-${SLUG}"
  fi
  WT_PATH="$WT_ROOT/p${NUM}-${SLUG}"
}

# ---------------------------------------------------------------- remove ----

# git status --porcelain for a worktree, minus what GSD itself leaves behind
# after a session: an untracked .planning/HANDOFF.json (resume state for
# /gsd:resume-work), and a .planning/config.json whose only change is the
# workflow._auto_chain_active flag or formatting. Those are not work, and
# counting them made --remove refuse every worktree a GSD session had run in,
# leaving --force — which also throws away real changes — as the only way out.
real_changes() {
  local wt=$1 line
  git -C "$wt" status --porcelain 2>/dev/null | while IFS= read -r line; do
    case "$line" in
      "?? .planning/HANDOFF.json") continue ;;
      " M .planning/config.json")
        if command -v jq >/dev/null 2>&1 \
           && [ "$(git -C "$wt" show HEAD:.planning/config.json 2>/dev/null | jq -S 'del(.workflow._auto_chain_active)' 2>/dev/null)" \
              = "$(jq -S 'del(.workflow._auto_chain_active)' "$wt/.planning/config.json" 2>/dev/null)" ] \
           && [ -n "$(jq -S . "$wt/.planning/config.json" 2>/dev/null)" ]; then
          continue
        fi ;;
    esac
    printf '%s\n' "$line"
  done
}

remove_phase() {
  derive_names "$1"

  # A worktree made before the default root moved into the repo, or with a
  # different --root, is not at WT_PATH. Find it by the branch it has checked
  # out instead, so --remove still works on it.
  if [ ! -d "$WT_PATH" ]; then
    local found
    found=$(git -C "$REPO_ROOT" worktree list --porcelain | awk -v b="refs/heads/$BRANCH" '
      /^worktree / { p = substr($0, 10) }
      $0 == "branch " b { print p; exit }')
    [ -n "$found" ] && [ -d "$found" ] && WT_PATH=$found
  fi
  if [ ! -d "$WT_PATH" ]; then
    say "  phase $NUM: no worktree at $WT_PATH — nothing to remove"
    return 0
  fi

  local dirty unmerged=0 leftovers=0
  dirty=$(real_changes "$WT_PATH" | wc -l | tr -d ' ')
  leftovers=$(( $(git -C "$WT_PATH" status --porcelain 2>/dev/null | wc -l | tr -d ' ') - dirty ))
  if [ "$dirty" -ne 0 ] && [ "$FORCE" -eq 0 ]; then
    say "  phase $NUM: SKIPPED — $dirty uncommitted change(s) in $WT_PATH"
    say "             commit them, or re-run with --force"
    return 0
  fi

  if git -C "$REPO_ROOT" rev-parse --verify --quiet "$BASE" >/dev/null 2>&1 \
     && git -C "$REPO_ROOT" rev-parse --verify --quiet "$BRANCH" >/dev/null 2>&1; then
    unmerged=$(git -C "$REPO_ROOT" rev-list --count "$BASE..$BRANCH" 2>/dev/null || printf '0')
  fi
  if [ "$unmerged" -ne 0 ]; then
    say "  phase $NUM: note — $BRANCH has $unmerged commit(s) not in $BASE (branch is kept)"
  fi

  if [ "$leftovers" -gt 0 ] && [ "$FORCE" -eq 0 ]; then
    say "  phase $NUM: discarding GSD's own session files ($leftovers) — no work in them"
  fi
  if [ "$FORCE" -eq 1 ] || [ "$leftovers" -gt 0 ]; then
    run git -C "$REPO_ROOT" worktree remove --force "$WT_PATH"
  else
    run git -C "$REPO_ROOT" worktree remove "$WT_PATH"
  fi
  say "  phase $NUM: removed $WT_PATH (branch $BRANCH kept)"
}

# ---------------------------------------------------------------- create ----

# Symlink gitignored build directories back to the main checkout.
link_build_dirs() {
  local wt=$1 d
  for d in vendor node_modules .venv target build; do
    [ -d "$REPO_ROOT/$d" ] || continue
    (cd "$REPO_ROOT" && git check-ignore -q "$d") || continue
    if [ -e "$wt/$d" ] || [ -L "$wt/$d" ]; then
      continue
    fi
    run ln -s "$REPO_ROOT/$d" "$wt/$d"
    LINKED+=("$d")
  done
  return 0
}

# A symlink to the main checkout's .claude, unless the repo tracks files under
# .claude/ — then a real directory with copied settings.
#
# This used to be copy-only, on the belief that a symlink put .claude/worktrees
# outside the session's writable area so agent worktrees failed and the wave
# ran one plan at a time. Tested on 9 Nov 2026 (BACKLOG.md item 2): two
# identical probes, one copied and one symlinked, both ran two 60-second plans
# in parallel. Claude Code creates agent worktrees itself, outside the Bash
# sandbox, and roots them at the main checkout either way. The symlink buys
# shared permission approvals.
#
# The copy stays for repos that track .claude/ content: the worktree checkout
# already holds those files, and replacing the directory with a symlink makes
# git in the worktree see every one of them as deleted.
seed_claude_dir() {
  local wt=$1 f
  if [ -z "$(git -C "$REPO_ROOT" ls-files -- .claude)" ] && [ ! -e "$wt/.claude" ]; then
    run mkdir -p "$REPO_ROOT/.claude"
    run ln -s "$REPO_ROOT/.claude" "$wt/.claude"
    CLAUDE_LINKED=1
    return 0
  fi
  run mkdir -p "$wt/.claude"
  for f in settings.json settings.local.json; do
    [ -f "$REPO_ROOT/.claude/$f" ] || continue
    run cp "$REPO_ROOT/.claude/$f" "$wt/.claude/$f"
  done
  return 0
}

# Keep shared milestone bookkeeping out of phase commits.
pin_shared_planning_files() {
  local wt=$1 f
  for f in .planning/STATE.md .planning/ROADMAP.md; do
    git -C "$wt" ls-files --error-unmatch "$f" >/dev/null 2>&1 || continue
    run git -C "$wt" update-index --skip-worktree "$f"
  done
  return 0
}

create_phase() {
  derive_names "$1"
  LINKED=()

  if [ -d "$WT_PATH" ]; then
    say "  phase $NUM: already exists at $WT_PATH — skipped"
    CREATED+=("$NUM|$BRANCH|$WT_PATH")
    return 0
  fi

  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    say "  phase $NUM: branch $BRANCH already exists — checking it out as is"
    run git -C "$REPO_ROOT" worktree add "$WT_PATH" "$BRANCH"
  else
    run git -C "$REPO_ROOT" worktree add -b "$BRANCH" "$WT_PATH" "$BASE"
  fi

  seed_claude_dir "$WT_PATH"
  link_build_dirs "$WT_PATH"
  if [ "$DRY" -eq 0 ]; then
    pin_shared_planning_files "$WT_PATH"
  fi

  local note=""
  [ ${#LINKED[@]} -eq 0 ] || note="  linked: ${LINKED[*]}"
  say "  phase $NUM: $WT_PATH  [$BRANCH]$note"
  CREATED+=("$NUM|$BRANCH|$WT_PATH")
}

# Add .claude/ to the shared exclude file once, and the worktree root too when
# it is inside the repo — otherwise git status in the main checkout lists every
# worktree as untracked. The root is anchored with a leading slash so only that
# directory is excluded, not any directory of the same name further down.
exclude_entries() {
  local ex="$GIT_COMMON/info/exclude" entry entries=(".claude/")
  # .claude/ matches only a directory; a symlinked .claude is a file to git.
  [ "${CLAUDE_LINKED:-0}" = 1 ] && entries+=("/.claude")
  case "$WT_ROOT/" in
    "$REPO_ROOT"/?*) entries+=("/${WT_ROOT#"$REPO_ROOT"/}/") ;;
  esac
  for entry in "${entries[@]}"; do
    if [ -f "$ex" ] && grep -qxF "$entry" "$ex"; then
      continue
    fi
    if [ "$DRY" -eq 1 ]; then
      say "  would append '$entry' to $ex"
      continue
    fi
    mkdir -p "${ex%/*}"
    case "$entry" in
      .claude/|/.claude) printf '\n# Per-worktree Claude Code config (phase-worktrees)\n%s\n' "$entry" >>"$ex" ;;
      *)        printf '\n# Phase worktrees inside the repo (phase-worktrees)\n%s\n' "$entry" >>"$ex" ;;
    esac
    say "  added '$entry' to $ex"
  done
}

# ------------------------------------------------------------------ main ----

say "repo:      $REPO_ROOT"
say "worktrees: $WT_ROOT"
if [ "$MODE" = "create" ]; then
  say "base:      $BASE"
fi
if [ "$DRY" -eq 1 ]; then
  say "(dry run — nothing will change)"
fi
say ""

DIRS=()
for p in "${PHASES[@]}"; do
  d=$(resolve_phase_dir "$p") || exit 1
  DIRS+=("$d")
done

if [ "$MODE" = "remove" ]; then
  for d in "${DIRS[@]}"; do remove_phase "$d"; done
  run git -C "$REPO_ROOT" worktree prune
  say ""
  say "Done."
  exit 0
fi

if [ "$DRY" -eq 1 ]; then
  say "  would mkdir -p $WT_ROOT"
else
  mkdir -p "$WT_ROOT"
fi

CREATED=()
for d in "${DIRS[@]}"; do create_phase "$d"; done
exclude_entries

say ""
say "Launch each phase in its own terminal:"
say ""
for entry in "${CREATED[@]}"; do
  IFS='|' read -r num branch path <<<"$entry"
  say "  cd $path && claude"
  say "    then: /gsd:execute-phase $num"
done
say ""
say "Shared milestone state (STATE.md, ROADMAP.md) stays with the main checkout."
say "Gitignored config such as .env is not copied — add it per worktree if needed."
