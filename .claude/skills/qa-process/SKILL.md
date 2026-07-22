---
name: qa-process
description: The team's manual/exploratory QA process — turning acceptance criteria into a test plan, exploratory testing, cross-cutting checks (security/a11y/performance/responsiveness), bug triage & severity, regression, and the verification gate to Done. Always use this skill when verifying a task, planning manual test coverage, deciding bug severity, doing exploratory/acceptance testing, or judging whether work is truly done. Owned by the tester; complements `testing-strategy` (automated) and `debugging`, and follows `task-workflow`.
---

# QA process (manual, exploratory & acceptance)

Goal: verify that work genuinely meets its acceptance criteria and is safe to ship — automated tests are the baseline (`testing-strategy`); this skill is the human verification on top. Owned by the **tester**. Nothing is "done" until it passes here. Verify on the deployed **develop environment**, not a local one-off (`git-workflow`).

## From acceptance criteria → test plan
- Start from the task's **acceptance criteria**; if they're missing or ambiguous, ask the task-manager to clarify — don't guess.
- Derive test cases covering: the **happy path**, **boundary/edge cases**, **error/invalid input**, and **state** (empty/loading/error/offline). Note expected result per case, tied back to a criterion.

## Exploratory testing
- Beyond scripted cases, run time-boxed **exploratory charters** ("explore X to discover Y"): try to break it — unexpected order, double-submit, back button, stale data, concurrency, large/odd input, interrupted flows.
- Record what you did so anything found is **reproducible**.

## Cross-cutting checks (every feature, where relevant)
- **Security** (`security`): authorization boundaries (access another user's resource), invalid/expired tokens, rate limiting, no user enumeration, input validation/fuzzing on key fields, no secrets/PII in responses or logs.
- **Accessibility**: keyboard-only operation, focus, labels, contrast, screen-reader sanity on key flows.
- **Performance**: responsiveness under realistic data; no obvious slow paths/leaks; for 3D/canvas, that it runs and degrades gracefully.
- **Responsiveness/compat**: key breakpoints and target browsers/runtimes.
- **Contract** (backend): response shape matches `api-conventions`; validation and failure modes behave.

## Bug triage & severity
- File a structured, reproducible bug report (Title, Severity, Area/Assignee, Related task, Environment, Steps, Expected, Actual, Notes) — always in **English**, routed to the responsible area via the tech-lead.
- **Severity**: *Blocker* (can't proceed / data loss / security hole) · *Critical* (core flow broken, no workaround) · *Major* (important issue, workaround exists) · *Minor* (small/cosmetic with impact) · *Trivial* (polish). Severity reflects user/business impact, not effort to fix.
- When diagnosing, apply `debugging` (reproduce → hypotheses → isolate → root cause → verify) so the report points at the real cause, not the symptom.

## Regression & the gate to Done
- After a fix, **re-test the original issue and do a focused regression** around the change — fixes commonly break neighbors.
- **Pass** → mark verified, summarize what was checked, move to Done (`task-workflow`). **Fail** → back into the cycle with the bug report. Loop until it genuinely passes; never close prematurely.

## Principles
- Reproducible or it isn't a bug report. Tie every pass/fail to an acceptance criterion. Protect quality without blocking the team — be precise, constructive, and fast.

## Output
A concise verification summary (criteria checked + result) on pass, or structured bug report(s) routed to the right area on fail, plus the regression check after re-test.
