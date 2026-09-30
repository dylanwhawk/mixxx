---
name: fork-dev
description: Rules and scripts for doing development on dylanwhawk's Mixxx fork — feature branches, the single `staging` branch that the other Mac installs as "Mixxx Staging", fast-forward promotion to `main` ("Mixxx Fork"), GitHub Actions DMG builds, and the upstream-PR constraints. Use whenever a task involves branches, pushing, testing a change on the Mac, promoting, syncing upstream, or opening a PR.
---

# Fork development workflow

<!-- AI-generated text: this skill was written autonomously by an AI agent (Claude) at the operator's request. -->

This checkout is the fork `dylanwhawk/mixxx` (remote `origin`); `upstream` is
`mixxxdj/mixxx`. Nothing is built or run locally for testing. Instead, every push to
`main` or `staging` runs GitHub Actions on the fork, and a launcher on the operator's
other Mac installs the newest unexpired `mixxx-*-arm64.dmg` artifact:

| Branch    | Installed as    | Purpose                                  | Workflow      |
| --------- | --------------- | ---------------------------------------- | ------------- |
| `main`    | Mixxx Fork      | stable; the operator's real library      | `release.yml` |
| `staging` | Mixxx Staging   | test builds; separate settings/library   | `develop.yml` |

Both workflows call `build.yml`; its **"macOS 15 arm64"** job uploads the DMG with
`actions/upload-artifact` (`archive: "false"`). That job and its upload step are the
whole delivery pipeline — treat them as protected (see rule 5).

## Rules (non-negotiable)

1. **Feature work happens on feature branches.** Never commit directly on `main` or
   `staging`. Branch names: `feat/<topic>`, `fix/<topic>`, or similar.
   - Fork-only work (won't go upstream): branch from `main`.
   - Work meant for an upstream PR: branch from `upstream/main`
     (`git fetch upstream && git switch -c feat/x upstream/main`) so the PR diff
     never contains fork-only files (`CLAUDE.md`, `.claude/`, `tools/fork/`).
2. **One staging branch: `staging`.** It is the only branch the Mac tests, and the only
   branch that ever reaches `main`. Test a change by putting it on `staging` with
   `tools/fork/stage.sh <branch>` (merge) or `--replace` (make staging exactly that
   branch). Both keep `staging` a superset of `main`.
3. **`main` moves only by fast-forward to a tested `staging` commit**, via
   `tools/fork/promote.sh`. Never force-push `main`, never merge anything else into it.
   Exception: `tools/fork/sync-upstream.sh` merges `upstream/main` into `main`.
4. **The operator has the final say on every promotion.** Agents verify the staging
   build is green (`build-status.sh`), then *ask*. Only after the operator says they
   tested "Mixxx Staging" and approves that exact commit may an agent run
   `promote.sh --yes`. Never promote on your own initiative.
5. **Never rename, remove, or restructure the "macOS 15 arm64" job or its "Upload GitHub
   Actions artifacts" step** in `.github/workflows/build.yml`, and never stop
   `release.yml`/`develop.yml` from calling `build.yml`. `check-build-job.sh` gates
   every stage/promote on this. Prefer not to edit `.github/workflows/` at all.
6. **Never open an upstream (`mixxxdj/mixxx`) PR from `staging` or `main`.** `develop.yml`
   skips fork builds of any branch that has an open upstream PR, so staging would stop
   building. PRs from feature branches are fine — and while such a PR is open the
   feature branch itself gets no fork build on push, which is why testing goes through
   `staging`.
7. **Git actions on the fork are authorized; upstream actions are not.** The operator
   has authorized agents to push `staging`, push `main` via `promote.sh`/
   `sync-upstream.sh`, and commit on feature branches. Upstream PRs, PR comments, and
   issues remain human actions per `AGENTS.md`. AI-written commit bodies, PR text, and
   docs carry the disclaimer `AGENTS.md` requires.

## Scripts (run from the repository root; all are safe to re-run)

```bash
tools/fork/stage.sh <branch> [--replace]   # put a branch on staging -> "Mixxx Staging"
tools/fork/build-status.sh [main|staging] [--commit <sha>] [--wait] [--quiet]
tools/fork/promote.sh [--yes]              # ff main to the tested staging commit
tools/fork/sync-upstream.sh [--no-stage]   # merge upstream/main into main, refresh staging
tools/fork/check-build-job.sh [<ref>]      # verify the arm64 DMG job is intact
```

`stage.sh` and `sync-upstream.sh` work in a temporary worktree and never touch your
checkout. `build-status.sh` exits 0 (arm64 job green + DMG listed), 1 (failed or
skipped), 2 (still running); `--wait` polls every two minutes.

## Typical cycle

```bash
git fetch origin upstream
git switch -c feat/thing origin/main        # or upstream/main for an upstream PR
# ... edit, commit (normal git; run pre-commit if installed) ...
tools/fork/stage.sh feat/thing              # pushes staging; develop.yml builds it
tools/fork/build-status.sh staging --wait   # ~50-90 min
# -> report to the operator: commit sha, run URL, what to test in "Mixxx Staging"
# -> operator tests on the Mac and approves
tools/fork/promote.sh --yes                 # only after that explicit approval
tools/fork/build-status.sh main --wait      # release.yml build for "Mixxx Fork"
```

## Build facts

- A build takes about 50–90 minutes after the push. The Mac installs on the *next
  launch* of the corresponding app; nothing is pushed to it.
- If the arm64 job fails, the Mac keeps the previous build. Fix on the feature branch
  and stage again.
- On the fork, jobs that need upstream secrets — changelog, publish, flatpak/appimage
  publishing, macOS signing/notarization, deploy manifests — fail or are skipped.
  That is expected. Only the "macOS 15 arm64" job (shown as `build / macOS 15 arm64`)
  matters. Other matrix legs failing is worth a look but does not block.
- Artifacts expire; "newest unexpired" is what the launcher picks. If nothing is
  installable, push (or `gh workflow run release.yml -R dylanwhawk/mixxx --ref main`)
  to build again.
- A fresh fork does not run workflows on push until a human clicks "I understand my
  workflows, go ahead and enable them" on https://github.com/dylanwhawk/mixxx/actions.
  Symptoms: `gh workflow list` is empty until the first push registers the files, and
  even after that only `gh workflow run <release|develop>.yml --ref <branch>` starts
  runs while pushes start none. If `build-status.sh` finds no run after a push, check
  that page first, then dispatch by hand. The scripts abort while zero workflows exist.

## Handling conflicts

`stage.sh` aborts and leaves `staging` untouched if a merge conflicts. Rebase the
feature branch onto `origin/main` (or merge `origin/staging` into it), resolve there,
and stage again — or stage with `--replace` once the branch contains `main`. If
`staging` has accumulated junk, `stage.sh <clean-branch> --replace` resets it.

<!-- AI-generated text ends. -->
