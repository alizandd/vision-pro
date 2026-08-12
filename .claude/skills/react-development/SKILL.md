---
name: react-development
description: The team's standards for building React apps — components/hooks, React 19 features, Next.js (App Router), state management (server state vs client state, TanStack Query, Zustand, Redux Toolkit, Context), data fetching, forms, performance, and testing. Always use this skill whenever the conversation involves React, JSX/TSX, hooks, Next.js, or a React state/data-fetching decision. Pairs with `frontend-standards`, `api-conventions`, and `threejs-3d`/`canvas-graphics`.
---

# React development

Goal: React apps that are composable, correctly separate server vs client state, and stay fast. Owned by the **frontend** specialist; the cross-framework rules live in `frontend-standards`. Pairs with `api-conventions` (data shape) and `threejs-3d` / `canvas-graphics` for visuals.

## Stack (current baseline — verify with `tech-research`)
- **React 19** (19.2.x) with **TypeScript**. Function components + hooks only (no classes). The **React Compiler is stable (v1)** — enable it and drop manual `useMemo`/`useCallback` noise; still write render-pure components. 19.2 adds `<Activity>`, `useEffectEvent`, and `cacheSignal`.
- **Next.js 16 (App Router)** for SSR/SSG/RSC apps — 16.2.x is the LTS line; **Next.js 15 goes end-of-support on 2026-10-21**, so plan the 15 → 16 upgrade now. Security note: the May 2026 release patched 13 advisories (middleware bypass, SSRF, cache poisoning, XSS) — never run below 15.5.18 / 16.2.6. Vite + React for SPAs. Know **Server vs Client Components** — keep `"use client"` at the leaves, fetch on the server where possible, use Server Actions for mutations in Next.
- Build/lint/test: Vite or Next, ESLint (react-hooks rules), Vitest + React Testing Library, Playwright for e2e.

## Components & hooks
- Small, single-responsibility, typed components; logic extracted into **custom hooks**. Presentational vs container separation; co-locate feature folders (component + hook + test).
- Follow the rules of hooks; correct dependency arrays. Prefer derived state over duplicated state; key lists correctly. Use `Suspense` + error boundaries for async UI; handle loading/empty/error always.

## State management (the key decision)
- **Separate server state from client state** — this is the rule that keeps React apps sane:
  - **Server/async state** → **TanStack Query** (caching, retries, pagination, background refresh, invalidation). Do **not** copy fetched data into Redux/Zustand/Context.
  - **Shared client/UI state** → **Zustand** (lightweight) for small–medium apps; **Redux Toolkit** for large/enterprise apps with many contributors and strict patterns.
  - **Slow-changing config** (theme, locale, auth user) → **Context**.
  - **Local state** → `useState`/`useReducer`. Keep it local; lift only when genuinely shared.
- Avoid prop-drilling (compose components or use a store/context). Avoid Context for high-frequency updates (it re-renders consumers).

## Data fetching & forms
- Centralize the API client; in Next, prefer server-side fetching + Server Actions. Type request/response to the backend contract (`api-conventions`) — don't guess.
- Forms with **React Hook Form** + a schema validator (Zod) shared with the API where possible; show field-level and submission errors.

## Performance
- Code-split heavy routes/components (`lazy`/dynamic import). Avoid unnecessary re-renders (stable props, selectors in Zustand, `memo` where it measurably helps). Virtualize long lists. Mind bundle size and use RSC to ship less client JS.

## Output
Typed React/Next code + a note on which state tool handles what (server vs client) and the data contract it expects. Flag backend (endpoints) and devops (build/env) dependencies via the tech-lead.
