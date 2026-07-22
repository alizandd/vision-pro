---
name: team-update
description: The team's self-maintenance so its skills and specialists stay current. Use at the START of team engagement and whenever refreshing the team. A last-update marker is checked on use; if more than a week old, the tech-lead first runs a web-research refresh — what changed since the marker across the team's stacks (new releases, deprecations, CVEs, shifted best practices) — updates the affected skills/agents, records it, resets the marker, then continues the task. Owned by the tech-lead; pairs with tech-research, security, and capability-expansion.
---

# Team Update (weekly, checked on use)

The team must not go stale. Technology moves; a skill written months ago can encode a deprecated approach or miss a CVE. Rather than a background cron, the team checks its currency **whenever it's engaged** and refreshes itself when overdue, then continues the task.

## The marker & the staleness rule
- A marker file, **`.claude/team/last-update.txt`**, holds a single ISO date — the last time the team was refreshed. The installer scaffolds it to the install date; this skill rewrites it.
- **Rule: if `today − marker > 7 days`, the team is stale.** Compare against today's date (from session context).

## Check on use (trigger)
At **tech-lead review** (workflow step 1), before doing the task, the lead reads the marker:
- **Fresh (≤ 7 days)** → proceed with the task normally.
- **Stale (> 7 days)** → run the refresh below **first**, then continue with the original task. This is exactly the user's intent: "if the task I give today is more than a week past the last update, go update, then continue."

## The refresh process
1. **Scope** — list the team's active stacks/skills (from `.claude/skills/` and the project's stack): frameworks, languages, key libraries, deploy/CI tooling.
2. **Research what changed since the marker** — use the `tech-research` skill: web-search (current year) for new stable releases, deprecations/breaking changes, and shifted best practices for those stacks. Run a **security** pass for new CVEs / advisories on the team's dependencies (see the `security` skill, coordinate with devops).
3. **Apply conservative updates** — for each affected skill/agent, update it to reflect the current best practice (versions, commands, patterns, warnings). Keep changes incremental and justified; don't rewrite wholesale. Anything risky or breaking is **surfaced to the user**, not silently applied.
4. **Note new specialties** — if the research shows the team should gain a whole new capability, hand off to `capability-expansion` (gated) rather than cramming it here.
5. **Keep the authoring standard current** — when a refresh touches how skills/agents themselves are written (skill format, evaluation, agent-interop standards like MCP/A2A), update the **`skill-authoring`** skill and, if the underlying guidance shifted, the canonical references in `docs/references/agent-engineering/`. The references are the source of truth; the skill is their propagated distillation.

## Record & reset
- **Append a dated entry** to `docs/team-updates.md` (project-owned, survives installs): the date, what was checked, and what changed — so there's a visible history. See the `documentation` skill.
- **Rewrite the marker** `.claude/team/last-update.txt` to today's date.
- **Guard the cycle**: if the refresh touched any cycle-carrying file (modes, statuses, gate, board driving — see `docs/cycle-contract.md`), run `bash scripts/check-cycle-consistency.sh` in the source repo and fix any drift **before** shipping — a currency refresh must never break the delivery loop.
- If the installed payload (skills/agents/`CLAUDE.team.md`) changed, **bump `VERSION`**.
- Then **continue the original task**.

## Source repo vs. consuming project
- **In the `claude-team` source repo**: edit the canonical skills/agents directly, bump `VERSION`, and the refresh propagates to every project on its next `install.sh`. This is the primary place updates happen.
- **In a consuming project**: managed skills/agents are **replaced on update** (they're in the installer manifest), so the cleanest way to get canonical updates is to **re-run the installer** (`git -C <claude-team> pull && bash install.sh <project>`). Use this skill locally to (a) refresh the marker, (b) capture project-specific currency notes in `docs/team-updates.md`, and (c) flag managed-skill staleness to fix upstream. Locally **added** capability skills (from `capability-expansion`) are not managed and are refreshed in place.

## Principles
- **Current over familiar** — verify against today's sources, never stale memory. See the `tech-research` skill.
- **Security is continuous** — every refresh includes a CVE/advisory check. See the `security` skill.
- **Conservative & visible** — apply low-risk currency updates; surface anything breaking; always log what changed.
- **Don't block needlessly** — the check is cheap; only the >7-day case triggers real work, and it runs once, then the task continues.
