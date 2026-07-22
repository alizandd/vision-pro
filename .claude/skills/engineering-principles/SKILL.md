---
name: engineering-principles
description: The team's core engineering principles for writing maintainable, extensible, long-term code, and the doc-first workflow (design review before implementation, docs kept current through the cycle). Always use this skill whenever writing or reviewing non-trivial code, making structural/architectural choices, or deciding how a feature should be built — to ensure a long-term, standard, extensible approach rather than a quick fix.
---

# Engineering Principles

These apply to every specialist's work. The goal: code the 30+ person team can build on for the long run.

## Long-term view & extensibility
- **Build for the long run**: choose standard, conventional structure that is easy to extend and maintain. Avoid quick fixes and one-off shortcuts.
- **Architecture first**: clear separation of concerns, well-defined boundaries/modules, and dependency direction that supports growth. Prefer composition and clear interfaces over tight coupling.
- **Consistency**: follow established patterns and the team's skills (api-conventions, database-migrations, frontend-standards, etc.). New code should look like it belongs.
- **Scalability of structure**: organize code so new features slot in without rewrites — predictable folders, naming, and module boundaries.
- **Tech debt is explicit**: a temporary hack is allowed only when consciously chosen and **recorded** (ADR or task note) with a follow-up to address it.
- **Testability**: structure code so it can be tested in isolation; this is part of "extensible," not an afterthought.
- **English-only code**: all comments, identifiers, commit messages, and inline docs are in English — never Farsi or any other language. This keeps the codebase consistent and maintainable for the whole team.

## Doc-first workflow
1. **Design review up front**: before implementation, the tech-lead does an initial architecture/code-design review. Significant structural choices are decided here, not mid-coding.
2. **Write the design doc before coding**: capture the approach as an **ADR** (`docs/adr/`) for the decision plus a short design note on the task — structure, key interfaces, data shape, extensibility considerations, risks.
3. **Implement against the doc**: build to the documented design; if reality forces a change, update the doc rather than letting code and docs diverge.
4. **Keep docs current through the cycle**: as the work moves through review → QA → fixes → done, update the ADR/task/bug docs so documentation stays the single source of truth and the whole effort moves forward coherently.

## Working with AI agents (when the work is AI-assisted or builds an agent)
These extend the principles above when an agent is doing the implementation, or when the thing being built is itself an agent/LLM feature. See `docs/references/agent-engineering/` (Day 1 & Day 5).
- **Structure scales, vibes don't.** Casual "accept whatever the model returns" is fine for throwaway prototypes; production work needs specs, tests, and human review of architecture. Know where on that spectrum a task sits and say so.
- **Spec-first; treat code as regenerable.** For non-trivial AI-built work, the durable artifact is the spec/design (clear acceptance criteria, or a BDD-style description), not the first code. A good spec can be re-implemented; ambiguous intent produces confident-but-wrong code.
- **Context engineering is a real lever.** Give an agent a dense, high-signal payload (the design doc, conventions, the relevant files) rather than dumping everything — too much context degrades output and burns tokens. Decide deliberately what is always-loaded vs. fetched on demand.
- **The harness matters more than the model.** Reliability comes from the scaffolding around the model — instructions, tools, tests, guardrails, review — not from swapping models. When an agent gets something wrong, suspect a missing rule/tool/guardrail before blaming the model.
- **Generation is the easy part; verification is the craft.** AI removes the typing bottleneck and moves it to review/integration. Budget effort accordingly — review every line that ships, and be skeptical of code that "looks right."

## Why this matters
A single source of truth + an agreed structure means many people (and many sessions) can work on the codebase without it fragmenting. Documentation written up front and kept current is what makes the long-term view actually hold.
