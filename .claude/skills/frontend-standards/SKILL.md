---
name: frontend-standards
description: The team's cross-framework frontend standards — component structure, state strategy (server vs client), styling/Tailwind, design tokens, TypeScript, accessibility, responsive design, API integration, performance, and testing. The shared layer above the framework-specific skills. Always use this skill whenever building a component, UI, styling, state, or connecting the frontend to a backend. Pairs with `react-development`, `vue-development`, `canvas-graphics`, `threejs-3d`, `design-system`, and `api-conventions`.
---

# Team Frontend Standards (shared layer)

These rules apply to **every** frontend project regardless of framework. Framework-specific depth lives in `react-development` and `vue-development`; visuals in `canvas-graphics` (2D) and `threejs-3d` (3D); visual language in `design-system`.

## Component structure
- Small, single-responsibility, **reusable** components; one component = one job.
- **Separate logic from presentation** — logic in a custom hook (React) / composable (Vue), markup in the component.
- Explicit, **typed props** (TypeScript) with sensible defaults; validate inputs at the boundary.
- Co-locate each feature folder (component + style + test + hook/composable). Organize by feature, not by file type.

## State strategy (framework-agnostic rule)
- **Separate server state from client state** — the single most important decision:
  - **Server/async data** → a dedicated query/cache layer (TanStack Query / Vue Query / Nuxt `useAsyncData`). Don't copy it into a global client store.
  - **Shared client/UI state** → a store (Zustand/Redux Toolkit for React; Pinia for Vue).
  - **Slow-changing config** (theme, locale, auth user) → context/provide-inject.
  - **Local state** → component-local; lift only when genuinely shared. Avoid prop-drilling and avoid context for high-frequency updates.

## Styling
- **One approach per project** (Tailwind, CSS Modules, or CSS-in-JS) — never a mix. Tailwind is the team default for new work.
- **Tailwind v4** (4.3.x current): configure via the CSS-first config (`@theme`) and design tokens; centralize color/spacing/typography tokens (align with `design-system`). Extract repeated utility clusters into components or `@apply`d classes — don't copy-paste long class strings. Keep it responsive (mobile-first) and theme-aware (dark mode).
- No magic numbers/hex scattered in markup; tokens are the source of truth.

## TypeScript & quality
- TypeScript on by default; type props, API responses, and store shape. Avoid `any`. ESLint + Prettier enforced; framework lint rules (react-hooks / vue) on.

## Accessibility (always)
- Semantic HTML first; ARIA only to fill gaps. Labels for inputs, `alt` for images, sufficient contrast, visible focus, full keyboard navigation, correct heading order. Test with a screen reader for key flows.

## Responsive & states
- Mobile-first, fluid layouts; test across breakpoints. **Always handle loading / empty / error** (and offline where relevant) — all of them, every data-driven view.

## API integration
- All calls go through a **central API-client layer** — never scattered `fetch`. Type request/response to the backend contract (`api-conventions`); don't guess the shape — confirm via the tech-lead.
- Turn API errors into human-readable messages; handle auth/refresh centrally.

## Performance
- Code-split heavy routes/components; lazy-load below-the-fold and heavy visuals (3D/canvas). Minimize re-renders (stable props/selectors, correct keys, memo where it measurably helps). Virtualize long lists. Optimize images and **watch bundle size** (analyze it). Prefer SSR/RSC to ship less client JS where the framework supports it.

## Testing (see `testing-strategy`)
- Unit/component tests with the framework's testing library (Vitest + RTL / Vue Testing Library); e2e for critical flows (Playwright). Test behavior and the unhappy paths, not implementation details.

## Output
Component/UI code following these standards + a note on the data it needs (contract) and any backend/devops/design dependencies, routed through the tech-lead.
