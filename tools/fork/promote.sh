#!/usr/bin/env bash
#
# Promote the tested `staging` commit to `main` (fast-forward only) so the
# other Mac installs it as "Mixxx Fork".
#
#   tools/fork/promote.sh [--yes]
#
#   --yes   skip the interactive confirmation. Pass it ONLY after the human
#           operator has tested "Mixxx Staging" on the Mac and explicitly
#           approved promoting this exact commit. Agents never decide this.
#
# Gates: remotes/gh/Actions, staging exists and is a fast-forward of main,
# the "macOS 15 arm64" job intact, that job succeeded for the staging commit,
# then the operator confirmation. main is never force-pushed.
#
set -euo pipefail
# shellcheck source=tools/fork/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

YES=0
while [ $# -gt 0 ]; do
  case "$1" in
    --yes) YES=1 ;;
    --help | -h) sed -n '2,15p' "$0"; exit 0 ;;
    *) die "unknown argument '$1'" ;;
  esac
  shift
done

require_cmd git gh
gate "1/5 remotes, gh login, Actions"
check_remotes
check_gh_auth
check_actions_enabled
log "ok"

gate "2/5 $STAGING_BRANCH is a fast-forward of $MAIN_BRANCH"
git -C "$REPO_ROOT" fetch --quiet origin
git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/remotes/origin/$STAGING_BRANCH" >/dev/null ||
  die "origin/$STAGING_BRANCH does not exist. Stage something first: tools/fork/stage.sh <branch>"
STAGING_SHA="$(git -C "$REPO_ROOT" rev-parse "refs/remotes/origin/$STAGING_BRANCH")"
MAIN_SHA="$(git -C "$REPO_ROOT" rev-parse "refs/remotes/origin/$MAIN_BRANCH")"
[ "$STAGING_SHA" != "$MAIN_SHA" ] || die "$STAGING_BRANCH and $MAIN_BRANCH are the same commit; nothing to promote."
git -C "$REPO_ROOT" merge-base --is-ancestor "$MAIN_SHA" "$STAGING_SHA" ||
  die "origin/$MAIN_BRANCH is not an ancestor of origin/$STAGING_BRANCH, so this is not a fast-forward.
  Bring $MAIN_BRANCH into $STAGING_BRANCH first (tools/fork/stage.sh $MAIN_BRANCH), test again, then promote."
COUNT="$(git -C "$REPO_ROOT" rev-list --count "$MAIN_SHA..$STAGING_SHA")"
log "ok — $COUNT commit(s) would land on $MAIN_BRANCH:"
git -C "$REPO_ROOT" log --oneline --no-decorate "$MAIN_SHA..$STAGING_SHA" | sed 's/^/  /'

gate "3/5 '$BUILD_JOB_NAME' job intact on $STAGING_BRANCH"
"$FORK_TOOLS_DIR/check-build-job.sh" "$STAGING_SHA"

gate "4/5 '$BUILD_JOB_NAME' succeeded for $STAGING_BRANCH @ ${STAGING_SHA:0:10}"
if ! "$FORK_TOOLS_DIR/build-status.sh" "$STAGING_BRANCH" --commit "$STAGING_SHA"; then
  die "no successful '$BUILD_JOB_NAME' build for that exact commit — it was never installable as
  'Mixxx Staging', so it cannot have been tested. Wait for the build (build-status.sh --wait) or fix it."
fi

gate "5/5 operator approval"
log "Promoting means 'Mixxx Fork' (the real library) installs this build on next launch."
if [ "$YES" = "1" ]; then
  log "--yes given: the operator approved promoting ${STAGING_SHA:0:10} after testing 'Mixxx Staging'."
else
  if [ ! -t 0 ]; then
    die "stdin is not a terminal, so approval cannot be confirmed.
  The human operator tests 'Mixxx Staging' on the Mac, then either runs this script at a
  terminal or tells the agent to re-run it with --yes for commit ${STAGING_SHA:0:10}."
  fi
  printf '%s: has "Mixxx Staging" @ %s been tested on the Mac? Promote to main? [y/N] ' "$SCRIPT_NAME" "${STAGING_SHA:0:10}" >&2
  IFS= read -r REPLY
  case "$REPLY" in
    y | Y | yes | YES | Yes) ;;
    *) die "not approved; $MAIN_BRANCH is unchanged." ;;
  esac
fi

git -C "$REPO_ROOT" push origin "$STAGING_SHA:refs/heads/$MAIN_BRANCH"

# Keep the local main in step when it is checked out and clean; otherwise leave it.
if [ "$(git -C "$REPO_ROOT" symbolic-ref --quiet --short HEAD || true)" = "$MAIN_BRANCH" ] &&
  [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
  git -C "$REPO_ROOT" merge --ff-only "refs/remotes/origin/$MAIN_BRANCH" >/dev/null && log "local $MAIN_BRANCH fast-forwarded."
elif git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/heads/$MAIN_BRANCH" >/dev/null; then
  git -C "$REPO_ROOT" branch -f "$MAIN_BRANCH" "refs/remotes/origin/$MAIN_BRANCH" 2>/dev/null && log "local $MAIN_BRANCH moved to origin/$MAIN_BRANCH." || true
fi

printf '\n'
log "SUCCESS — origin/$MAIN_BRANCH is now ${STAGING_SHA:0:10} ($COUNT commit(s))."
log "  release.yml builds it now (~50-90 min); changelog/publish/signing jobs fail on the fork — ignore them."
log "  Watch with: tools/fork/build-status.sh $MAIN_BRANCH --wait"
