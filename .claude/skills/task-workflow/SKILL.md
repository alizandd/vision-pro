---
name: task-workflow
description: The team's shared task lifecycle and status conventions — the single source of truth for how tasks move from To Do to Done, how bugs are filed and routed, and the definition of done. Always use this skill whenever the conversation involves task status, a board/backlog, moving a ticket, filing or routing a bug, or deciding whether something is "done". Used by the task-manager and the tester to stay consistent.
---

# Task Lifecycle & Status Conventions

A shared workflow so everyone — task-manager, tester, and specialists — speaks the same language. All statuses, labels, and reports are in English.

## Operating modes (how a request enters the pipeline)
Every request runs in one of the seven modes below. Identify the mode first; it decides where the pipeline **stops**.

### Mode 1 — Review → Tasks (no implementation)
- **Trigger**: the user gives a **title/goal** and there is existing code in the directory.
- **Flow**: tech-lead + the relevant team **review the existing code against the title** (architecture, correctness, security, extensibility) → produce the task breakdown → **STOP**.
- **No code is written.** The deliverable is the reviewed task list only. Use this to scope/plan without touching code.

### Mode 2 — Review → Tasks → Implement → QA → Done (existing code)
- **Trigger**: existing code that should actually be delivered/changed.
- **Flow**: code goes to tech-lead review → into the team → tasks come out → **(if TeamFlow is in use: register the approved tasks to the board first)** → **each team implements its tasks** → **tester verifies the full cycle** against acceptance criteria → on failure, it goes **back to the lead + the responsible team from the start** (bug routed, fixed, re-verified) → loop **until Done**.
- This is the full delivery cycle on an existing codebase.
- **Order matters:** tasks are registered to TeamFlow **before** implementation and each card is driven live (To Do → In Progress → In Review = lead code review → In QA = tester → Done) — never build first and back-fill the board. See **"Order of operations when the board is in use"** below.

### Mode 3 — Greenfield: Design → Tasks → Implement → QA → Done (no code)
- **Trigger**: there is **no code yet** — building from base.
- **Flow**: the **tech-lead designs the scenario/architecture first** (design doc / ADR before anything), raises it with the team → tasks come out → **(if TeamFlow is in use: register the approved tasks to the board first)** → **code is implemented** → tester verifies → loop **until Done**.
- The lead-authored scenario is the starting point; nothing is built before it exists.
- **Order matters:** same as Mode 2 — tasks land on the board (To Do) **before** any code, then each card is driven live through In Progress → In Review (lead code review) → In QA (tester) → Done. See **"Order of operations when the board is in use"** below.

### Mode 4 — Task Force: lead implements scenario + code directly (fast track)
- **Trigger**: **speed matters** — an urgent fix, a small well-understood change, or a time-boxed spike-to-delivery where the full breakdown + per-team delegation would be pure overhead.
- **Flow**: the **tech-lead personally does it end-to-end** — designs the scenario **and writes the code directly** — skipping the task-breakdown and per-team hand-offs so it ships fast.
- **Quality/security bar is NOT dropped** — only the ceremony is compressed: the lead still applies `engineering-principles` and `security`, does a self-review, and runs at least a light tester smoke-check before Done. For anything large, risky, or genuinely cross-area, **fall back to Mode 2/3**.
- **Ticketing is minimal/optional**: record a single tracking task for traceability if the change matters; no full backlog.

### Mode 5 — Execute from an external backlog (Jira/task-manager API)
- **Trigger**: tasks already live in an external task-manager (Jira or similar — the specific system/credentials are provided by the user; the connector is a planned integration).
- **Flow**: connect to the task-manager **API → read the project board/task list →** the tech-lead routes each task to the responsible team → **teams implement the code in the project** → tester verifies → status is **driven back in the external system** (In Progress / In Review / Done) → loop **until Done**.
- This is the **read/pull** direction of the integration. (The push/write direction — registering newly-produced tasks — is the review gate further below.) The team does **not** invent the backlog here; it executes the one that already exists.
- The concrete API (TeamFlow: read board, move tasks, comment), auth/secrets, and our status↔column mapping live in the **`taskmanager-api`** skill — use it for every external call.

### Mode 6 — System off (disabled)
- **Trigger**: the user explicitly does **not** want this team system involved in the work.
- **Flow**: the whole team pipeline is **turned off** — no mode routing, no lead breakdown, no delegation to subagents, no task pipeline, no QA gating. Behave as plain Claude Code and do the work directly.
- It stays off until the user re-enables it. This is a clean kill-switch, not a degraded mode.

