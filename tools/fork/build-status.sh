#!/usr/bin/env bash
#
# Show whether the fork's "macOS 15 arm64" job built a DMG for a branch.
#
#   tools/fork/build-status.sh [<branch>] [--commit <sha>] [--wait] [--quiet]
#
#   <branch>        main or staging (default: staging)
#   --commit <sha>  look at the run for this exact commit instead of the newest
#   --wait          poll until the arm64 job finishes (checks every 2 min, ~3 h max)
#   --quiet         print only the final verdict line
#
# Exit codes: 0 = arm64 job succeeded (DMG artifact listed when present),
#             1 = job failed/cancelled or the run is missing,
#             2 = still queued/running (without --wait).
#
set -euo pipefail
# shellcheck source=tools/fork/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

BRANCH="$STAGING_BRANCH"
COMMIT=""
WAIT=0
QUIET=0
while [ $# -gt 0 ]; do
  case "$1" in
    --commit) COMMIT="${2:-}"; shift ;;
    --wait) WAIT=1 ;;
    --quiet) QUIET=1 ;;
    --help | -h) sed -n '2,17p' "$0"; exit 0 ;;
    -*) die "unknown argument '$1'" ;;
    *) BRANCH="$1" ;;
  esac
  shift
done

require_cmd gh
check_gh_auth
check_actions_enabled

say() { [ "$QUIET" = "1" ] || log "$*"; }

# Newest run of the workflow that builds this branch (Release for main,
# "Pull request or branch build" for everything else), optionally for one commit.
find_run() {
  local wf args
  if [ "$BRANCH" = "$MAIN_BRANCH" ]; then wf="release.yml"; else wf="develop.yml"; fi
  args=(-R "$FORK_REPO" --branch "$BRANCH" --workflow "$wf" --limit 1
    --json databaseId,status,conclusion,headSha,createdAt,url,event)
  [ -n "$COMMIT" ] && args+=(--commit "$COMMIT")
  gh run list "${args[@]}" --jq '.[0] // empty'
}

# Prints: "<status> <conclusion>" of the arm64 job in run $1 ("" if not present yet).
arm64_job_state() {
  gh run view "$1" -R "$FORK_REPO" --json jobs \
    --jq --arg job "$BUILD_JOB_NAME" \
    '.jobs[] | select(.name | endswith($job)) | "\(.status) \(.conclusion)"' 2>/dev/null | head -n 1
}

list_arm64_artifacts() {
  gh api "repos/$FORK_REPO/actions/runs/$1/artifacts" \
    --jq --arg suf "$ARTIFACT_SUFFIX" \
    '.artifacts[] | select(.name | endswith($suf)) | "\(.name)  \(.size_in_bytes / 1048576 | floor) MiB  expired=\(.expired)  expires=\(.expires_at)"' 2>/dev/null || true
}

deadline=$(( $(date +%s) + 3 * 60 * 60 ))
while :; do
  RUN="$(find_run)"
  if [ -z "$RUN" ]; then
    if [ "$WAIT" = "1" ] && [ "$(date +%s)" -lt "$deadline" ]; then
      say "no run yet for $BRANCH${COMMIT:+ @ $COMMIT}; waiting..."
      sleep 120
      continue
    fi
    log "no workflow run found on $FORK_REPO for branch '$BRANCH'${COMMIT:+ at $COMMIT}."
    log "trigger one with: git push origin <ref>:refs/heads/$BRANCH   or"
    log "  gh workflow run $([ "$BRANCH" = "$MAIN_BRANCH" ] && printf release.yml || printf develop.yml) -R $FORK_REPO --ref $BRANCH"
    exit 1
  fi
  RUN_ID="$(printf '%s' "$RUN" | jq -r .databaseId)"
  RUN_SHA="$(printf '%s' "$RUN" | jq -r .headSha)"
  RUN_URL="$(printf '%s' "$RUN" | jq -r .url)"
  RUN_STATUS="$(printf '%s' "$RUN" | jq -r .status)"
  say "run $RUN_ID ($RUN_STATUS) for $BRANCH @ ${RUN_SHA:0:10}: $RUN_URL"

  JOB="$(arm64_job_state "$RUN_ID")"
  JOB_STATUS="${JOB%% *}"
  JOB_CONCLUSION="${JOB#* }"
  case "$JOB_STATUS" in
    completed)
      case "$JOB_CONCLUSION" in
        success)
          ARTS="$(list_arm64_artifacts "$RUN_ID")"
          if [ -n "$ARTS" ]; then
            [ "$QUIET" = "1" ] || printf '%s\n' "$ARTS" | sed "s/^/$SCRIPT_NAME:   artifact: /"
            log "OK: '$BUILD_JOB_NAME' succeeded for $BRANCH @ ${RUN_SHA:0:10} and a *$ARTIFACT_SUFFIX artifact exists."
          else
            log "OK-ish: '$BUILD_JOB_NAME' succeeded for $BRANCH @ ${RUN_SHA:0:10} but no *$ARTIFACT_SUFFIX artifact is listed (expired? check $RUN_URL)."
          fi
          exit 0
          ;;
        *)
          log "FAILED: '$BUILD_JOB_NAME' concluded '$JOB_CONCLUSION' for $BRANCH @ ${RUN_SHA:0:10}."
          log "  The Mac keeps the previous build. Logs: gh run view $RUN_ID -R $FORK_REPO --log-failed"
          exit 1
          ;;
      esac
      ;;
    '')
      # Job not created yet (stop-build gate still running, or the run was skipped).
      if [ "$RUN_STATUS" = "completed" ]; then
        log "run $RUN_ID completed without a '$BUILD_JOB_NAME' job."
        log "  On develop.yml this means the stop-build gate skipped it: branch '$BRANCH' has an open"
        log "  upstream PR. Never open upstream PRs from $STAGING_BRANCH or $MAIN_BRANCH."
        exit 1
      fi
      ;;
  esac
  if [ "$WAIT" = "1" ] && [ "$(date +%s)" -lt "$deadline" ]; then
    say "'$BUILD_JOB_NAME' is ${JOB_STATUS:-pending}; checking again in 2 min (builds take ~50-90 min)..."
    sleep 120
    continue
  fi
  log "PENDING: '$BUILD_JOB_NAME' is ${JOB_STATUS:-not started yet} for $BRANCH @ ${RUN_SHA:0:10} ($RUN_URL)."
  exit 2
done
