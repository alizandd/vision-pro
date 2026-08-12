---
name: skill-authoring
description: The team's standard for authoring and revising the team's OWN skills and specialist agents — skill anatomy, three-level progressive disclosure, the description-as-router, naming, the five rules, eval coverage (trigger/execution/regression/token-budget), and the read/draft/act tier ladder. Always use this skill whenever creating a new skill or agent, editing an existing SKILL.md or agent file, splitting a long skill into references/, or judging whether a skill is good enough to ship. Required by `capability-expansion`. Do NOT use for writing project/product feature code, BDD specs, or end-user docs (that's `engineering-principles` / `documentation`).
---

# Skill Authoring (how the team writes its own skills & agents)

This is the durable standard for the **meta-work**: writing and improving the skills and
specialist agents that *are* the team. It distills the canonical references in
[`docs/references/agent-engineering/`](../../../docs/references/agent-engineering/README.md)
— primarily **Day 3 (Agent Skills)**, with security/eval from **Day 4**. When this skill
and a reference disagree, the reference wins; update this skill to match.

A skill without a test is a hope, not a capability. A skill body is a budget, not a vessel.

## Skill anatomy & progressive disclosure
A skill is a folder with a `SKILL.md` plus optional `references/`, `scripts/`, `assets/`.
It loads in **three levels** — keep each level lean so co-loaded skills don't cause context rot:

1. **Metadata** (`name` + `description`) — always in context. This is the routing layer. Keep it sharp.
2. **`SKILL.md` body** — loaded only when the skill triggers. Keep it the lean "runbook".
3. **Bundled resources** (`references/`, `scripts/`, `assets/`) — loaded strictly on demand.

**Rule of thumb:** if the `SKILL.md` body is getting long, the next section probably belongs
in `references/`, not in the body. Hard ceiling: a body over ~500 lines / 5,000 words is a
**smell** — split it. (See `app-deploy`, `cad-to-3d-building` for the split pattern in this repo.)

## The description is the router (spend the most effort here)
The `description` is the only thing the model sees to decide whether to load the skill. It must:
- **State what it does AND when to use it** — front-load trigger keywords ("Generate a commit message…", not "This skill helps with…").
- **Include when NOT to use** — name the adjacent skill that owns the excluded case, to prevent over-triggering and routing collisions.
- Describe **actual** behaviour, not aspirational. Be pushy if the model under-triggers.
- Stay within ~1024 chars; most aim for ~50 words of substance.

## The five rules
1. **One skill, one job.** If you need "and" between unrelated capabilities, it's two skills. Decompose first.
2. **Descriptions are an interface.** A vague description means an unused (or mis-fired) skill.
3. **Skills are dependencies.** Version, review, and test them like code. They propagate to every consuming project on `install.sh`.
4. **The right team owns the right skill.** Keep domain skills with the domain specialist; don't bottleneck everything through the lead.
5. **The runtime is interchangeable.** Don't hard-code to one model/tool; keep skills portable.

## Quality principles
- **Run the task first; give the reason, not just the rule.** Models generalize from *why* an instruction exists. If you're typing "ALWAYS"/"NEVER" in caps, explain the rationale instead — capitalized imperatives accumulate **context debt** and get ignored.
- **Every line earns its place.** Keep gotchas, exact commands, business logic, anti-patterns. Cut boilerplate the model already knows.
- **Make instructions verifiable.** If the agent can't tell whether it followed the rule, the rule is too vague.
- **Bundle what repeats.** Deterministic helper code goes in `scripts/`, not as prose instructions. Don't reinvent MCP as scripts.

## Interop standard (MCP) — currency note
Skills carry the *procedural knowledge*; **MCP** carries the *actions* a skill invokes. Keep that split — a skill that hand-rolls a transport is doing MCP's job badly.
- Current spec revision: **2026-07-28** — a **stateless protocol core** (scales on ordinary HTTP infrastructure), multi-round-trip requests, header-based routing, cacheable list results, **hardened authorization** aligned with OAuth/OIDC, and a formal **extensions** framework (MCP Apps for server-rendered UI, Tasks for long-running work).
- MCP is now stewarded by the **Linux Foundation's Agentic AI Foundation** (donated December 2025) — treat it as a vendor-neutral standard when choosing an integration path.
- Skills are themselves a supply-chain surface: a third-party skill is executable instructions. Adopt one the same way as a dependency — read it end to end, record provenance and license in `skills-lock.json`, and re-check on update (see `capability-expansion`).

## The tier ladder — graduate, don't assume (Day 4)
Authority is earned. Match the eval bar to what the skill is allowed to do:
- **Read-only** (fetch/describe, no state change) → trigger accuracy ~90%; lightest bar.
- **Draft-only** (produces content for human review) → representative cases + human approval. **Anything an agent drafts enters here, never straight to action.**
- **Action-allowed** (mutates real state / irreversible) → adversarial review, sustained success across runs (not one lucky pass), HITL gate for high-stakes actions. In this team that maps to the **task review/registration gate** and Mode-7 promotion gates.

## Eval coverage (a skill is "evaluated" only when all four hold)
See [`references/checklists.md`](references/checklists.md) for the full checklist + minimal-skill template. The four conditions:
- **Trigger** — positive (should fire) AND negative (should not fire) cases; aim ~90% accuracy.
- **Execution** — correct output across a representative input range.
- **Regression** — adding it causes zero drops in the existing skill library's routing.
- **Token budget** — co-loaded with 5–15 active skills it doesn't degrade unrelated turns.

Any failure holds the skill at the **draft tier**, regardless of happy-path performance.

## Workflow for adding/revising a skill or agent
1. **One job, named.** State the single capability in one sentence. If you can't, split.
2. **Write three triggers first** (2 positive, 1 negative) before drafting the body — this surfaces description ambiguity early (Eval-Driven Development).
3. **Draft the lean body**; push detail to `references/`, deterministic work to `scripts/`.
4. **Write the description last and hardest** — what + when + when-NOT + front-loaded keywords.
5. **Check the smells** (`references/checklists.md`) and the eval coverage; fix before shipping.
6. **Wire it in** — for a new domain skill, also add the specialist agent and update `CLAUDE.team.md` + the `Conventions` skills list (see `capability-expansion`), bump `VERSION`, and record an ADR.

## Authoring specialist **agents**
- Frontmatter: `name`, `description` (same router rules as a skill — include when-NOT and the boundary with adjacent agents), `tools` (minimal & appropriate; mirror `frontend`/`backend`).
- Body: a focused role that **leans on skills** rather than duplicating them. One specialty per agent.
- Subagents don't talk to each other — coordination flows through the tech-lead (see `technical-leadership`).

## Anti-patterns
- Vague descriptions ("helps with documents"); no when-NOT clause.
- A `SKILL.md` body over ~5,000 words, or one that references no other resource (it may just be a system-prompt line).
- Two specialists could plausibly own it (not yet decomposed).
- Hard-coded paths/secrets; "ALWAYS do X" walls; letting an agent self-promote a skill past the draft tier without the gate.
- Mass-generating skills. Build the library one real workflow at a time.
