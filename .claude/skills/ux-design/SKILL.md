---
name: ux-design
description: The team's UX/product-design process — how the designer goes from a problem to implementable direction: user/context understanding, information architecture, user flows, wireframing, interaction & content design, usability and accessibility, and design critique/handoff. Always use this skill when designing a new product/feature that has no existing design, defining UX, structuring flows/IA, or producing a design spec. Pairs with `design-system` (the visual system) and `frontend-standards` (implementation).
---

# UX / product design process

Goal: design direction that solves the real user problem and is directly implementable — not decoration. Owned by the **designer** (engaged *only* when no design exists). This skill is the *process*; `design-system` is the *token/component system* the output plugs into.

## When engaged
- Only when there is **no existing design** to follow. If a design/Figma/established language exists, defer to it — the frontend implements as-is. The tech-lead decides this before bringing you in.

## The process
1. **Understand the problem & users**: who is this for, their goals, context of use, constraints, and the jobs-to-be-done. Capture assumptions explicitly; note what's unknown. Don't jump to screens.
2. **Information architecture**: define the content/structure — navigation model, hierarchy, grouping, naming. The IA decides findability before any pixels.
3. **User flows**: map the key task flows end-to-end (entry → steps → success), including decision points and error/empty/edge states. A flow per primary task.
4. **Wireframe / layout**: low-fidelity structure first — layout, hierarchy, and priority of elements per key screen, responsive (mobile-first). Validate the flow before visual polish.
5. **Interaction & content design**: states and transitions (default/hover/active/focus/disabled/loading/empty/error), micro-interaction intent, and **clear microcopy** (labels, empty states, errors, CTAs) — words are part of the design.
6. **Apply the visual system**: express the visual layer in `design-system` terms — tokens (color/type/spacing/radius/shadow) and component specs — so it's coherent and implementable, never one-off screens.

## Usability & accessibility (non-negotiable)
- Heuristics: visibility of system status, match to the real world, user control, consistency, error prevention, recognition over recall, clear feedback.
- **Accessibility by design**: WCAG-minded contrast, focus order and visible focus, target sizes, semantic intent, no color-only meaning, keyboard-operable. Design the a11y in — don't leave it for implementation to retrofit.
- Reduce cognitive load: progressive disclosure, sensible defaults, forgiving inputs, and obvious primary actions.

## Critique & handoff
- Self-critique against the user problem and heuristics before handing off; cut anything arbitrary. Keep a short **rationale** ("why this direction") so it's defensible, not taste-by-assertion.
- Deliver a structured **design spec** (Markdown): tokens, IA, flows, key screens, component specs + states, interaction/motion, accessibility notes, and rationale — ready for the frontend (via the tech-lead) and worth capturing as a design-direction ADR.

## Output
An implementable design spec the frontend can build directly, grounded in the user problem, expressed in `design-system` tokens/components, with accessibility and rationale included.
