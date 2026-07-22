---
name: env-onboarding
description: The team's standard for local environment setup and onboarding a new developer — prerequisites, env config, getting the project running, and a SETUP/onboarding doc. Always use this skill whenever setting up a project locally, onboarding a new team member, diagnosing "works on my machine" issues, or writing setup documentation.
---

# Environment Setup & Onboarding

Goal: a new developer (in a 30+ person team) can clone the repo and be running locally fast, the same way every time.

## SETUP.md (every project has one)
Write/maintain a `SETUP.md` covering:
- **Prerequisites**: required tools and versions (Docker, Node, PHP/Composer, Python, etc.).
- **Clone & install**: exact commands to install dependencies.
- **Environment config**: copy `.env.example` → `.env`; explain each required variable (no secrets committed; provide a documented `.env.example`).
- **Run locally**: how to start the stack (usually `docker compose up`), seed the DB, and the URLs/ports.
- **Common tasks**: run tests, run migrations, lint, build.
- **Troubleshooting**: known gotchas and fixes.

## Reproducible environments
- Prefer containerized local dev (Docker) so environments match across the team and reduce "works on my machine" (aligns with `app-deploy`).
- Pin tool/dependency versions; commit lockfiles.
- Keep `.env.example` in sync with the real required variables — adding a new env var means updating it and SETUP.md.

## Onboarding checklist (new dev)
- [ ] Access: repo, registry, relevant services/secrets (via the right owner — never shared in plaintext).
- [ ] Local env running per `SETUP.md`; tests pass locally.
- [ ] Read `CLAUDE.md`, this skill set, and the team workflow.
- [ ] Make a tiny first PR (e.g. a doc fix) to exercise the full flow (branch → PR → CI → review → merge).
- [ ] Knows where docs live: `docs/adr`, `docs/tasks`, `docs/bugs`, `CHANGELOG.md`.

## Diagnosing env issues
- Compare against `SETUP.md` prerequisites and versions first.
- Check env vars and `.env` completeness; check container/service health and logs.
- Watch for environment/config drift and network constraints (mirrors/registries) — coordinate with devops.

## Principles
- Setup is documented and reproducible, not tribal knowledge.
- If onboarding hits friction, fix the docs/scripts so the next person doesn't.
