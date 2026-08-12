---
name: taskmanager-api
description: The team's external task-manager (TeamFlow) integration — read a project's board/backlog, create tasks, correct or delete a mis-registered task, and move tasks through their states via the HTTPS+JSON API. Always use this skill whenever connecting to the task-manager, running Mode 5 (execute from external backlog) or Mode 7 (review sweep — verify the Review column and move tasks to Done or back to To Do), registering approved tasks into the external system, fixing or removing a task that was entered wrong, reading the task list for a project, or updating a task's status/comments externally.
---

# TeamFlow Task-Manager Integration

The concrete API behind the team's external task-manager. It powers these flows from `task-workflow`:
- **Mode 5 (read/pull)** — read an existing backlog, work the tasks, drive their states.
- **Mode 7 (review sweep)** — read the **Review** column, verify each task against its acceptance criteria, then **move pass → Done** and **fail → To Do with a comment** on what's wrong. Read/move/comment only — no task authoring.
- **Registration gate (write/push)** — after the **user explicitly approves**, create produced tasks in the system.
- **Correction (write)** — a ticket registered with the wrong content is edited in place, or (with the user's go-ahead) deleted and re-registered. See "Fix a wrongly registered task".

Full endpoint reference lives in the TeamFlow repo doc: `../teamflow/docs/integration-api-for-claude-team.md` (sibling repo to `claude-team`). This skill is the operating playbook on top of it.

## Auth & secrets (non-negotiable)
- Base URL: `https://teamflow.qoo.studio/api/v1/integration`. Token is a **user token** (no admin mode — you only see/do what the owner can).
- The token is a **secret**: read it from the environment, **never** hardcode, echo, log, or commit it.
  ```bash
  export TEAMFLOW_TOKEN="tf_…"     # provided by the user; store as a secret
  export TEAMFLOW_BASE="https://teamflow.qoo.studio/api/v1/integration"
  export TEAMFLOW_PROJECT_ID="…"   # default project tasks register into / the board you read
  ```
- These (plus the per-role assignee ids below) live in `.claude/settings.local.json` (gitignored) and reach the shell as env vars. When `TEAMFLOW_PROJECT_ID` is set, **use it directly** — skip the "pick a project" call and add tasks straight to that project.
- Every request: `Authorization: Bearer $TEAMFLOW_TOKEN`, `Accept: application/json`, and `Content-Type: application/json` on POST/PATCH.
- A **Read & write** token is needed to create/move/comment; a read-only token can only read (writes → `403`).
- Error envelopes are JSON: `401` (bad/expired token), `403` (read-only or not allowed), `422` (`{ "message", "errors": { field: [...] } }`). Handle them; don't retry a `403`/`422` blindly.

## Who runs the calls
The HTTP calls are shell `curl`s, so they run from a **Bash-capable step** — the main loop, the **tech-lead**, or a specialist agent. The **task-manager** agent has no Bash: it *produces* the task payloads and the breakdown, and a Bash-capable step performs the actual POST/PATCH after the gate. Keep that division.

## Windows / PowerShell note (read before any call on Windows)
On Windows, two things silently break the bash examples below — both have caused "tasks not added to TeamFlow" reports:
- **`curl` in PowerShell is an alias for `Invoke-WebRequest`** — it does NOT accept `-s`, `-H`, `-d` the way curl does, and the request will fail or return an HTML/PSObject instead of JSON. ALWAYS invoke the real binary as **`curl.exe`** in PowerShell. (Inside the Bash tool / Git Bash, `curl` works as-is.)
- **Env var syntax differs.** Bash: `$TEAMFLOW_TOKEN`. PowerShell: **`$env:TEAMFLOW_TOKEN`**. The `env` block in `.claude/settings.local.json` is exported to both shells by Claude Code, but you must reference it with the right syntax for the shell you're in. If a write returns empty/`401` on Windows, the first thing to check is whether the var actually expanded (run `$env:TEAMFLOW_TOKEN.Length` in PowerShell, or `printenv TEAMFLOW_TOKEN` in Bash — if it's empty, the shell isn't seeing the settings env).
- **Quoting `-d` JSON in PowerShell**: single-quoted here-strings are safest. Example:
  ```powershell
  $body = @'
  { "project_id": 7, "title": "Example", "priority": "high" }
  '@
  curl.exe -s -X POST "$env:TEAMFLOW_BASE/tasks" `
    -H "Authorization: Bearer $env:TEAMFLOW_TOKEN" `
    -H "Accept: application/json" -H "Content-Type: application/json" `
    -d $body
  ```
- **Prefer the Bash tool on Windows** for these calls — the bash examples below run as-is in Git Bash and avoid every issue above. Drop to PowerShell only if Bash isn't available.

## Status mapping (our lifecycle ↔ TeamFlow columns)
TeamFlow columns carry flags — **use the flags, don't hard-code column names** (boards differ):
- `is_start: true` → our **To Do** (project start column; default for new tasks).
- `is_in_progress: true` → our **In Progress** (moving here sets `started_at`).
- a Review/QA column (by name/position, between in-progress and done) → our **In Review / In QA**.
- `is_done: true` → our **Done** (moving here sets `completed_at`).
Read the board first to resolve the real column `id`s and flags before any move. Some boards restrict transitions (disallowed → `403`/`422`).

**Fewer columns than logical statuses?** Most boards have a **single** Review/QA column and no Bug/Reopened column. Don't look for (or wait on) a column that isn't there: when one column serves both In Review and In QA, the lead-review → QA hand-off is recorded as a **comment** on the card ("Lead review passed → QA"), not a move; a QA fail is the move back to the in-progress column (the start column in Mode 7) plus the bug-report comment. The logical lifecycle in `task-workflow` still applies in full — comments carry the steps the board can't.

## Area & assignee mapping (every task is tagged by area)
Tasks register **into `$TEAMFLOW_PROJECT_ID`**. The responsible area is carried as a **tag** on **every** task; the assignee is set only for single-person roles.

- **Area → tag (always):** tag each task with its area. Resolve the tag id by name from the catalog (`GET /tags`) — the team uses **`Backend`, `Frontend`, `Tester`, `Devops`** (add `Tech-lead` / `Designer` if your board defines them). Put the matching id in `tag_ids`. This is how frontend/backend work is routed even though those roles have several people.
- **Single-person roles → also auto-assign** from env: `tech-lead → $TEAMFLOW_ASSIGNEE_TECH_LEAD`, `devops → $TEAMFLOW_ASSIGNEE_DEVOPS`, `tester → $TEAMFLOW_ASSIGNEE_TESTER`. Pass that numeric id as `assignee_id` on create (in addition to the area tag).
- **Frontend & backend → multiple people → no auto-assignee.** Tag the area (`Frontend`/`Backend`) but leave `assignee_id` **off**; a human picks the specific person on the board. Don't guess one.
- Resolve/verify ids against the board/catalog: `tag_ids` from `GET /tags`, `assignee_id` must belong to a team on the project. If a tag name or a single-role env var is missing, attach what you can and note the gap.

## Resolve a named person → `assignee_id` (never guess an id)
When a request says "assign it **to me**" or "assign it **to Nima**", turn the human reference into a concrete `assignee_id` *before* you create/move the task — don't invent a numeric id.
- **"assign to me"** → `GET /me` returns the token owner `{ id, name, email }`; use that `id`.
  ```bash
  curl -s "$TEAMFLOW_BASE/me" -H "Authorization: Bearer $TEAMFLOW_TOKEN" -H "Accept: application/json"
  ```
- **"assign to <name>"** → `GET /users/search?q=<name>&project_id=$TEAMFLOW_PROJECT_ID` searches by name **or** email, scoped to that project's **assignable users** (exactly who may be assigned there), and returns matches with their `id`. Pass `project_id` so the match is directly assignable; `q` is required.
  ```bash
  curl -s "$TEAMFLOW_BASE/users/search?q=nima&project_id=$TEAMFLOW_PROJECT_ID" \
    -H "Authorization: Bearer $TEAMFLOW_TOKEN" -H "Accept: application/json"
  ```
  0 results → tell the user no assignable match; several → disambiguate by exact name/email or ask, don't pick blindly. Both endpoints need only `tasks:read`.

## Relative due dates ("today" / "tomorrow")
The API stores a **calendar date**, not a keyword. When a task says it's due "today" or "tomorrow", compute the absolute date from **today's date** (it's in your context) and send `due_date: "YYYY-MM-DD"`. E.g. with today = 2026-06-23 → "today" → `2026-06-23`, "tomorrow" → `2026-06-24`. Never send the literal word.

## Set a task's cover image on upload
The file-upload call (below) takes an optional `cover=true` field: it attaches the file **and** sets it as the task's cover in one request. The file must be an **image** (jpg/png/gif/webp/svg) — `cover=true` on a non-image → `422` (`errors.cover`) and nothing is stored. Omit `cover` to attach without touching the cover.
```bash
curl -s -X POST "$TEAMFLOW_BASE/tasks/<id>/files/upload" \
  -H "Authorization: Bearer $TEAMFLOW_TOKEN" -H "Accept: application/json" \
  -F "file=@/path/to/hero.png" -F "cover=true"
```

## Read the backlog (Mode 5)
1. **Pick the project** — when `$TEAMFLOW_PROJECT_ID` is set, use it directly. Otherwise (tokens aren't locked to one) list and pick:
   ```bash
   curl -s "$TEAMFLOW_BASE/projects" -H "Authorization: Bearer $TEAMFLOW_TOKEN" -H "Accept: application/json"
   ```
2. **Read the board (the task list)** — columns in order, tasks expanded (assignee, tags, checklist, files, threaded comments, dependencies):
   ```bash
   curl -s "$TEAMFLOW_BASE/projects/<id>/board" -H "Authorization: Bearer $TEAMFLOW_TOKEN" -H "Accept: application/json"
   ```
   Note each column's `id` + flags (you need them to move tasks). Use `dependency_count`/`blocking_count` to respect ordering.
3. **Read the tag catalog** (to map area → `tag_ids` on create):
   ```bash
   curl -s "$TEAMFLOW_BASE/tags" -H "Authorization: Bearer $TEAMFLOW_TOKEN" -H "Accept: application/json"
   ```
   Note the ids of `Backend`, `Frontend`, `Tester`, `Devops` (and any others).
4. **One task in full** (adds `time_logs`, `work_sessions`): `GET $TEAMFLOW_BASE/tasks/<id>`.
5. The **tech-lead routes** each task to the responsible team by its tags/area; teams implement in the project; the lifecycle in `task-workflow` and the promotion flow in `git-workflow` still apply (work on `develop`, QA on the develop env, lead promotes to `main`).

## Drive a task through its states
Move one column per transition (read the board for the target `id` first):
```bash
curl -s -X PATCH "$TEAMFLOW_BASE/tasks/<id>/move" \
  -H "Authorization: Bearer $TEAMFLOW_TOKEN" -H "Accept: application/json" -H "Content-Type: application/json" \
  -d '{ "board_column_id": <target_id>, "position": 0 }'
```
Typical run: To Do → In Progress (specialist starts) → **In Review (tech-lead code review, `code-review` skill)** → In QA (tester verifies on develop) → Done. A card is moved to In Progress **before** its code is written, not after the work is finished.

**Move at the real moment — one card at a time, never batched.** Each transition PATCH is sent **when the transition actually happens**, not reconstructed at the end of the run: move → In Progress the instant the specialist starts (then code), move → In Review the instant that task's code is complete. Don't move several cards together or back-fill the board after the work — the move times *are* the project timeline.

**Timestamp every step.** TeamFlow stamps each move and comment server-side, and auto-sets `started_at` when a card enters an `is_in_progress` column and `completed_at` when it enters `is_done`. The **intermediate** steps (→ In Review, → In QA, → back to To Do) have **no timestamp field of their own**, so capture the moment by **posting a comment on each move** — that comment's server time is the record of when the step happened. So every transition = **move + a short comment**, giving a step-by-step, time-stamped audit trail on the card. Post progress / QA notes as comments so humans watching the live board see it:
```bash
curl -s -X POST "$TEAMFLOW_BASE/tasks/<id>/comments" \
  -H "Authorization: Bearer $TEAMFLOW_TOKEN" -H "Accept: application/json" -H "Content-Type: application/json" \
  -d '{ "body": "Tests pass on develop. Moving to Review." }'   # reply: add "parent_id": <comment_id>
```
Mirror real state: when the **tester** passes a task on develop, move it to Review/Done and comment the QA result; when a bug is filed, comment it and move it back. Keep the board honest — it's the shared source of truth.

## Register produced tasks (write — gated)
This is the **push** side of the registration gate. **Do NOT create tasks until the user has reviewed the breakdown and explicitly approved registration** (see `task-workflow`). Once approved, register **all** approved tickets into **To Do first — before any implementation begins** (Modes 2 & 3), so the board shows the whole plan and is then driven live as work happens. Then, for each approved ticket:
```bash
curl -s -X POST "$TEAMFLOW_BASE/tasks" \
  -H "Authorization: Bearer $TEAMFLOW_TOKEN" -H "Accept: application/json" -H "Content-Type: application/json" \
  -d '{ "project_id": '"$TEAMFLOW_PROJECT_ID"', "title": "...", "priority": "high",
        "board_column_id": <start_col_id>, "description": "<p>…</p>",
        "assignee_id": <role_user_id>, "due_date": "YYYY-MM-DD", "estimate_hours": 6,
        "tag_ids": [<id>], "dependency_ids": [<upstream_task_id>, …],
        "checklist": ["Write tests", "Update docs", "Security review"] }'
