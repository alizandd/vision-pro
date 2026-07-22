---
name: canvas-graphics
description: The team's standards for 2D Canvas and GPU-accelerated 2D graphics on the web — when to use canvas vs SVG/DOM, the render loop, performance, hit-testing/interaction, high-DPI, and libraries (PixiJS, Konva, p5, OffscreenCanvas). Always use this skill whenever the conversation involves the HTML Canvas, 2D rendering, data/particle visualization, custom drawing, games on canvas, or interactive graphics that aren't 3D. For 3D/WebGL use `threejs-3d`.
---

# 2D Canvas & accelerated 2D graphics

Goal: smooth, crisp, interactive 2D graphics that stay performant with many elements. Owned by the **frontend** specialist. For **3D/WebGL** use `threejs-3d`; for charts prefer a charting lib unless custom rendering is required. Pairs with `frontend-standards`.

## When to use canvas (vs SVG/DOM)
- **DOM/SVG**: few elements, need accessibility, CSS styling, or individually-addressable nodes (forms, icons, simple charts). Retained-mode, accessible by default.
- **Canvas (2D)**: many shapes/pixels, custom drawing, games, particle/data viz where per-node DOM would be too heavy. Immediate-mode — you own the redraw and there's no built-in accessibility, so provide a text/DOM fallback.
- **WebGL/GPU (PixiJS or raw)**: thousands of sprites, shaders, heavy compositing — when 2D canvas can't keep frame rate.

## Render loop
- Drive animation with a single **`requestAnimationFrame`** loop (never `setInterval` for rendering). Decouple update (state, use delta time) from draw; only redraw when something changed (dirty flag) for mostly-static scenes.
- Clear/redraw efficiently: clear only dirty regions when possible; batch state changes. Stop the loop when offscreen/tab hidden (`visibilitychange`, IntersectionObserver).

## Crisp rendering & sizing
- Handle **high-DPI**: set the canvas backing store to `cssSize * devicePixelRatio` and scale the context; cap DPR (~2) for perf. Re-handle on resize. Use integer/half-pixel coordinates to avoid blur on strokes.

## Performance
- Minimize state changes (`fillStyle`/`font`) and expensive calls (`shadow*`, per-frame gradients) — cache them. **Pre-render** static or repeated content to an offscreen canvas and `drawImage` it.
- Avoid per-frame allocations and string parsing. For heavy scenes use **OffscreenCanvas + a Web Worker** to render off the main thread, or move to **PixiJS/WebGL**. Layer multiple canvases (static background + dynamic foreground) to limit redraw.

## Interaction & hit-testing
- Canvas has no DOM nodes — implement hit-testing yourself: math/bounding boxes/spatial index, or a hidden "pick" buffer with unique colors per object. Libraries (Konva) provide event/hit-testing out of the box.
- Map pointer coords through DPR and canvas offset; support touch and pointer events.

## Libraries (pick per need)
- **Konva** — interactive 2D with a scene graph + events (diagrams, editors). **PixiJS** — GPU-accelerated 2D for games/lots of sprites. **p5.js** — creative coding/sketches/prototyping. Use raw canvas for small/simple needs.

## Accessibility & integration
- Always provide a non-canvas fallback (ARIA text, data table, or DOM layer) — canvas content is invisible to assistive tech. In React/Vue, wrap the canvas in a component, drive it via a ref, and clean up the rAF loop and listeners on unmount (`frontend-standards`).

## Output
Canvas/graphics code with the render loop, DPR handling, and cleanup in place, plus a note on the approach chosen (canvas vs SVG vs WebGL) and any library dependency.
