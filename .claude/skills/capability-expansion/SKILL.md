---
name: capability-expansion
description: How the team grows a missing specialty on demand. Use whenever a task needs expertise that no current skill/agent covers — e.g. building an Android app, iOS/Swift, Flutter, Unity/game dev, Windows/desktop app, embedded, data/ML, blockchain. The tech-lead researches the domain, drafts a new skill + a specialist agent, presents them for the user's approval (gated), then on approval adds them to the team AND to the tech-lead and drives the task forward with the new capability.
---

# Capability Expansion (the team grows a missing specialty)

The team is not fixed. When a request needs a skill the team doesn't have, the lead **acquires** that capability rather than improvising: research it, capture it as a real skill, add a specialist for it, and only then build. This keeps quality high for domains outside the current roster (Android, iOS, Flutter, Unity, Windows/desktop, embedded, ML, …).

## When it triggers (capability gap)
At **tech-lead review** (workflow step 1), the lead checks the task's domain against the existing skills (`.claude/skills/`) and agents (`.claude/agents/`). It's a gap when **no current skill/agent covers the core technology** the task needs — e.g. a task says "build an Android app" but there's no mobile/Android skill or specialist. Don't force such work onto an ill-fitting agent; expand instead.

## The flow (detect → research → draft → GATE → install → proceed)
1. **Detect & name the gap** — state plainly what capability is missing (e.g. "native Android (Kotlin/Jetpack Compose)").
2. **Research the domain** — use the `tech-research` skill: web-search the **current** best-fit stack, tooling, project structure, testing, and security for that domain (use the current year; verify against primary sources). Threat-model per the `security` skill.
3. **Draft the new skill** — following the **`skill-authoring`** standard (anatomy, three-level progressive disclosure, description-as-router, the five rules, eval coverage, tier ladder), write a `.claude/skills/<domain>/SKILL.md` capturing the domain's standards (structure, conventions, build/release, testing, security, gotchas). Write three triggers (2 positive, 1 negative) **before** the body; push detail into `references/`. The drafted skill is reviewed against the canonical references in `docs/references/agent-engineering/`.
4. **Draft the specialist agent** — write a `.claude/agents/<role>.md` (e.g. `android-engineer`) in the same shape as the existing agents: frontmatter (`name`, `description` with a when-NOT/boundary clause, `tools`) + a role body that **leans on** the new skill and the shared skills rather than duplicating them. Keep `tools` minimal and appropriate (mirror `frontend`/`backend`). See `skill-authoring` › "Authoring specialist agents".
5. **GATE — present for approval first.** Do **not** add anything to the team yet. Show the user: the gap, the research summary (chosen stack + why), and the **drafts** of the new skill and specialist. This mirrors the task **registration gate** — produce → user review → (explicit approval) → install. Nothing joins the team without the user's OK.
6. **Install on approval** — write the skill + agent files, **add the new skill to the tech-lead's repertoire** (the lead gains the capability too), and register the specialist in the roster: update `CLAUDE.team.md` "The team" list and the `Conventions` skills list so the new member and skill are first-class.
7. **Proceed** — now run the task/scenario through the normal workflow with the new specialist + skill (design doc → tasks → implement → QA → Done).

## What gets created
- A **skill**: `.claude/skills/<domain>/SKILL.md` — the durable, reusable standard for that domain.
- A **specialist agent**: `.claude/agents/<role>.md` — the team member who owns that work.
- **Lead + roster updates**: the tech-lead can now direct this domain; `CLAUDE.team.md` reflects the new member and skill.

## Source repo vs. consuming project
- **In the `claude-team` source repo**: the new skill/agent become **canonical** — bump `VERSION`; every consuming project picks them up on its next `install.sh`. Prefer this when the capability is broadly useful.
- **In a consuming project**: the new skill dir + agent file are **not** in the installer manifest, so they **survive updates** (locally added). They stay project-local until promoted into the source repo. If the capability is generally useful, also add it upstream so the whole org benefits.

## Quality bar
- The new skill must meet the team's bar: standard, extensible, security-aware, long-term — not a thin stub. Research first; don't write from stale memory.
- It must pass the `skill-authoring` **eval coverage** check (trigger / execution / regression / token-budget) and clear the **smell list** before it ships. Anything an agent drafts enters at the **draft tier** until reviewed — never straight to action-allowed.
- Reuse the shared skills (`engineering-principles`, `security`, `testing-strategy`, `git-workflow`, `app-deploy`, etc.) from the new specialist rather than duplicating them.
- Keep one specialty per skill/agent; if a task spans two new domains, expand each.
- Record the decision as an ADR (`docs/adr/`) — what was missing, what stack was chosen, and why. See the `tech-research` and `documentation` skills.