```
- Required: `project_id` (use `$TEAMFLOW_PROJECT_ID` so the task lands in the configured project), `title` (≤255), `priority` (`low|medium|high|urgent`). Others optional (see the doc).
- **Enforce the ≤8h cap**: never register a task with `estimate_hours > 8` — split it into sub-tasks first.
- **Assignee**: for tech-lead/devops/tester tasks, set `assignee_id` from the matching `$TEAMFLOW_ASSIGNEE_*` env var. For **frontend/backend** tasks, **omit `assignee_id`** — those roles have several people and are assigned by hand in TeamFlow (see "Assignee mapping"). `assignee_id` must belong to a team on the project.
- **Area tag (required on every task)**: resolve the area tag id from `GET /tags` by name (`Backend`/`Frontend`/`Tester`/`Devops`) and include it in `tag_ids` so the task is routed to the right area — see "Area & assignee mapping". Add any other Type labels as extra `tag_ids`.
- Respect team-inclusion: only register designer/devops tickets when their work is real (per `task-workflow`).
- **Dependencies (which tasks depend on which)**: the task-manager must capture each ticket's dependencies in the breakdown. Register in **dependency order** (upstream first), capture each returned task `id`, then pass the upstream ids as `dependency_ids` on the dependent task so the link is created at creation time. Each dependency must be a task on the **same project**; a task can't depend on itself or a cross-project task (→ `422`). Older TeamFlow boards that don't accept `dependency_ids` silently ignore it — fall back to recording the dependency in the description / a comment and ordering the registration.
- **Checklist (things to verify)**: turn a ticket's acceptance criteria / sub-steps into a `checklist` — an array of label strings. Each becomes an **unchecked** item, ordered as given. Keep labels concise and verifiable (e.g. acceptance-criteria lines, security checks). Older boards that don't accept `checklist` ignore it — fall back to listing the items in the description.
- **Branch + full description**: every task carries its `feature/<feature-slug>` branch (the **same** branch for all tasks of one feature — see `git-workflow`). TeamFlow has no dedicated branch field, so put the branch as the **first line of `description`** (e.g. `<p><strong>Branch:</strong> feature/login</p>`) and keep tasks of the same feature on the identical slug. The `description` itself must be the **complete, copy-paste-ready** spec the task-manager produced (behavior, service/API contract, states, edge cases) — send the full thing, don't truncate it to a one-liner.

## Fix a wrongly registered task (update / delete)
A ticket registered with the wrong content is **corrected in place** — never left standing next to a duplicate "correct" copy. Partial update; send only the fields that change (omitted fields are untouched, `tag_ids` replaces the whole set):
```bash
curl -s -X PATCH "$TEAMFLOW_BASE/tasks/<id>" \
  -H "Authorization: Bearer $TEAMFLOW_TOKEN" -H "Accept: application/json" -H "Content-Type: application/json" \
  -d '{ "title": "Corrected title", "priority": "high", "description": "<p>…</p>", "tag_ids": [<id>] }'
