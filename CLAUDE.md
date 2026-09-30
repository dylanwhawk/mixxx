# Mixxx (dylanwhawk fork)

@AGENTS.md

<!-- AI-generated text: this fork-specific section was written autonomously by an AI agent (Claude) at the operator's request. -->

## This checkout: dylanwhawk's fork

This is the fork `dylanwhawk/mixxx` (`origin`), tracking `mixxxdj/mixxx` (`upstream`).
Builds come from GitHub Actions on the fork; the operator's other Mac auto-installs the
newest `mixxx-*-arm64.dmg` artifact — `main` as "Mixxx Fork" (real library),
`staging` as "Mixxx Staging" (test builds). There is no local run-and-test loop.

Before any branch, push, promote, sync, or PR work, follow the `fork-dev` skill
(`.claude/skills/fork-dev/SKILL.md`). The short version:

- Feature work on feature branches (from `main`, or from `upstream/main` when the
  change is headed for an upstream PR).
- Test on the Mac by putting the change on `staging`: `tools/fork/stage.sh <branch>`.
- Promote by fast-forwarding `main` to the tested staging commit:
  `tools/fork/promote.sh` — only after the operator tested it and approved.
- Never open an upstream PR from `staging` or `main`; never rename/remove the
  "macOS 15 arm64" job or its artifact upload in `.github/workflows/build.yml`.
- Check builds with `tools/fork/build-status.sh [main|staging] --wait` (~50–90 min).
  Changelog/publish/signing job failures on the fork are expected.
- The `AGENTS.md` rule that commits and pushes are human actions applies to upstream.
  On this fork the operator has authorized agents to push `staging`, and `main` via
  `promote.sh`/`sync-upstream.sh`; upstream PRs, PR replies, and issues stay human.

<!-- AI-generated text ends. -->
