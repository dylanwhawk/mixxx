#!/usr/bin/env bash
# shellcheck shell=bash
#
# Shared helpers for the fork workflow scripts in tools/fork/.
# Source this file; do not run it. See .claude/skills/fork-dev/SKILL.md.

FORK_REPO="dylanwhawk/mixxx"
UPSTREAM_REPO="mixxxdj/mixxx"
MAIN_BRANCH="main"
STAGING_BRANCH="staging"
# The job in .github/workflows/build.yml whose DMG the Mac launcher installs.
BUILD_JOB_NAME="macOS 15 arm64"
# Artifact name suffix the Mac launcher looks for.
ARTIFACT_SUFFIX="-arm64.dmg"

FORK_TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$FORK_TOOLS_DIR/../.." && pwd)"
SCRIPT_NAME="$(basename "${0:-fork}")"

die() {
  printf '\n%s: ABORTED: %s\n' "$SCRIPT_NAME" "$*" >&2
  exit 1
}

log() {
  printf '%s: %s\n' "$SCRIPT_NAME" "$*"
}

gate() {
  printf '\n%s: gate %s\n' "$SCRIPT_NAME" "$*"
}

require_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || die "'$c' is not on PATH."
  done
}

# Remote URL -> "owner/repo" (works for https and ssh forms).
remote_slug() {
  local url
  url="$(git -C "$REPO_ROOT" remote get-url "$1" 2>/dev/null || true)"
  url="${url%.git}"
  url="${url%/}"
  case "$url" in
    *github.com[:/]*) printf '%s\n' "${url##*github.com[:/]}" ;;
    *) printf '%s\n' "$url" ;;
  esac
}

check_remotes() {
  local o u
  o="$(remote_slug origin)"
  u="$(remote_slug upstream)"
  [ "$o" = "$FORK_REPO" ] ||
    die "remote 'origin' must be $FORK_REPO (found '${o:-none}').
  Fix with: git remote set-url origin https://github.com/$FORK_REPO.git"
  [ "$u" = "$UPSTREAM_REPO" ] ||
    die "remote 'upstream' must be $UPSTREAM_REPO (found '${u:-none}').
  Fix with: git remote add upstream https://github.com/$UPSTREAM_REPO.git"
}

check_gh_auth() {
  gh auth status >/dev/null 2>&1 || die "gh is not logged in. Run: gh auth login"
}

# Fails loudly when GitHub Actions has never been enabled on the fork (a fresh
# fork lists zero workflows until a human clicks "enable" on the Actions tab).
check_actions_enabled() {
  local n
  n="$(gh api "repos/$FORK_REPO/actions/workflows" --jq '.total_count' 2>/dev/null || printf '0')"
  if [ "${n:-0}" = "0" ]; then
    die "GitHub Actions is not enabled on $FORK_REPO (0 workflows registered).
  A human must open https://github.com/$FORK_REPO/actions and click
  \"I understand my workflows, go ahead and enable them\". Nothing builds until then."
  fi
}

# Number of open upstream PRs whose head is <fork-owner>:<branch>.
open_upstream_prs_for() {
  gh pr list -R "$UPSTREAM_REPO" --state open --head "${FORK_REPO%%/*}:$1" \
    --json number --jq 'length' 2>/dev/null || printf '0'
}

check_clean_tree() {
  if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
    printf '\n%s\n' "$(git -C "$REPO_ROOT" status --short)" >&2
    die "the working tree has uncommitted changes (listed above). Commit or stash them first."
  fi
}

# --- temporary worktree ------------------------------------------------------
TMP_WORKTREE=""
cleanup_tmp_worktree() {
  if [ -n "$TMP_WORKTREE" ] && [ -d "$TMP_WORKTREE" ]; then
    git -C "$REPO_ROOT" worktree remove --force "$TMP_WORKTREE" >/dev/null 2>&1 || {
      rm -rf "$TMP_WORKTREE"
      git -C "$REPO_ROOT" worktree prune >/dev/null 2>&1 || true
    }
    rm -rf "$(dirname "$TMP_WORKTREE")" 2>/dev/null || true
    TMP_WORKTREE=""
  fi
}

# make_tmp_worktree <ref>: detached worktree at <ref>, path in $TMP_WORKTREE.
make_tmp_worktree() {
  local parent
  parent="$(mktemp -d "${TMPDIR:-/tmp}/mixxx-fork-XXXXXX")"
  TMP_WORKTREE="$parent/wt"
  git -C "$REPO_ROOT" worktree add --detach "$TMP_WORKTREE" "$1" >/dev/null ||
    die "could not create a temporary worktree at '$1'."
  trap cleanup_tmp_worktree EXIT
}