```
- Editable: `title`, `description`, `priority`, `assignee_id`, `reviewer_id`, `team_id`, `delivery_id`, `due_date`, `estimate_hours`, `started_at`, `completed_at`, `tag_ids`, `cover_file_id`. The ≤8h cap still applies to a corrected `estimate_hours`.
- **A column change is still a `/move`**, not an update — the move is what records the timed transition the reports read.
- Only when the ticket is the **wrong task altogether** (not fixable by editing), delete it and register a fresh one:
```bash
curl -s -X DELETE "$TEAMFLOW_BASE/tasks/<id>" -H "Authorization: Bearer $TEAMFLOW_TOKEN" -H "Accept: application/json"
```
- `204` on success; permanent, and it takes the card's comments/history with it. Lead+ only (Admin/Manager/team lead/project manager) — a member's token gets `403`.
- **Deleting a task is destructive and outward-facing: ask the user first**, exactly like the registration gate. Editing an incorrect field needs no gate; wiping a ticket does. If the work is real but shouldn't clutter the board, archive it in the UI instead of deleting.

## Attach the task's files / images (after create)
When the request that produced a task **came with attachments** — a mockup, screenshot, reference doc, or any file the scenario provided — upload each to the task so it travels with the ticket. Create the task first (to get its `id`), then upload each asset as a **multipart** request (field `file`, one per call):
```bash
curl -s -X POST "$TEAMFLOW_BASE/tasks/<id>/files/upload" \
  -H "Authorization: Bearer $TEAMFLOW_TOKEN" -H "Accept: application/json" \
  -F "file=@/path/to/mockup.png"
