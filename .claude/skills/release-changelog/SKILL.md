---
name: release-changelog
description: The team's standard for releases, versioning, changelogs, and release notes — semantic versioning, what goes in a changelog, and how releases are cut and tagged. Always use this skill whenever cutting a release, writing a changelog or release notes, or deciding a version bump. Owned by devops; aligns with git-workflow and cicd-pipeline.
---

# Releases, Changelog & Release Notes

Consistent, traceable releases so anyone can see what changed, when, and why.

## Semantic Versioning (SemVer)
`MAJOR.MINOR.PATCH`:
- **MAJOR** — breaking changes (incompatible API/behavior).
- **MINOR** — new backward-compatible features.
- **PATCH** — backward-compatible bug fixes.
Pre-release/build metadata as needed (`-rc.1`, `+build`).

## CHANGELOG (Keep a Changelog format)
- Maintain a `CHANGELOG.md` at the repo root.
- An **Unreleased** section accumulates entries as work merges; it's promoted to a version on release.
- Group entries under: **Added**, **Changed**, **Deprecated**, **Removed**, **Fixed**, **Security**.
- Each entry: one clear line in English, user-facing language, referencing the task/PR (`TASK-XXXX` / `#PR`).
- Derive entries from Conventional Commits where possible (see `git-workflow`): `feat` → Added, `fix` → Fixed, etc.

## Release notes (human-facing)
- A short summary of the release's theme + highlights, then the grouped changelog.
- Call out **breaking changes** and required migration steps prominently.
- Note any security fixes (without leaking exploit detail).

## Cutting a release
1. Ensure `develop`/`main` is green in CI and QA-verified.
2. Promote **Unreleased** → the new version in `CHANGELOG.md` with the date.
3. Bump the version (package manifest, etc.).
4. Tag on `main` with `vX.Y.Z` (see `git-workflow`), matching the deployable image tag (see `app-deploy`).
5. Deploy per `cicd-pipeline`; verify post-deploy; keep the tag for rollback.

## Principles
- Every release is tagged and traceable to its changelog and tasks.
- Breaking changes are never silent — they bump MAJOR and are documented with migration notes.
- Changelog is written for humans, in English, kept current as work merges (not reconstructed at the end).
