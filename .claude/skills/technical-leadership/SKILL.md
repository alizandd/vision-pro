---
name: technical-leadership
description: The tech-lead's end-to-end project delivery method — the correct path a piece of work travels from intake to production. Covers request triage, mode selection, doc-first design, decomposition & delegation, cross-team consultation, review, QA routing, promotion, and keeping docs/board in sync. Always use this skill when leading a project, breaking work down, coordinating specialists, deciding the order of work, or driving something from request to Done. Pairs with `code-review`, `task-workflow`, `engineering-principles`, and `tech-research`.
---

# Technical leadership — the correct project path

Goal: every request travels a predictable, high-quality path from intake to production — designed before built, delegated to the right hands, reviewed, QA'd, and promoted, with docs always current. Owned by the **tech-lead**. This is the *method*; the *review bar* is `code-review`, the *status rules* are `task-workflow`.

## The path (intake → production)
1. **Pre-engagement gates** (every request, before analysis):
   - **Currency** (`team-update`): if the update marker is > 7 days old, refresh the team first, then continue.
   - **Capability** (`capability-expansion`): if the work needs a specialty no skill/agent covers, research → draft skill+specialist → **gate on user approval** → install → proceed.
2. **Triage & pick the mode** (`task-workflow`): classify the request and choose Mode 1–7 up front — it decides how much you delegate vs. do yourself. State the mode.
3. **Design-first (doc before code)**: do the architecture/design review. **Research the current best-fit approach** (`tech-research`) — don't default to the familiar. Decide structure for the **long term and extensibility**; threat-model (`security`). Capture an **ADR** (`docs/adr/`) + a task design note. No implementation starts until the design doc exists.
4. **Decompose**: break the work into components with ordering, dependencies, area ownership, priorities, and risks. Enforce the **≤ 8h task cap** — split anything larger. Only areas with real work get tasks (no filler designer/devops tickets).
5. **Delegate** (Task tool, parallel where independent): route each part to the right specialist. **Label every dispatched agent with its team/specialist name** (e.g. `backend: payment API`, `frontend: checkout UI`) — when several run in parallel the names are the only way to tell at a glance which stream is which and who owns it, so don't dispatch an unlabeled agent. Hand the decomposition to the **task-manager** to write English tickets; sign off before they hit the board (registration is **gated** on user approval — see `taskmanager-api`).
6. **Facilitate consultation**: reconcile cross-team decisions explicitly — the API contract (backend↔frontend via `api-conventions`), a security-driven version choice (devops), a missing design (engage **designer** only when no design exists).
7. **Review & integrate** (`code-review`): review on the right, current branch; check correctness, extensibility, security, tests, and fidelity to the design doc. Request changes or approve. The final call is yours.
8. **Route to QA** (`task-workflow`): the **tester** verifies against acceptance criteria on the develop environment. Fail → bug routed back to the responsible area → fix → re-verify. Loop until it genuinely passes.
9. **Promote to production** (`git-workflow`): only after QA passes on develop, merge `develop` → `main`, then run a **production smoke test**. Never promote unverified work.
10. **Keep everything current**: ADR/design note/task/bug log and the board reflect reality as work moves. A short "why this approach" closes the loop.

## Delegation judgment
- Match the task to the specialist's domain; don't force ill-fitting work onto the wrong agent (expand instead). Subagents don't talk to each other — **all coordination flows through you**.
- Parallelize independent work; serialize on real dependencies (e.g. contract before frontend build). Give each delegate the design doc + acceptance criteria, not vague asks.
- For urgent/small/well-understood work, use **Mode 4** (implement it yourself) but keep the quality/security bar and a light QA check.

## Leadership principles
- **Direction over doing**: your value is judgment, architecture, and integration — go deep only where it unblocks.
- **Decisions are documented**: significant choices become ADRs with the reasoning, so the 30+ person team can build on them coherently.
- **No language/stack lock-in**: choose by fit and justify it. **Current over familiar** (`tech-research`).
- **Standard & maintainable**: conventional, extensible paths; hacks only with a recorded tech-debt note.
- **Protect the cycle**: nothing is "done" until reviewed *and* QA-passed; nothing hits prod unverified.

## Output
Lead with a brief architectural decision summary and the chosen mode, then the decomposition + delegation plan, then (after the cycle) the integrated, QA-passed result with a "why this approach" rationale and links to the ADR/tasks.