### Mode 7 — Review sweep: verify the board → Done or back to To Do
- **Trigger**: tasks are sitting in the **Review** column of the external board (TeamFlow) and need to be checked — work was implemented and now must be verified, not authored or built.
- **Flow**: connect to TeamFlow and **read the Review column**, then process tasks **one by one**: the tech-lead routes each to the **tester** (and the responsible specialist when a closer look is needed) to confirm it was **implemented correctly against its acceptance criteria** (including the security checks). For each task:
  1. **Make the code current before judging it** (don't review stale code):
     - `git fetch` all, and bring **`develop`** up to date (`git checkout develop && git pull`).
     - **Check out the task's branch**: every task names its `feature/<feature-slug>` (per `git-workflow`). Switch to it and pull the latest: `git checkout feature/<slug> && git pull`. Verify the **task's work is actually present on that branch** (the expected commits/behavior are there, and the branch isn't behind `develop` in a way that hides it — rebase/merge `develop` in if needed to test against current integration).
     - If the named branch is **missing, empty of the task's work, or hopelessly behind** → treat as a **Fail** (To Do + a comment saying the branch/update wasn't found) — there's nothing valid to verify.
  2. **Verify on that branch** against the acceptance criteria + security checks — build/run the branch per `testing-strategy` (use the develop/preview environment if the branch is deployed there). The point is to test the **actual current code on the task's branch**, not a stale checkout.
  3. **Pass → move the task to Done**, comment the QA result, then **integrate**: **merge the feature branch into `develop` and push `develop`** (this auto-deploys to the develop server). Delete the merged branch once the **whole feature** is done. ⚠️ Because a `feature/<slug>` branch is **shared by all that feature's tasks**, only merge when the branch carries no unfinished sibling-task work; if other tasks of the same feature are still open, mark this task Done but **defer the merge until the feature's remaining tasks also pass**, and note that in the comment.
  4. **Fail → move the task back to To Do** and **add a comment stating exactly what's wrong or missing** (which acceptance criteria failed, repro, expected vs. actual). **Do not merge.** It re-enters the cycle for a fix.
- This is the **verification/audit counterpart to Mode 5**: the team does **not** invent tasks or write features here — it validates an existing board, brings the code current, and drives each task to its correct terminal/return state (merging passes into `develop`). Board reads/moves/comments go through the `taskmanager-api` skill; the git steps follow the `git-workflow` promotion flow.

> Modes 2 and 3 run the full status lifecycle below. Mode 4 runs a compressed lifecycle (lead implements → light QA → Done). Mode 5 runs the full lifecycle but on tasks **pulled from an external backlog** rather than produced here. Mode 1 ends at a reviewed **To Do** backlog and never enters In Progress. Mode 6 disables the pipeline entirely. Mode 7 verifies tasks already in **Review** and sends each to **Done** (pass) or back to **To Do** with a comment (fail).

## Who gets tasks (team inclusion rules)
Not every team produces a ticket on every request. The tech-lead includes a team **only when its work is real**:
- **Designer** — gets tasks **only when design is needed** (no existing design/design-system to follow, per the request). If a design already exists, the designer has **no task** and frontend implements it as-is.
- **DevOps** — gets tasks **only for project structure → deploy-to-server work** (conform the project to the house structure and build its deploy/CI per `app-deploy` & `cicd-pipeline`). If the request needs no structural/deploy change, **no devops ticket enters the system**.
- Backend, frontend, tester are included whenever their area is actually touched. Don't manufacture filler tickets for an area with no work.

## Statuses (the board columns)
1. **To Do** — defined and ready, not started. Must have a clear description + acceptance criteria.
2. **In Progress** — actively being worked by an assignee.
3. **In Review** — implementation complete, awaiting tech-lead review and/or QA.
4. **In QA / Testing** — with the tester, being verified against acceptance criteria.
5. **Bug / Reopened** — failed QA (or a defect was found). A bug report is attached and it's routed back to the responsible area.
6. **Done** — passed QA against all acceptance criteria and any regression check. Only the tester (or tech-lead) moves a task here.
7. *(optional)* **Blocked** — cannot proceed; must record what it's blocked on (dependency/ticket).

> **Board reality check.** A physical TeamFlow board often has **fewer columns** than these logical statuses — typically one Review/QA column between In Progress and Done, and no dedicated Bug/Reopened column. Map by the column *flags* (see `taskmanager-api` › Status mapping) and record the transitions the board can't express as **comments** on the card: the In Review → In QA hand-off becomes a comment ("Lead review passed → QA"), and Bug/Reopened is the move back to In Progress (To Do in Mode 7) plus the bug-report comment. Never invent, rename, or wait for a column the board doesn't have.

## Standard transitions
- To Do → In Progress → In Review → In QA → **Done**
- In QA → **Bug/Reopened** → In Progress (fix) → In Review → In QA → Done
- Any → Blocked → (back to previous) when unblocked

A task may only reach **Done** through QA. "Code complete" is *In Review*, not Done.

## Definition of Done (DoD)
A task is Done only when:
- The work was merged to `develop` and **verified by the tester on the develop environment** (not just locally) — see the promotion flow in `git-workflow`.
- All acceptance criteria are met and verified by the tester.
- A light regression check around the change passed.
- Required docs updated (e.g. API contract, DEPLOY.md) where relevant.
- No open Blocker/Critical bugs against it.
- For a release: the tech-lead has promoted `develop → main` and run a **production smoke test** on `main` with no problem.

> **Mode 7 variant (deliberate exception).** In a review sweep the tester verifies on the task's `feature/<slug>` branch **brought current with `develop`** *before* the merge — so failed work never lands on develop. The merge to `develop` on pass completes the first bullet; give the resulting develop deploy a quick post-merge check. This ordering difference is intentional; everywhere else (Modes 2/3/5), QA happens on the develop environment after the merge, per `git-workflow`.

## Bug routing
When QA fails, the tester files a structured bug report (see the tester agent) and sets status to **Bug/Reopened** with the **Area/Assignee** label pointing to the responsible team (backend / frontend / devops / 3d). Routing and re-assignment happen via the tech-lead. After the fix, it returns through In Review → In QA, and the tester re-verifies before Done.

## Labels (shared vocabulary)
- **Area**: `backend`, `frontend`, `devops`, `3d`, `security`
- **Type**: `feature`, `bug`, `chore`, `spike`
- **Severity** (bugs): `blocker`, `critical`, `major`, `minor`, `trivial`
- **Size**: `S` / `M` / `L` (or story points)

## Task sizing
- **Hard cap: ~8 hours (one working day) per task.** Any task estimated above 8h must be split into smaller sub-tasks that each fit within the cap, each with its own acceptance criteria and dependencies.
- Keep tasks small enough to estimate confidently; a parent/epic can group the sub-tasks.

## Linking
- Bugs link back to the originating task.
- Dependencies are explicit (`blocks` / `blocked by`) so the board reflects real ordering.

## Task review & external registration gate
This is the **push/write** direction of the external integration (Mode 5 is the read/pull direction). Tasks are **never auto-pushed to an external system.** The flow is:
1. The task-manager produces the breakdown (lead-signed-off) and **presents it to the user for review.**
2. The **user reviews the tasks** and may request changes — revise and re-present until approved.
3. **Only after the user explicitly says to register** are tasks sent to the external task-manager (**TeamFlow**, via its API — see the `taskmanager-api` skill). No registration happens without that explicit go-ahead.
4. Until the user invokes registration, the deliverable is the reviewed English ticket list itself.

So: **produce → user review → (explicit approval) → register.** Skipping the review/approval step is not allowed.

## Order of operations when the board is in use (register FIRST, then build)
This is the sequence the team most often gets wrong — **the board is created before the work, not after it.** Whenever tasks are tracked in TeamFlow (Mode 5 always; Modes 2 & 3 once the user approves registration), the order is strict:
1. **Design + breakdown first** — lead review / design doc, then the task-manager produces the tickets (full description + acceptance criteria + the `feature/<slug>` branch).
2. **Gate → register every approved task into To Do *before any code is written.*** All tickets land in the start column first. The board now shows the whole plan in To Do.
3. **Then implement task-by-task, driving each card live — one card at a time, in real time** as the work actually happens. The move is made **at the moment the transition really happens**, never batched afterward:
   - To Do → **In Progress** at the **instant a specialist starts the task** — move the card *first*, then write the first line of code. **Never write a task's code while its card is still in To Do**, and never move several cards to In Progress at once "to get going" — only the card actually being worked is In Progress.
   - In Progress → **In Review** at the **moment that task's code is complete** (not after the next task, not at the end of the batch) → the **tech-lead does the code review here** (`code-review` skill);
   - on lead approval → **In QA** → the **tester verifies** on the develop env → pass → **Done**; fail → **Bug/Reopened → In Progress** (re-verify after the fix).
4. **Never "code-first, tasks-after," and never "work now, move the card later."** Building the whole feature and only then back-filling a board — or doing the work and moving the cards in one batch at the end — is the exact bug this rule exists to kill. The board must mirror live state **as it changes**, so the timeline anyone reads later matches when the work really happened.
5. **Record every step at its real moment, with its timestamp.** Each transition is a **move + a comment posted at that moment** so the board carries a step-by-step, timestamped audit trail (TeamFlow stamps every move and comment server-side, and auto-sets `started_at` on In Progress / `completed_at` on Done). The intermediate steps (→ In Review, → In QA, → back to To Do) carry **no automatic timestamp of their own**, so the moment is captured by commenting on the move — that's how "exactly when each step happened" lands in TeamFlow. Don't reconstruct the timeline after the fact; it must be written live. Concrete calls live in `taskmanager-api` ("Drive a task through its states").

The registration gate above still holds: it gates **step 2** (explicit user approval before the first push). It does **not** permit implementation to jump ahead of registration. The state-driving API calls live in the `taskmanager-api` skill. If the user has **not** enabled TeamFlow for the work, there's no board to drive — run the same lifecycle locally (docs/tasks), still tasks-before-code, still recording each step as it happens.

## Jira/Trello mapping
- Statuses map to board columns above.
- Tasks are **lead-driven**: the tech-lead produces the breakdown (decomposition, ordering, dependencies, ownership), and the task-manager specifies each ticket from that direction and gets the lead's sign-off before the board.
- Each task carries: Title, Type, Description, Acceptance Criteria, Labels, Dependencies, Estimate, Assignee/Team — produced by the task-manager.
- External registration (into a Jira-like system via API) is gated on the user's explicit approval — see the review gate above.
