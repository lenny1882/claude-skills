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
                   (default: <repo-parent>/<repo-name>-worktrees)
  --remove         Remove the worktrees for these phases instead of creating
  --force          With --remove, remove even with uncommitted changes
  --dry-run        Print what would happen, change nothing
  -h, --help       This text

WHAT EACH WORKTREE GETS
  * Its own branch, named from the phase directory:
      01-non-product-requests-hbd20-1786
        -> unit/HBD20-1786-non-product-requests-phase
    Phases with no ticket id fall back to gsd/phase-<n>-<slug>.
  * A real .claude/ directory holding copies of the main checkout's
    settings.json and settings.local.json. Copies, not symlinks: Claude Code
    creates subagent worktrees under .claude/worktrees/, and a symlink puts
    that path outside the session's writable area, which breaks parallel
    plan execution inside the phase.
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
REPO_NAME=${REPO_ROOT##*/}
GIT_COMMON=$(cd "$REPO_ROOT" && git rev-parse --git-common-dir)
case "$GIT_COMMON" in
  /*) ;;
  *) GIT_COMMON="$REPO_ROOT/$GIT_COMMON" ;;
esac

PHASE_DIR_ROOT="$REPO_ROOT/.planning/phases"
[ -d "$PHASE_DIR_ROOT" ] \
  || die "no .planning/phases in $REPO_ROOT — is this a GSD project?"

[ -n "$WT_ROOT" ] || WT_ROOT="${REPO_ROOT%/*}/${REPO_NAME}-worktrees"

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

remove_phase() {
  derive_names "$1"

  if [ ! -d "$WT_PATH" ]; then
    say "  phase $NUM: no worktree at $WT_PATH — nothing to remove"
    return 0
  fi

  local dirty unmerged=0
  dirty=$(git -C "$WT_PATH" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
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

  if [ "$FORCE" -eq 1 ]; then
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

# A real directory with copied settings — never a symlink. See usage().
seed_claude_dir() {
  local wt=$1 f
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

# Add .claude/ to the shared exclude file once.
exclude_claude_dir() {
  local ex="$GIT_COMMON/info/exclude"
  if [ -f "$ex" ] && grep -qxF '.claude/' "$ex"; then
    return 0
  fi
  if [ "$DRY" -eq 1 ]; then
    say "  would append '.claude/' to $ex"
    return 0
  fi
  mkdir -p "${ex%/*}"
  printf '\n# Per-worktree Claude Code config (phase-worktrees)\n.claude/\n' >>"$ex"
  say "  added '.claude/' to $ex"
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
exclude_claude_dir

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
