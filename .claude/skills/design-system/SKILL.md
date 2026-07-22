---
name: design-system
description: The team's standard for defining a design system — design tokens, component specs, states, and accessibility — so design direction is consistent and directly implementable by the frontend. Use this skill whenever creating or extending a design system, defining tokens (color/type/spacing), specifying components, or producing a design spec for a project that lacks one.
---

# Design System Standard

Defines how the team expresses design as a reusable, implementable system. Used by the designer
to author direction and by the frontend to implement it. Tokens and component specs are the contract.

## Design tokens (the foundation)
- **Color**: semantic roles, not raw names — `primary`, `secondary`, `surface`, `background`,
  `text`, `muted`, `border`, `success`, `warning`, `error`. Provide hex + light/dark variants.
- **Typography**: font family/families, a type scale (e.g. xs→3xl), weights, line-heights, letter-spacing.
- **Spacing**: a consistent scale (e.g. 4px base: 4/8/12/16/24/32...).
- **Radius, shadow, border**: named tokens (sm/md/lg).
- **Breakpoints**: mobile-first set (e.g. sm/md/lg/xl).
- **Motion**: duration + easing tokens for consistent transitions.

Express tokens in a framework-neutral table so frontend can map them to Tailwind config / CSS
variables / theme object.

## Components
For each component, specify:
- **Anatomy**: parts and structure.
- **Variants**: e.g. primary/secondary/ghost; sizes sm/md/lg.
- **States**: default, hover, active, focus, disabled, loading, error, empty.
- **Usage rules**: when to use / not use; do's and don'ts.
- **A11y**: role, label, focus order, contrast, target size.

## Accessibility (baseline)
- WCAG AA contrast for text and essential UI.
- Visible focus states; full keyboard operability.
- Adequate touch targets; respects reduced-motion.

## Hand-off
- Deliver as a Markdown **design spec** (tokens table + component specs + rationale).
- Align with the `frontend-standards` skill: centralized tokens, small reusable components.
- Capture the chosen visual direction as an ADR (`docs/adr/`) so it's a recorded decision.

## Boundary
- This skill is for projects **without** an existing design. If a design/Figma/system already
  exists, that is the source of truth — implement it as-is rather than re-deriving tokens.
