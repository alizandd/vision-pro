---
name: documentation
description: The team's standard for storing project documentation in the repo — Architecture Decision Records (ADR), task docs, and the bug log. Always use this skill whenever a significant decision is made, a task is created or its status changes, or a bug is filed or resolved, so the right document gets written under docs/. Defines where each doc goes, the templates, and numbering.
---

# Documentation Standard

The repo keeps a durable, English record of decisions, tasks, and bugs under `docs/`.
This is the team's long-term memory — Claude sessions start fresh, so anything that should
persist must live here (or in CLAUDE.md / agents / skills).

## Where things go
- `docs/adr/` — **Architecture Decision Records**. One file per significant decision.
- `docs/tasks/` — **Task docs**, an English mirror of the board (Jira/Trello stays the source of truth for live status).
- `docs/bugs/` — **Bug log**, structured reports filed by the tester.

Each folder has a `README.md` (index + rules) and a `0000-template.md`. Copy the template,
number sequentially (`0001-...`, `0002-...`), and keep the README index updated.

## When to write
- **ADR + design doc (before coding)** — for any non-trivial work, write the design up front: an ADR for the
  decision plus a short design note on the task (structure, interfaces, extensibility, risks). Implementation
  starts only after this exists. See the `engineering-principles` skill.
- **ADR** — whenever an architectural/technical decision is made (stack choice, security-driven
  version pick, data model, deployment approach). Record context, options, decision, consequences.
  Never delete an ADR; supersede it and update its status.
- **Task doc** — when the task-manager creates a task, mirror it here; update status as it moves
  through the lifecycle (see the `task-workflow` skill).
- **Bug** — when the tester fails QA, file a bug here and route it; update to Verified/Closed only
  after re-verification.

## Rules
- Everything in **English**, even if the discussion was in another language.
- Keep docs concise and current — stale docs are worse than none.
- Cross-link: tasks ↔ bugs ↔ ADRs by their IDs (TASK-XXXX, BUG-XXXX, ADR-XXXX).
- The tech-lead is responsible for ensuring the right doc exists before work is considered Done.
