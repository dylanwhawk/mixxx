#!/usr/bin/env bash
#
# Verify that the CI job the Mac launcher depends on is intact.
#
#   tools/fork/check-build-job.sh [<git-ref>]
#
# Checks, in the working tree (default) or at <git-ref>:
#   - build.yml still has the "macOS 15 arm64" matrix entry producing build/*.dmg
#   - build.yml still has the "Upload GitHub Actions artifacts" step with archive: "false"
#   - release.yml and develop.yml still call build.yml
# Exit 0 when everything is in place, 1 otherwise. Used as a gate by stage.sh
# and promote.sh; never edit those workflow pieces on the fork.
#
set -euo pipefail
# shellcheck source=tools/fork/lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

REF="${1:-}"

read_file() {
  if [ -n "$REF" ]; then
    git -C "$REPO_ROOT" show "$REF:$1" 2>/dev/null || die "cannot read $1 at '$REF'."
  else
    cat "$REPO_ROOT/$1"
  fi
}

BUILD_YML="$(read_file .github/workflows/build.yml)"
RELEASE_YML="$(read_file .github/workflows/release.yml)"
DEVELOP_YML="$(read_file .github/workflows/develop.yml)"

fail=0
where="${REF:-working tree}"

# Matrix entry: from "- name: macOS 15 arm64" up to the next "- name:".
ENTRY="$(printf '%s\n' "$BUILD_YML" | awk -v job="$BUILD_JOB_NAME" '
  $0 ~ "^[[:space:]]*- name: " job "[[:space:]]*$" { inblock = 1; print; next }
  inblock && $0 ~ "^[[:space:]]*- name: " { exit }
  inblock { print }
')"
if [ -z "$ENTRY" ]; then
  log "FAIL ($where): build.yml has no matrix entry named '$BUILD_JOB_NAME'."
  fail=1
else
  printf '%s\n' "$ENTRY" | grep -Eq 'artifacts_path:[[:space:]]*build/\*\.dmg' ||
    { log "FAIL ($where): '$BUILD_JOB_NAME' no longer uploads build/*.dmg."; fail=1; }
  printf '%s\n' "$ENTRY" | grep -Eq 'cpack_generator:[[:space:]]*DragNDrop' ||
    { log "FAIL ($where): '$BUILD_JOB_NAME' no longer uses the DragNDrop (DMG) generator."; fail=1; }
fi

printf '%s\n' "$BUILD_YML" | grep -Eq 'name:[[:space:]]*"Upload GitHub Actions artifacts"' ||
  { log "FAIL ($where): build.yml lost the 'Upload GitHub Actions artifacts' step."; fail=1; }
printf '%s\n' "$BUILD_YML" | awk '
  /name:[[:space:]]*"Upload GitHub Actions artifacts"/ { inblock = 1; next }
  inblock && /^[[:space:]]*- name:/ { exit }
  inblock { print }
' | grep -Eq 'archive:[[:space:]]*"false"' ||
  { log "FAIL ($where): the artifact upload step no longer sets archive: \"false\" (the Mac launcher needs a bare .dmg)."; fail=1; }

printf '%s\n' "$RELEASE_YML" | grep -Eq 'uses:[[:space:]]*\./\.github/workflows/build\.yml' ||
  { log "FAIL ($where): release.yml no longer calls build.yml (main builds would stop)."; fail=1; }
printf '%s\n' "$DEVELOP_YML" | grep -Eq 'uses:[[:space:]]*\./\.github/workflows/build\.yml' ||
  { log "FAIL ($where): develop.yml no longer calls build.yml (staging builds would stop)."; fail=1; }

if [ "$fail" != "0" ]; then
  die "the '$BUILD_JOB_NAME' build job or its artifact upload is missing or changed at $where.
  The Mac launcher installs the *$ARTIFACT_SUFFIX artifact from exactly that job.
  Restore the workflow files to match upstream before staging or promoting."
fi
log "ok ($where): '$BUILD_JOB_NAME' job, DMG artifact upload, and workflow wiring are intact."