```
- Do **not** set `Content-Type` manually — `-F` makes curl send `multipart/form-data` with the right boundary.
- One file per request; loop over all the files the task came with. Returns the created file (`201`); it then shows up under `files` on the board/task.
- Allowed types/size are enforced server-side (images, pdf, office docs, zip, mp4/mov…); oversize/disallowed → `422`. Needs a write token.
- Route each attachment to the task it belongs to (match the file to the scenario/ticket it was provided for); don't dump every file onto one task.

## End-to-end Modes 2 & 3 loop (team-produced backlog → board → build)
When the team produces the backlog itself (Mode 2 existing code, Mode 3 greenfield) **and** TeamFlow is in use, register **before** building and then drive each card live — do **not** write the feature first and back-fill the board (see `task-workflow` › "Order of operations when the board is in use"):
```
design + breakdown (lead) → present to user → USER APPROVES registration   ← the gate
GET /projects/{id}/board ; GET /tags        → start/Review/Done column ids + area tag ids
# 1) Register the WHOLE approved backlog into To Do FIRST (dependency order, ≤8h each):
for each approved task:  POST /tasks  → lands in is_start (To Do), full description + checklist + branch + tag
# 2) THEN implement task-by-task, moving the card to mirror real state:
for each task (dependency order):           # one card at a time, in real time
  PATCH /tasks/{id}/move → is_in_progress ; POST comment "Started."   (the instant work begins — not before, not batched)
  … implement on the feature/<slug> branch off develop (git-workflow) …
  PATCH /tasks/{id}/move → Review ; POST comment   (the instant code is complete → tech-lead code review here)
  lead approves → tester verifies on develop:
    PASS → PATCH /tasks/{id}/move → is_done ; POST comment "Verified on develop → Done"
    FAIL → POST comment "<bug: which AC, repro, expected vs actual>" ; PATCH move back → in_progress
