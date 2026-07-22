---
name: api-conventions
description: The team's standard conventions for API design — naming, response structure, error handling, versioning, and the contract between backend and frontend. Always use this skill whenever the conversation involves designing an endpoint, JSON response structure, error format, API contract, or aligning backend and frontend on data shape. Not for internal server architecture/layering (that's `backend-architecture`) or the database schema itself (that's `database-migrations`).
---

# Team API Conventions

Goal: all team APIs share a predictable shape so the frontend doesn't have to guess and maintenance stays easy.

## Naming
- Resources plural and consistent kebab/snake: `/users`, `/order-items`
- Non-CRUD actions as a verb under the resource: `POST /orders/{id}/cancel`
- Query params for filter/sort/paginate: `?status=active&sort=-created_at&page=2`

## Response structure (uniform for all)
Success:
```json
{
  "data": { ... },        // or an array for a list
  "meta": { "page": 1, "per_page": 20, "total": 134 }  // lists only
}
```
Error:
```json
{
  "error": {
    "code": "VALIDATION_ERROR",
    "message": "A human/developer-readable message",
    "details": { "field": ["error message"] }   // optional
  }
}
```

## HTTP status
- 200 OK, 201 Created, 204 No Content
- 400 (bad request), 401 (unauthenticated), 403 (forbidden), 404, 422 (validation)
- 500 only for server errors; never for user/logic errors

## Versioning
- Prefix: `/api/v1/...`
- Breaking change = new version, not a change to v1

## Auth
- Bearer token (Sanctum/Passport for Laravel)
- Sensitive endpoints always behind authorization middleware

## Pagination
- Default `per_page=20`, cap `100`
- Always return `meta` with pagination info

## Contract between backend and frontend
- Before implementation, agree on the request/response shape (ideally in one OpenAPI/markdown doc).
- Backend documents it; frontend relies on it — no guessing.
- Any contract change must be communicated to the other side (via the tech-lead).

## Validation
- Backend always validates (never trust the frontend).
- 422 error messages should be per-field so the frontend can display them.

## Exposing tools to AI agents (MCP / A2A)
When an endpoint or service is meant to be consumed by an **AI agent** (not just a human frontend), prefer the open interop standards over bespoke wrappers. See `docs/references/agent-engineering/` (Day 2).
- **MCP (Model Context Protocol)** is the standard way to expose a tool/data source to an agent — build it once and any MCP-compatible agent can use it. Keep the same uniform request/response and error discipline as above; advertise a clear tool schema.
- **Consume before you build**, and prefer official/internal registries over unvetted public MCP servers. Don't pass real credentials to untrusted servers; never hardcode tokens (use env/secret manager).
- **Tool calls that change state need the same authZ and human-in-the-loop** as any sensitive endpoint (see `security`); default agent-facing data access to read-only and least privilege.
- For **agent-to-agent** delegation across services, **A2A** is the emerging standard (agent "capabilities card" + negotiation), distinct from MCP's tool access — reach for it only when a real cross-agent boundary exists, not for ordinary tool calls.
