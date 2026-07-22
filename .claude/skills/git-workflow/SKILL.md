---
name: git-workflow
description: The team's standard Git and pull-request workflow — branching model, commit message conventions, PR rules, and branch protection. Always use this skill whenever creating branches, writing commits, opening or reviewing pull requests, or deciding how changes get merged. Owned by devops; followed by everyone.
---

# Git & PR Workflow

A consistent version-control workflow so a 30+ person team can collaborate without chaos.

## Branching model
- Long-lived: `main` (production-ready) and `develop` (integration).
- Short-lived branches off `develop`:
  - `feature/<feature-slug>` (e.g. `feature/login`, `feature/checkout`)
  - `bugfix/<bug-id>-short-desc`
  - `hotfix/<id>-short-desc` (off `main` for urgent production fixes)
- **One feature = one branch, shared by all that feature's tasks.** Every task that belongs to the same feature is implemented on the **same** `feature/<feature-slug>` branch so the work stays unified and integrates cleanly. When the work moves to a **different** feature, it gets its **own** branch. (Example: all login-related tasks — page, validation, service call — go on `feature/login`; the checkout work starts a new `feature/checkout`.)
- Keep features small and short-lived; the ≤8h cap applies **per task**, and a feature branch holds a small set of related tasks, not an open-ended pile. Bugfix/hotfix branches stay one-per-fix.

## Commit messages (Conventional Commits)
- Format: `type(scope): summary` — e.g. `feat(auth): add password reset endpoint`.
- Types: `feat`, `fix`, `refactor`, `chore`, `docs`, `test`, `perf`, `build`, `ci`.
- Imperative mood, English only, concise summary; body explains *why* when needed.
- Reference the task/bug: include `TASK-XXXX` / `BUG-XXXX` in body or footer.

## Pull requests
- Open a PR from the feature branch into `develop` (or `main` for hotfix).
- PR must: link its task/bug, describe what & why, list how it was tested, and note any doc/ADR updates.
- Keep PRs small and focused — easier review, fewer regressions.
- Pass CI (lint, tests, build) before review (see `cicd-pipeline`).
- At least one reviewer approval; address all review comments (see `code-review`).
- Squash or rebase per project convention; no merge of unresolved conflicts.

## Environment promotion flow (how a feature reaches production)
Branches map to environments; **the develop server is separate from production** (see `cicd-pipeline`: `develop` → dev server, `main` → prod). A feature is promoted, never hot-edited on a long-lived branch:

1. **Branch**: pull latest `develop`, then for the **feature** use its `feature/<feature-slug>` branch — create it on the feature's first task and **reuse the same branch** for the feature's remaining tasks (don't cut a new branch per task).
2. **Work & push**: implement the task on the feature branch, push. CI runs on the PR.
3. **Merge to `develop`**: when the work is OK and the PR is approved, merge into `develop`. The merge **auto-deploys to the develop server**.
4. **QA on develop**: the **tester verifies the task on the develop environment** (a real deployed env, not a laptop) against its acceptance criteria. Fail → bug routed back, fix on a new branch, repeat. Pass → the task is QA-approved.
5. **Promote to `main`**: once QA passes, the **tech-lead merges `develop` → `main`**, which **deploys to production**.
6. **Production smoke test (lead)**: the **lead runs a smoke test on `main`/production** to confirm nothing broke in promotion. Only then is the work truly Done/released.

> So QA happens on **develop**, and the lead owns the **develop → main** promotion plus the final production check. Don't merge to `main` before the tester has passed it on develop.

> **Mode 7 (review sweep) is a deliberate exception to step order**: tasks audited from the board's Review column are verified on their `feature/<slug>` branch **brought current with `develop` first**, and merged into `develop` only on pass — so failed work never reaches develop. Give the post-merge develop deploy a quick check. See `task-workflow` › Mode 7.

## Branch protection (devops sets up)
- `main` and `develop` protected: no direct pushes, require PR + passing CI + review.
- Optional: require up-to-date branch, signed commits, CODEOWNERS for sensitive areas.
- **When protection blocks a direct push** (e.g. the Mode 7 pass → merge into `develop`), the merge goes through a **PR** on the same branch instead — open, let CI pass, merge. Never bypass or disable protection to complete a cycle step; if the PR path is blocked too (missing approvals), surface it to the user rather than stalling silently.

## Releases
- Tag releases on `main` with semantic versioning (`vMAJOR.MINOR.PATCH`).
- Keep tags so deploys/rollbacks reference a specific version (see `app-deploy`).

## Hygiene
- Delete merged branches. Don't commit secrets, build artifacts, or generated files (.gitignore).
- Rebase/update long-running branches regularly to avoid big conflicts.