```
Key rule: a task's code is written **only after its card is In Progress**, and lead code review happens at **Review**, tester at **QA**, before **Done**. Every `move` is paired with a `comment` **at the real moment of the transition** so the card's timeline shows exactly when each step happened.

## End-to-end Mode 5 loop
```
use $TEAMFLOW_PROJECT_ID            → (or GET /projects to pick one)
GET /projects/{id}/board            → backlog + column ids/flags
GET /tags                           → area tag ids (Backend/Frontend/Tester/Devops)
for each task (dependency order):           # one card at a time, in real time
  PATCH /tasks/{id}/move → is_in_progress ; POST comment  (the instant work starts — move + comment together)
  … implement on a feature branch off develop (git-workflow) …
  POST  /tasks/{id}/comments                  (progress / QA notes — at each real step)
  PATCH /tasks/{id}/move → Review ; POST comment → is_done ; POST comment   (each move at the real moment, after tester passes on develop)
task came with files? → POST /tasks/{id}/files/upload  (multipart, one per file)
discovered new work? → POST /tasks  (gated + ≤8h; upstream first, then dependency_ids)
```

## End-to-end Mode 7 loop (review sweep)
```
use $TEAMFLOW_PROJECT_ID            → (or GET /projects to pick one)
GET /projects/{id}/board            → resolve the Review column id (the QA column between in-progress and is_done) + To Do (is_start) + Done (is_done) ids
for each task in the Review column (one by one):
  tester verifies the task against its acceptance criteria (+ security checks)
  PASS → PATCH /tasks/{id}/move → is_done             (Done)
         POST  /tasks/{id}/comments  "Verified: all acceptance criteria pass. → Done."
  FAIL → PATCH /tasks/{id}/move → is_start             (back to To Do)
         POST  /tasks/{id}/comments  "Rejected: <which AC failed, expected vs. actual, repro>. → To Do for fix."
re-read the board before each move (the Review list may have shifted)
```
No task authoring in Mode 7 — read/move/comment only. The fail comment must be specific enough to act on (name the failing criteria, not just "doesn't work").

## Safety checklist
- Token from env only; never printed or committed.
- Writes (`POST`/`PATCH`) only after the human gate (for registration) or as the genuine reflection of work state (Mode 5 / Mode 7).
- Re-read the board before a move (positions/columns may have changed under you).
- One transition per `move`; comment the *why* on every state change.
- Don't fabricate assignees/tags/columns — resolve real ids from the board; on `403`/`422`, read the error and correct, don't loop.
- **On Windows**: use the Bash tool, or invoke `curl.exe` (not the `curl` alias) and `$env:VAR` syntax in PowerShell — see the "Windows / PowerShell note" above. If a call silently returns nothing or fails with `401`, verify the env var actually expanded before retrying.
