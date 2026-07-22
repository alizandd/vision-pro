---
name: database-migrations
description: The team's standards for database design and migration management — schema design, safe migrations, indexing, and query optimization. Always use this skill whenever the conversation involves database schema, migrations, altering a table, indexes, or query optimization.
---

# Database and Migration Standards

## Golden rules
- **All schema changes via migrations** — no manual changes in any environment, especially production.
- Migrations must be **reversible** (a correct `down`) for rollback.
- Migrations atomic and small — one logical change per migration.

## Naming and structure
- Table naming: plural, snake_case (`order_items`).
- Columns: snake_case, clear (`created_at`, not `ts`).
- Foreign keys: `{singular}_id` (`user_id`) + a proper constraint.
- Standard timestamps (`created_at`, `updated_at`); soft delete (`deleted_at`) if needed.

## Safe migrations in production
1. **Back up the DB before any migration.**
2. Consider that large changes (on big tables) may lock them — if needed, use an online approach (multi-step: new column → backfill → switch).
3. Never drop a column directly while code still uses it — code first, then column (two deploys).
4. Run migrations only through the deploy pipeline (e.g. `migrate --force` in Laravel, `alembic upgrade`/`migrate` elsewhere), never manually in production.

## Indexing
- Index foreign keys and commonly filtered/sorted/joined columns.
- Composite indexes in the right order (left to right = most to least selective).
- Avoid over-indexing (slows writes).

## Query optimization
- Resolve N+1 with eager loading (e.g. `with()` in Eloquent, `select_related`/`prefetch_related` in Django, explicit joins in query builders).
- Use `EXPLAIN` for slow queries.
- Select only needed columns, not `SELECT *` on hot paths.
- Paginate large lists (api-conventions skill).

## Seeds and data
- Use seeders/fixtures for base/test data; no manual entry.
- Never put sensitive data in a committed seeder.
