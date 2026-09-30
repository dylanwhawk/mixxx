#!/usr/bin/env bash
#
# Pull upstream (mixxxdj/mixxx) main into the fork's main, then refresh staging.
#
#   tools/fork/sync-upstream.sh [--no-stage]
#
# Merges upstream/main into origin/main in a temporary worktree (fast-forward
# when possible, otherwise a merge commit), pushes main, then merges main into
# staging via stage.sh so staging keeps containing main. --no-stage skips the
# staging refresh. Conflicts abort with nothing pushed.
#
set -euo pipefail
# shellcheck source=tools/fork/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

NO_STAGE=0
while [ $# -gt 0 ]; do
  case "$1" in
    --no-stage) NO_STAGE=1 ;;
    --help | -h) sed -n '2,11p' "$0"; exit 0 ;;
    *) die "unknown argument '$1'" ;;
  esac
  shift
done

require_cmd git gh
gate "1/4 remotes"
check_remotes
check_gh_auth
log "ok"

gate "2/4 fetch"
git -C "$REPO_ROOT" fetch --quiet origin
git -C "$REPO_ROOT" fetch --quiet upstream "$MAIN_BRANCH"
MAIN_SHA="$(git -C "$REPO_ROOT" rev-parse "refs/remotes/origin/$MAIN_BRANCH")"
UP_SHA="$(git -C "$REPO_ROOT" rev-parse "refs/remotes/upstream/$MAIN_BRANCH")"
if git -C "$REPO_ROOT" merge-base --is-ancestor "$UP_SHA" "$MAIN_SHA"; then
  log "origin/$MAIN_BRANCH already contains upstream/$MAIN_BRANCH @ ${UP_SHA:0:10}; nothing to merge."
  exit 0
fi
log "upstream/$MAIN_BRANCH @ ${UP_SHA:0:10} has $(git -C "$REPO_ROOT" rev-list --count "$MAIN_SHA..$UP_SHA") new commit(s)."

gate "3/4 merge upstream into $MAIN_BRANCH and push"
make_tmp_worktree "$MAIN_SHA"
git -C "$TMP_WORKTREE" merge --no-edit "$UP_SHA" -m "Merge upstream/$MAIN_BRANCH (${UP_SHA:0:10}) into fork $MAIN_BRANCH" || {
  git -C "$TMP_WORKTREE" merge --abort >/dev/null 2>&1 || true
  die "merging upstream/$MAIN_BRANCH conflicted; nothing was pushed.
  Resolve by hand: git worktree add /tmp/mixxx-sync origin/$MAIN_BRANCH && git -C /tmp/mixxx-sync merge upstream/$MAIN_BRANCH"
}
NEW_MAIN="$(git -C "$TMP_WORKTREE" rev-parse HEAD)"
"$FORK_TOOLS_DIR/check-build-job.sh" "$NEW_MAIN"
git -C "$REPO_ROOT" push origin "$NEW_MAIN:refs/heads/$MAIN_BRANCH"
cleanup_tmp_worktree
if [ "$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD || true)" = "$MAIN_BRANCH" ] &&
  [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
  git -C "$REPO_ROOT" merge --ff-only "refs/remotes/origin/$MAIN_BRANCH" >/dev/null && log "local $MAIN_BRANCH fast-forwarded."
fi
log "ok — origin/$MAIN_BRANCH is now ${NEW_MAIN:0:10} (release.yml builds it; ~50-90 min)."

gate "4/4 refresh $STAGING_BRANCH"
if [ "$NO_STAGE" = "1" ]; then
  log "skipped (--no-stage). Run tools/fork/stage.sh $MAIN_BRANCH later so staging contains main."
elif git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/remotes/origin/$STAGING_BRANCH" >/dev/null; then
  "$FORK_TOOLS_DIR/stage.sh" "$MAIN_BRANCH"
else
  log "origin/$STAGING_BRANCH does not exist; nothing to refresh."
fi
