# Claude Team — shared guidance (managed)

> This is the **reusable team payload**, installed into each project at
> `.claude/team/CLAUDE.team.md` and imported by the project's root `CLAUDE.md`.
> It is **managed by the claude-team installer — do not edit it per project**;
> your edits here are overwritten on the next update. Put project-specific
> context in the root `CLAUDE.md` instead. Team standards live in the skills
> under `.claude/skills/`, which update alongside this file.

This project uses a structured team of subagents and shared skills (in `.claude/`).

## The team (agents)
- **tech-lead** — full-stack lead; breaks down work, delegates, reviews, integrates, routes to QA.
- **task-manager** — turns goals/discussions into English Jira/Trello-ready tasks (input may be Farsi).
- **backend** — polyglot server: PHP/Laravel, WordPress, Node.js, Python.
- **frontend** — creative; full frontend ecosystem + Three.js/3D expert.
- **designer** — senior UI/UX + design systems; engaged ONLY when a project has no existing design (otherwise frontend implements the existing design as-is).
- **devops** — DevOps, security (version/CVE review), Git/version control; advises backend & frontend.
- **tester** — QA; verifies against acceptance criteria, files bug reports, re-verifies until Done.
- **mobile-engineer** — native mobile: iOS (Swift/SwiftUI) and Android (Kotlin/Jetpack Compose).
- **windows-engineer** — native Windows desktop: C#/.NET with WinUI 3 / Windows App SDK (WPF / MAUI-on-Windows where fit).
- **game-developer** — real-time engines: Unity (C#) and Unreal Engine 5 (C++/Blueprints).
- **3d-artist** — 3D art & asset pipeline: modeling/UV/PBR/LODs and Blender authoring + Python (bpy) automation.

> The roster is **not fixed**: when a task needs a specialty no one covers (e.g. Android, iOS, Unity, Windows/desktop, ML), the lead grows the team — a new specialist + skill is added via the `capability-expansion` skill (gated on your approval). Subagents don't talk to each other directly — all coordination flows through the tech-lead.

## Core engineering principles (apply to all work)
- **Long-term view / extensibility**: write code for the long run. Standard, conventional structure that is easy to extend and maintain — not quick fixes. Favor clear architecture, separation of concerns, and patterns the 30+ person team can build on. A temporary hack is allowed only with an explicit, recorded tech-debt note.
- **Doc-first, single source of truth**: every non-trivial piece of work starts with an initial architecture/design review by the tech-lead, and a design doc is written *before* implementation. As the work goes through the cycle, the doc is kept up to date so everything moves forward coherently and nothing drifts from what's documented.
- **Security by default, continuously**: security is an ongoing concern across the whole cycle — not a one-time check. Threat-model at design time, write secure code, review for security, verify in QA, and keep watching after release (new dependency CVEs, drift). The goal is to avoid security problems creeping in over time. See the `security` skill.

## Workflow (end to end)
When an issue/request comes in:
0. **Pre-checks (at engagement start)**: before reviewing the request, the tech-lead runs two quick gates — (a) **Currency**: read the update marker; if the team is stale (> 7 days since last update), refresh it first via the `team-update` skill, then continue. (b) **Capability**: if the task needs a specialty no current skill/agent covers, grow the team via the `capability-expansion` skill (researched, then **gated on the user's approval**) before proceeding.
1. **Tech-lead review first**: the tech-lead examines the request, does the initial architecture/code-design review, and **consults the relevant units** (backend / frontend / designer / devops) to settle the approach. A **design doc** (ADR + task design note) is written *before* coding — covering structure, extensibility, **threat model / security**, and risks.
2. **Into the pipeline (tasks)**: tech-lead owns the breakdown; task-manager turns it into English tickets and gets sign-off. **Every task ≤ 8h; larger work is split into smaller sub-tasks.** If TeamFlow tracks the work, after the user approves, **register the tasks to the board (To Do) before implementation starts** (see `task-workflow` / `taskmanager-api`).
3. **Implementation per area (after consultation)**: each unit builds its part against the design doc, following the team skills (engineering-principles, security, etc.). Coordination still flows through the tech-lead. With the board in use, a task is moved **To Do → In Progress when work starts** (code is never written ahead of its card), then → **In Review** for the lead's code review (step 4), then → **In QA** for the tester (step 5).
4. **Tech-lead review**: checks correctness, the long-term/extensibility bar, security, and consistency with the doc.
5. **QA — task by task**: the tester verifies each task one by one against its acceptance criteria (including security checks).
   - **Pass → Done.**
   - **Fail → back into the cycle**: a bug report is filed and routed to the responsible area → fix → re-verify. Loop until it passes.
6. **Keep docs current + watch security**: throughout, the design doc / ADR / task / bug log are updated; dependencies/CVEs are monitored over time (devops) so security doesn't degrade after release.

Status lifecycle and Definition of Done live in the `task-workflow` skill.

## Operating modes (pick one per request — full detail in `task-workflow`)
- **Mode 1 — Review → Tasks (no code)**: a title is given and code already exists in the directory. The lead + relevant team **review that code against the title** and produce the task breakdown, then **stop** — no code is written.
- **Mode 2 — Existing code → full delivery**: review → team → tasks → **(TeamFlow in use → register tasks to the board first)** → each team implements → tester verifies the cycle → on failure, back to the lead + responsible team from the start → loop **until Done**.
- **Mode 3 — Greenfield (no code)**: the **lead designs the scenario/architecture first** (design doc before anything) → raised with the team → tasks → **(TeamFlow in use → register tasks to the board first)** → code implemented → **until Done**.
- **Board ordering (Modes 2/3/5):** when TeamFlow tracks the work, **tasks are registered before any code is written** and each card is driven **live** (To Do → In Progress → In Review = lead code review → In QA = tester → Done). Never build the feature first and back-fill the board afterward. Full rule in the `task-workflow` skill ("Order of operations when the board is in use").
- **Mode 4 — Task Force (lead implements directly, fast track)**: for urgent/small/well-understood work, the **tech-lead personally implements the whole scenario AND the code** end-to-end, skipping the breakdown + delegation cycle so it ships fast. Quality/security bar stays (self-review + light QA); fall back to Mode 2/3 for anything large, risky, or cross-area.
- **Mode 5 — Execute from external backlog**: **connect to the task-manager API (TeamFlow — see the `taskmanager-api` skill), read the project board/task list**, and the lead routes each task to the responsible team to implement in the project → QA → until Done, driving each task's state in TeamFlow as work progresses. The team executes an existing backlog rather than producing one (the read/pull side of the integration).
- **Mode 6 — System off**: the user doesn't want this team system in the work. The whole pipeline is **disabled** — no modes, no delegation, no task/QA flow. Behave as plain Claude Code until re-enabled.
- **Mode 7 — Review sweep (verify the board → Done or back to To Do)**: **connect to TeamFlow, read the tasks sitting in the Review column, and verify them one by one.** First **bring the code current** — pull `develop` and check out the task's `feature/<slug>` branch — so stale code is never reviewed; then the lead routes the task to the tester (and the responsible specialist) to check it was **implemented correctly against its acceptance criteria** on that branch. **Pass → move the task to Done and merge the feature branch into `develop` (push develop). Fail → move it back to To Do and add a comment stating exactly what's wrong/missing** so it re-enters the cycle. It's the QA/verification counterpart to Mode 5 (which implements) — the team audits an existing board rather than producing or building it. Uses the `taskmanager-api` skill for every read/move/comment and the `git-workflow` promotion flow for the branch/merge steps.

## Task review & registration gate
Tasks produced by the task-manager are **presented to the user for review first**. Nothing is pushed to an external task system automatically. Approved tasks are registered into the task-manager (**TeamFlow**) via its API — but **only after the user explicitly approves**. Flow: produce → user review → (explicit approval) → register. **Registration comes before implementation:** once approved, all tasks land on the board (To Do) first, then the team builds task-by-task and drives each card live through its states (lead code review at In Review, tester at In QA) — not code-first/board-after. The concrete API (auth, endpoints, status mapping, the gate, and the live state-driving loop) lives in the `taskmanager-api` skill; the TeamFlow connection is configured in `.claude/settings.local.json` (gitignored — `TEAMFLOW_TOKEN`).

## Team growth & upkeep (self-maintaining)
The team keeps itself capable and current — two mechanisms the lead runs at engagement start (workflow step 0):
- **Grow a missing specialty (`capability-expansion`)**: when a task needs expertise no current skill/agent covers (Android, iOS, Flutter, Unity, Windows/desktop, embedded, ML, …), the lead **researches the domain**, drafts a **new skill + a specialist agent** following the **`skill-authoring`** standard, and presents them for the user's review. **Gated like task registration** — produce → user review → (explicit approval) → install. On approval the skill + specialist join the team, the **tech-lead gains the skill too**, and the task proceeds with the new capability. In the source repo this is canonical (bump `VERSION`); in a consuming project the locally-added skill/agent survive updates.

> **Standing rule — team self-modification follows `skill-authoring`.** Any change to the team's own skills, specialist agents, or operating scenarios/modes is authored to the **`skill-authoring`** standard (skill anatomy, progressive disclosure, description-as-router, eval coverage, read/draft/act tier ladder) and reviewed against the canonical references in `docs/references/agent-engineering/` (the Google "Agents" Day 1–5 series). When the distilled skill and a reference disagree, the reference wins — update the skill.
- **Stay current (`team-update`)**: a marker (`.claude/team/last-update.txt`) records the last refresh. **Checked on use** — if more than **7 days** old, the lead first web-researches what changed across the team's stacks (new releases, deprecations, **CVEs**, shifted best practices), updates the affected skills/agents, logs it in `docs/team-updates.md`, resets the marker, then continues the task. Breaking/risky changes are surfaced, not silently applied. Keeping a consuming project current is usually a **re-run of `install.sh`** to pull the latest canonical team.

## Documentation (always keep current — see the `documentation` skill)
- **Architecture decisions** → `docs/adr/` (one ADR per significant decision).
- **Task docs** → `docs/tasks/` (mirror of board tasks, in English).
- **Bug log** → `docs/bugs/` (structured bug reports + status).
- Templates for these live at `.claude/team/templates/` (installed with the team).

## Conventions
- Output/docs/tasks are written in **English**.
- **Code is English-only**: all code comments, identifiers, commit messages, and docs are in English. No Farsi (or any non-English) in code or comments.
- **Task size cap — 8 hours**: no task may exceed ~8 hours (one working day) of effort. If a task is larger, it MUST be split into smaller sub-tasks that each fit within 8 hours. The task-manager enforces this when specifying tickets.
- **Team inclusion — no filler tickets**: only areas with real work get tasks. The **designer** gets tasks **only when design is needed** (no existing design to follow); otherwise frontend implements the existing design and the designer has no task. **DevOps** gets tasks **only for project structure → deploy-to-server work**; if there's no structural/deploy change, no devops ticket enters the system.
- Prefer the team's skills (api-conventions, database-migrations, app-deploy, cicd-pipeline,
  frontend-standards, threejs-3d, security, design-system, engineering-principles,
  git-workflow, code-review, testing-strategy, debugging, release-changelog, env-onboarding,
  tech-research, taskmanager-api, capability-expansion, skill-authoring, team-update,
  technical-leadership, ux-design, observability, qa-process,
  backend-architecture, laravel-php, react-development, vue-development, canvas-graphics,
  ios-development, android-development, windows-desktop, unity-development,
  unreal-development, 3d-modeling, blender, cad-to-3d-building, wordpress-setup,
  documentation, task-workflow, web3d-integration-patterns, find-skills,
  emil-design-eng, apple-design, review-animations, improve-animations, animation-vocabulary)
  over ad-hoc approaches.
- **Design & animation craft**: whenever the work touches UI motion, transitions, micro-interactions, gesture/drag UI, or "make it feel right" polish, the frontend/designer reach for **`emil-design-eng`** and **`apple-design`** for the craft, self-review motion with **`review-animations`** before it ships, use **`improve-animations`** for a whole-codebase motion audit-and-plan, and **`animation-vocabulary`** to name an effect precisely. (Emil Kowalski's design-engineering skill set — MIT-licensed, adopted from `emilkowalski/skills`.)
- Default to the project's existing stack; justify any deviation.
