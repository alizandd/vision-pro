---
name: vue-development
description: The team's standards for building Vue apps — Composition API + script setup, Vue 3.5 features, Nuxt 4 (SSR/Nitro), state with Pinia, server state with TanStack Query (Vue), composables, forms, performance, and testing. Always use this skill whenever the conversation involves Vue, SFCs (.vue), the Composition API, Pinia, or Nuxt. Pairs with `frontend-standards`, `api-conventions`, and `threejs-3d`/`canvas-graphics`.
---

# Vue development

Goal: Vue apps that are reactive, well-typed, and structured for scale. Owned by the **frontend** specialist; the cross-framework rules live in `frontend-standards`. Pairs with `api-conventions` (data shape) and `threejs-3d` / `canvas-graphics` for visuals.

## Stack (current baseline — verify with `tech-research`)
- **Vue 3.5** with the **Composition API** + `<script setup>` and **TypeScript**. Vite 7 build. Be aware of **Vapor Mode** (compile-time, vDOM-skipping rendering) for perf-critical components where supported.
- **Nuxt 4** for SSR/SSG/universal apps (Nitro engine, file-based routing, auto-imports); plain Vue + Vite + Vue Router for SPAs.
- **Pinia 3** for state; **Vitest** + Vue Testing Library for tests, Playwright for e2e.

## Components & composables
- SFCs with `<script setup>`; small, single-responsibility, typed props (`defineProps<T>()`) and events (`defineEmits`). Extract reusable logic into **composables** (`useX()`) — the Vue equivalent of hooks.
- Use `ref`/`reactive`/`computed`/`watch` deliberately; prefer `computed` over watchers for derived state. Avoid mutating props; one-way data flow with events up. Handle loading/empty/error states.

## State management
- **Pinia** for shared client state — typed stores with state, getters, and actions; one store per domain, composable and DevTools-friendly. Keep stores focused; don't dump everything global.
- **Server/async state** → **TanStack Query (Vue Query)** or Nuxt's `useFetch`/`useAsyncData` for caching, dedup, and background refresh — don't hand-roll fetch-into-ref everywhere or duplicate server data into Pinia.
- Local component state stays in the component (`ref`). Provide/inject for slow-changing config (theme/locale); avoid it for high-frequency updates.

## Data fetching & forms
- In Nuxt, fetch with `useAsyncData`/`useFetch` (SSR-aware) and call server routes/`server/api` for mutations and secrets. Centralize the API client; type to the backend contract (`api-conventions`).
- Forms with VeeValidate + a schema (Zod/Yup); show field-level and submit errors.

## Performance
- Route-level code splitting (async components, `defineAsyncComponent`); lazy-load heavy views. Use `v-once`/`v-memo` and proper `key`s; avoid unnecessary deep reactivity on large structures (`shallowRef`/`shallowReactive`). Leverage Nuxt SSR/payload optimization and mind bundle size.

## Output
Typed Vue/Nuxt code + a note on store shape (what's in Pinia vs server-state) and the data contract. Flag backend (endpoints) and devops (build/env, SSR hosting) dependencies via the tech-lead.
