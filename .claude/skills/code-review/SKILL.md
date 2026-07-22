---
name: code-review
description: The team's code review standard — a concrete checklist of what to look for (correctness, extensibility, security, tests, consistency) and how to give review feedback. Always use this skill whenever reviewing code, a pull request, or a specialist's output before it moves toward Done. Used by the tech-lead and any reviewer.
---

# Code Review Standard

Review is a quality gate, not a formality. The goal: protect the long-term health of the codebase while keeping the team moving.

## Before you review — review *current* code on the *right* branch
Never review stale code. First make the working copy current:
- `git fetch` and bring **`develop`** up to date (`git checkout develop && git pull`).
- **Check out the branch the work lives on** — for a task, that's its `feature/<feature-slug>` (per `git-workflow`); pull it (`git checkout feature/<slug> && git pull`) and confirm the change you're reviewing is actually present on it. If the branch is behind `develop`, bring `develop` in so you're judging it against current integration.
- If the named branch is missing or doesn't contain the work, stop and report that — there's nothing valid to review.

## Review checklist
**Correctness**
- Does it do what the task/acceptance criteria require? Edge cases and error paths handled?
- Any obvious logic bugs, off-by-one, null/undefined, race conditions?

**Long-term / extensibility** (see `engineering-principles`)
- Standard, conventional structure; clear separation of concerns.
- Does it fit existing patterns, or introduce a divergent one without justification?
- Will this be easy to extend/maintain, or is it a quick fix? Tech debt recorded if intentional.

**Security** (see `security`)
- Input validated server-side; output escaped; parameterized queries.
- AuthZ enforced; secrets not hardcoded; no sensitive data in logs.

**Tests** (see `testing-strategy`)
- New logic covered by tests; tests meaningful (not just for coverage numbers).
- Tests pass in CI.

**Consistency & clarity**
- Matches the design doc / ADR; deviations explained.
- Naming clear; **English-only comments/identifiers**; no dead code or debug leftovers.
- Docs updated (API contract, README, ADR) where relevant.

**Scope**
- PR is focused and reasonably small (ties to ≤8h tasks). Unrelated changes split out.

## Reviewing AI-generated code (extra scrutiny)
AI-generated code needs the same or *more* review than human-written code — it compiles and reads fluently while being subtly wrong. See `docs/references/agent-engineering/` (Day 4 & Day 5).
- **Verify dependencies are real.** Check that imported packages actually exist and are the intended ones — LLMs hallucinate plausible package names that attackers squat ("slopsquatting").
- **Review the logic, not just the syntax.** Translate non-obvious generated code back into plain language and confirm it matches intent; don't approve because tests are green (tests can be mocked/deleted to fake green).
- **Watch the AI failure modes:** wrong business-logic assumptions, missing edge/error handling, secrets or auth pushed to the client, and architecturally divergent patterns that "look right."
- **Judge the rendered artifact** for UI work, not just the diff.
- **Keep batches small** so review stays possible at agent output volume; an AI-generated PR summary / risk note (what changed, what might break) helps reviewers focus on architecture over line-noise.

## Giving feedback
- Be specific and constructive — point to the line and suggest a fix, not just "this is wrong."
- Distinguish **blocking** issues (must fix) from **nits** (optional/preference); label them.
- Prefer questions over commands when intent is unclear ("could this overflow if X?").
- Respect the author; review the code, not the person.

## Outcome
- **Approve** when blocking issues are resolved and the checklist passes.
- **Request changes** with a clear, actionable list.
- Re-review after changes; only then does it proceed toward QA/Done.
