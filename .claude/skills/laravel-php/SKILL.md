---
name: laravel-php
description: The team's standards for modern PHP and Laravel — project structure, Eloquent & the data layer, validation, services/actions, queues & events, API building, testing (Pest/PHPUnit), security, and performance. Always use this skill whenever the conversation involves PHP, Laravel, Eloquent, Artisan, Blade, a FormRequest, a migration, a queued job, or building/structuring a Laravel app or API. Pairs with `backend-architecture`, `api-conventions`, `database-migrations`, and `wordpress-setup`.
---

# Laravel / modern PHP

Goal: Laravel apps that follow framework conventions, stay thin where it matters, and are secure and well-tested. Owned by the **backend** engineer; the architectural rules live in `backend-architecture`, the HTTP contract in `api-conventions`, schema in `database-migrations`.

## Stack (current baseline — verify with `tech-research`)
- **Laravel 12.x** on **PHP 8.2–8.4** (8.4 supported; hold off on 8.5 until the ecosystem catches up). Use typed properties, enums, readonly, constructor promotion, and match expressions — modern PHP, not PHP-5-isms.
- **Composer** for dependencies; follow **PSR-12** + Laravel conventions. Pint for formatting, PHPStan/Larastan for static analysis.
- **Pest** as the default test framework for new work (PHPUnit where the team already standardized on it).

## Structure & layering
- **Thin controllers**: business logic lives in **service classes** or single-purpose **Action/Job** classes — never in controllers or models.
- **Validation in FormRequest** classes (not inline in controllers); authorize there too. Return typed **API Resources** (`JsonResource`) for responses — don't echo Eloquent models raw.
- Use the container/DI and contracts; bind interfaces in service providers. Config via `config/*` + `.env` — never call `env()` outside config files.

## Eloquent & the data layer
- **Eloquent over raw SQL** for the common path; drop to the query builder/raw only for genuine performance needs. Prevent **N+1** with eager loading (`with`) and detect it with `Model::preventLazyLoading()` in non-production.
- Guard mass assignment (`$fillable`/`$guarded`); cast attributes (`casts()`), use enums for status fields. Migrations are the only way schema changes (`database-migrations`); never edit the DB by hand.
- Wrap multi-step writes in `DB::transaction()`. Use scopes, accessors/mutators, and relationships idiomatically; avoid fat models with business workflows — push those to services.

## Queues, events & scheduling
- Offload slow/external work to **queued jobs** (Redis/database driver). Jobs: pass **IDs not models**, set `$tries`/`backoff`/`retryUntil`, make them idempotent, handle `failed()`. Run **Horizon** (Redis) and monitor; Supervisor restarts workers.
- Use **events/listeners** to decouple side effects; the **scheduler** (`schedule:run` via one cron entry) for recurring tasks. Cache with tags/TTLs and explicit invalidation.

## APIs & auth (see `api-conventions`, `security`)
- Build APIs with resource controllers + API Resources; version and shape per `api-conventions`. Auth via **Sanctum** (SPA/tokens) or **Passport** (full OAuth) as fit.
- Security: Eloquent/parameter binding (no string-built SQL), `$fillable` against mass assignment, CSRF for web forms, Laravel **policies/gates** for authz, `Hash` for passwords, signed/expiring URLs for sensitive links. Validate and rate-limit everything public.

## Testing (see `testing-strategy`)
- **Pest** feature tests hitting routes (`RefreshDatabase`), unit tests on services. Use **factories** for data, fake mail/queue/storage/HTTP (`Mail::fake()`, `Queue::fake()`, `Http::fake()`). Cover authz and validation failures, not just success.

## Performance
- Eager-load, cache expensive reads, queue heavy work. In production run `config:cache`, `route:cache`, `view:cache`, `event:cache`; use OPcache. Profile with Telescope (non-prod)/Debugbar before optimizing.

## Output
Laravel code in proper layers (controller → FormRequest → service → Eloquent → API Resource) + the API contract and migration notes. Flag devops dependencies (queue/cache drivers, Horizon, scheduler cron) via the tech-lead.
