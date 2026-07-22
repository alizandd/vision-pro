---
name: tech-research
description: How the tech-lead researches the current, best-fit technology and approach before committing to a direction — using web search to stay up to date — and transfers that knowledge to the team. Always use this skill when choosing a library/framework/tool, evaluating an approach, or when the best path may have changed since training data; the lead should verify against current sources rather than rely on memory.
---

# Technology Research (lead-driven)

The tech-lead is responsible for picking the **current best-fit** path — not the most familiar one, and not a stale default. Technology moves fast; what was best last year may be deprecated now. Verify against up-to-date sources, then transfer the decision to the team clearly.

## When to research
- Choosing a library, framework, tool, or pattern for new work.
- A dependency looks unmaintained, deprecated, or has a newer major version.
- The problem is unfamiliar, or the "obvious" answer may be outdated.
- Security/version concerns (coordinate with `security` and devops).
- Any time you're about to commit the team to a direction and aren't certain it's current.

## How to research
1. **Search the web** for the current state — latest stable versions, maintenance status, community adoption, known issues, and recent alternatives. Use the current year in queries; don't trust memory for anything version- or recency-sensitive.
2. **Compare options widely**: don't tunnel on one tool. Consider 2–3 real alternatives and the trade-offs (fit, maturity, maintenance, community, learning curve, license, performance, security, how it fits the existing stack).
3. **Think broadly about the scenario**: weigh long-term maintainability, the 30+ person team, existing infrastructure, network constraints, and where the project is heading — not just the immediate task.
4. **Verify, don't assume**: prefer primary sources (official docs, repos, release notes, changelogs) over blog summaries. Check the version is current and actively maintained.

## Transferring to the team
- Record the decision as an **ADR** (`docs/adr/`): the options considered, why this one, and the trade-offs — so the whole team shares the reasoning.
- Brief the relevant specialists on the chosen approach and any gotchas found in research.
- If a skill encodes the old approach, update it so the team's standards stay current.

## Principles
- **Current over familiar**: pick the best path for now, verified against today's sources.
- **Wide-angle view**: always consider broader scenarios and the long-term, not just the task in front of you.
- **Justify and document**: the team should be able to see *why* a technology was chosen, via the ADR.
- **Re-evaluate over time**: revisit choices as the landscape and dependencies change.
