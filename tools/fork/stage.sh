#!/usr/bin/env bash
#
# Put a branch on `staging` so the other Mac installs it as "Mixxx Staging".
#
#   tools/fork/stage.sh <branch> [--replace]
#
#   default    merge <branch> into origin/staging (--no-ff) in a temporary
#              worktree and push. Your checkout is not touched.
#   --replace  make staging exactly <branch> (force-push with lease). Use when
#              staging has junk you want gone or a rebased feature.
#
# Gates: remotes, gh auth, Actions enabled, branch exists, no upstream PR open
# from staging, the "macOS 15 arm64" job intact on the branch, staging contains
# main (merged in automatically). A conflict aborts and leaves staging unchanged.
#
set -euo pipefail
# shellcheck source=tools/fork/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REPLACE=0
BRANCH=""
while [ $# -gt 0 ]; do
  case "$1" in
    --replace) REPLACE=1 ;;
    --help | -h) sed -n '2,16p' "$0"; exit 0 ;;
    -*) die "unknown argument '$1'" ;;
    *) [ -z "$BRANCH" ] || die "only one branch may be given"; BRANCH="$1" ;;
  esac
  shift
done
[ -n "$BRANCH" ] || die "usage: tools/fork/stage.sh <branch> [--replace]"
[ "$BRANCH" != "$STAGING_BRANCH" ] || die "'$STAGING_BRANCH' cannot be staged onto itself."
[[ "$BRANCH" =~ ^[A-Za-z0-9._/-]+$ ]] || die "invalid branch name: $BRANCH"

require_cmd git gh
gate "1/6 remotes, gh login, Actions"
check_remotes
check_gh_auth
check_actions_enabled
log "ok"

gate "2/6 branch '$BRANCH' exists"
git -C "$REPO_ROOT" fetch --quiet origin
if git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/heads/$BRANCH" >/dev/null; then
  SRC="refs/heads/$BRANCH"
elif git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/remotes/origin/$BRANCH" >/dev/null; then
  SRC="refs/remotes/origin/$BRANCH"
else
  die "no local or origin branch named '$BRANCH'."
fi
SRC_SHA="$(git -C "$REPO_ROOT" rev-parse "$SRC")"
log "ok — $SRC @ ${SRC_SHA:0:10}"

gate "3/6 no open upstream PR from '$STAGING_BRANCH'"
N="$(open_upstream_prs_for "$STAGING_BRANCH")"
[ "$N" = "0" ] || die "$N open PR(s) on $UPSTREAM_REPO from ${FORK_REPO%%/*}:$STAGING_BRANCH.
  develop.yml skips fork builds for branches with an open upstream PR, so staging
  would never build. Close that PR (re-open it from a feature branch)."
log "ok"

gate "4/6 '$BUILD_JOB_NAME' job intact on $BRANCH"
"$FORK_TOOLS_DIR/check-build-job.sh" "$SRC_SHA"

gate "5/6 build new $STAGING_BRANCH"
if git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/remotes/origin/$STAGING_BRANCH" >/dev/null; then
  OLD_STAGING="$(git -C "$REPO_ROOT" rev-parse "refs/remotes/origin/$STAGING_BRANCH")"
else
  OLD_STAGING=""
fi
MAIN_SHA="$(git -C "$REPO_ROOT" rev-parse "refs/remotes/origin/$MAIN_BRANCH")"

if [ "$REPLACE" = "1" ]; then
  git -C "$REPO_ROOT" merge-base --is-ancestor "$MAIN_SHA" "$SRC_SHA" ||
    die "'$BRANCH' does not contain origin/$MAIN_BRANCH, so a later promote could not fast-forward.
  Merge or rebase '$BRANCH' onto $MAIN_BRANCH first."
  NEW_STAGING="$SRC_SHA"
  log "staging will be replaced by $BRANCH @ ${SRC_SHA:0:10}"
else
  make_tmp_worktree "${OLD_STAGING:-$MAIN_SHA}"
  [ -n "$OLD_STAGING" ] || log "origin/$STAGING_BRANCH does not exist yet — creating it from $MAIN_BRANCH."
  if ! git -C "$TMP_WORKTREE" merge-base --is-ancestor "$MAIN_SHA" HEAD; then
    log "$STAGING_BRANCH is behind $MAIN_BRANCH — merging origin/$MAIN_BRANCH first."
    git -C "$TMP_WORKTREE" merge --no-edit "$MAIN_SHA" -m "stage: merge $MAIN_BRANCH into $STAGING_BRANCH" || {
      git -C "$TMP_WORKTREE" merge --abort >/dev/null 2>&1 || true
      die "merging $MAIN_BRANCH into $STAGING_BRANCH conflicted; staging is unchanged.
  Resolve by hand in a worktree of $STAGING_BRANCH, or use --replace with a branch that contains $MAIN_BRANCH."
    }
  fi
  if git -C "$TMP_WORKTREE" merge-base --is-ancestor "$SRC_SHA" HEAD; then
    log "$STAGING_BRANCH already contains $BRANCH @ ${SRC_SHA:0:10}."
  else
    git -C "$TMP_WORKTREE" merge --no-ff --no-edit "$SRC_SHA" -m "stage: merge $BRANCH (${SRC_SHA:0:10})" || {
      git -C "$TMP_WORKTREE" merge --abort >/dev/null 2>&1 || true
      die "merging '$BRANCH' into $STAGING_BRANCH conflicted; staging is unchanged.
  Rebase '$BRANCH' onto $MAIN_BRANCH (or merge origin/$STAGING_BRANCH into it), resolve, then re-run.
  Alternatively: tools/fork/stage.sh $BRANCH --replace"
    }
  fi
  NEW_STAGING="$(git -C "$TMP_WORKTREE" rev-parse HEAD)"
fi

if [ "$NEW_STAGING" = "$OLD_STAGING" ]; then
  log "origin/$STAGING_BRANCH is already at ${NEW_STAGING:0:10}; nothing to push."
  exit 0
fi

gate "6/6 push $STAGING_BRANCH"
if [ -n "$OLD_STAGING" ]; then
  git -C "$REPO_ROOT" push --force-with-lease="refs/heads/$STAGING_BRANCH:$OLD_STAGING" \
    origin "$NEW_STAGING:refs/heads/$STAGING_BRANCH"
else
  git -C "$REPO_ROOT" push origin "$NEW_STAGING:refs/heads/$STAGING_BRANCH"
fi
cleanup_tmp_worktree

printf '\n'
log "SUCCESS — origin/$STAGING_BRANCH is now ${NEW_STAGING:0:10}."
log "  develop.yml builds it now (~50-90 min). Watch with:"
log "    tools/fork/build-status.sh $STAGING_BRANCH --wait"
log "  When the '$BUILD_JOB_NAME' job is green, 'Mixxx Staging' on the other Mac installs it on next launch."
