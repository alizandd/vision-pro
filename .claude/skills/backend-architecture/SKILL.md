---
name: backend-architecture
description: The team's standard for designing server-side applications across stacks (PHP/Laravel, Node.js, Python) — layering, domain modeling, auth/authz, validation, caching, queues/background jobs, transactions, error handling, observability, and performance. Always use this skill whenever designing a server/API, structuring backend code, modeling a domain, or deciding how server-side concerns (auth, caching, jobs, scaling) fit together. Stack-spanning; pairs with `laravel-php`, `api-conventions`, and `database-migrations`.
---

# Backend / server architecture

Goal: server applications that are correct, secure, observable, and extensible — the same architectural discipline regardless of language. Owned by the **backend** engineer. Pairs with `laravel-php` (PHP depth), `api-conventions` (the HTTP contract), `database-migrations` (schema), and `security`.

## Layering (the core rule)
- **Thin controllers/handlers → services (domain/use cases) → repositories/data access**. Controllers only translate HTTP ↔ domain; never put business logic, queries, or external calls in them.
- Keep the domain stack-agnostic: business rules in plain classes/functions that don't import the framework. Frameworks are delivery mechanisms, not the architecture.
- Inject dependencies (interfaces/contracts) — no `new` of concrete infrastructure inside the domain, no static/global state. This is what makes it testable and swappable.
- Validate at the edge (request objects/DTOs); the domain receives already-valid, typed input.

## Stacks (pick per fit — see the backend agent)
- **PHP/Laravel** — first-class; see the dedicated `laravel-php` skill for depth.
- **Node.js** (NestJS for structured DI/modules, Express/Fastify for lean services) — idiomatic TypeScript, typed DTOs (zod/class-validator), async/await everywhere, no unhandled promise rejections.
- **Python** (FastAPI default for new APIs; Django where the batteries help) — type hints + Pydantic models, dependency-injection via FastAPI, async where I/O-bound.
- Default to the project's existing stack; justify any deviation in an ADR.

## Runtime currency (verify with `tech-research` — versions move)
- **Node.js 24 is Active LTS**; 22 is in maintenance. Node 26 becomes LTS in October 2026, and from then Node moves to **one major per April, LTS every October, with every release an LTS** — pin the major in `.nvmrc`/Docker and upgrade deliberately.
- **Python 3.14** is the target for new services — **free-threaded (no-GIL) builds are officially supported** (PEP 779), with a ~5–10% single-thread cost; use them only where real parallelism pays for it. 3.15 lands October 2026.
- **PHP**: see `laravel-php` (8.4 default, 8.5 stable, 8.2 out of security support end of 2026).

## Auth & authorization (see `security`)
- Authentication (who) separate from authorization (what they may do). Centralize authz in policies/guards/middleware — never scatter `if role ==` through handlers.
- Stateless APIs: short-lived access tokens (JWT/opaque) + refresh; rotate and revoke. Hash passwords with bcrypt/argon2. Enforce least privilege on every endpoint.

## Data, transactions & consistency
- Wrap multi-write operations in **transactions**; make external side effects idempotent. Avoid N+1 (eager-load); index for real query patterns (see `database-migrations`).
- Don't leak the persistence model into the API — map entities → response DTOs (`api-conventions`).

## Caching, queues & background work
- **Cache** read-heavy/expensive data (Redis); define TTLs and explicit invalidation — stale cache is a bug source. Cache-aside by default.
- Push slow/external work (email, image processing, webhooks, third-party calls) to **queues/background jobs**. Jobs must be **idempotent and retryable**; pass IDs, not serialized models; set retry/backoff and a dead-letter path; monitor workers (Horizon/Supervisor/equivalent).

## Errors, resilience & observability
- Consistent error handling: domain errors → mapped HTTP responses (`api-conventions`); never leak stack traces/secrets to clients. Fail closed on auth.
- Timeouts, retries with backoff, and circuit-breaking on external calls. Rate-limit public endpoints.
- **Structured logging** (correlation/request IDs), metrics, and tracing from day one — no PII/secrets in logs. Health/readiness endpoints for the platform (coordinate with devops via `app-deploy`/`cicd-pipeline`).

## Performance & scale
- Measure before optimizing (profile real endpoints). Design stateless so it scales horizontally; keep session/state in Redis/DB, not memory.
- Paginate list endpoints; stream large responses; batch where it cuts round-trips.

## Testing (see `testing-strategy`)
- Unit-test the domain/services in isolation (mock repositories/clients); integration-test the data layer and the HTTP contract. Cover auth and the unhappy paths, not just the happy one.

## Output
Server code in clean layers + the API contract (`api-conventions`) and a one-line stack rationale. Flag dependencies on devops (env, services, queues, cache) and frontend (data shape), routed through the tech-lead.
