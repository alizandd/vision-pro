---
name: testing-strategy
description: The team's standard for how to test — test types (unit/integration/e2e), what to cover, coverage expectations, test data, and how automated tests fit the QA cycle. Always use this skill whenever writing tests, deciding what to test, or planning the verification of a feature. Complements the tester agent (manual/exploratory QA) with automated testing discipline.
---

# Testing Strategy

Automated tests are how we keep the long-term codebase safe to change. They complement the tester's manual/exploratory QA — they don't replace it.

## Test pyramid (favor the base)
- **Unit tests** (most): pure functions, business logic, components in isolation. Fast, no external deps.
- **Integration tests** (some): modules working together — API + DB, service boundaries, auth flows.
- **End-to-end / functional** (few): critical user journeys through the running app (e.g. login → reset → login).

## What to cover
- Happy path **and** edge cases, error paths, and boundary conditions.
- Security-relevant behavior (authz, invalid/expired tokens, validation) — see `security`.
- Regression: when a bug is fixed, add a test that fails on the old behavior so it can't return.

## Quality of tests
- Test behavior, not implementation details (resilient to refactors).
- One clear reason to fail per test; descriptive names.
- Deterministic — no flaky time/order/network dependencies; mock external services.
- Arrange–Act–Assert structure.

## Test data & environment
- Use factories/fixtures/seeders for data; never depend on production data.
- Separate test DB/environment; reset state between tests.
- Keep secrets out of tests; use test config.

## Coverage
- Aim for meaningful coverage of logic-heavy code; treat coverage as a signal, not a target to game.
- Critical paths (auth, payments, data integrity) should be well covered.

## Per stack (examples)
- PHP/Laravel: PHPUnit/Pest, feature tests hitting routes, factories.
- Node: Jest/Vitest, supertest for APIs.
- Python: pytest, fixtures.
- Frontend: component tests (Testing Library), e2e with Playwright/Cypress.
- 3D/Three.js: test logic/state and asset-loading paths; visual/perf checks are exploratory.

## Evaluating non-deterministic / AI output (when a feature uses an LLM/agent)
Deterministic tests check computed output ("did the function return X?"). They're necessary but **insufficient** for output that is *generated* — an agent or LLM-backed component can pass every unit test on its tools and still choose the wrong tool, paraphrase a critical answer, or hallucinate. For those features, add **evaluation** alongside tests. See `docs/references/agent-engineering/` (Day 4).
- **Tests vs. evals.** Tests catch deterministic regressions (binary pass/fail). Evals catch behavioural drift — scored judgments (e.g. an LLM-as-judge 0–5 against a rubric) and tolerance bands, not assertions.
- **Score the output AND the trajectory.** Check the final artifact *and* the path taken (tool calls, sequence). A right answer reached by a wrong/dangerous sequence is a fragile success — strict for action-allowed flows, looser for read-only.
- **Define the rubric first** (eval-driven): write the acceptance criteria / expected tool-calls before building, the same way you'd write a failing test first.
- **For rendered UI, judge the rendered artifact, not the code** — pair Playwright/E2E assertions (interactivity) with a check of how the page actually looks/behaves.
- **Calibrate judges against humans** and sample real sessions; treat user corrections ("no, not like that") as labelled failure data.

## In the cycle
- Tests run in CI on every PR (see `cicd-pipeline`); a PR shouldn't merge with failing tests.
- The tester relies on automated tests as a baseline, then does exploratory + acceptance verification on top.
