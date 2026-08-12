---
name: blender
description: The team's standards for using Blender as the authoring tool — modeling/sculpting/UV/shading workflow, Geometry Nodes, glTF/FBX export for engines and the web, and Python (bpy) automation/add-ons. Always use this skill whenever the conversation involves Blender, .blend files, the bpy API, a Blender add-on/script, Geometry Nodes, or exporting assets from Blender. Pairs with `3d-modeling` for asset standards.
---

# Blender (authoring + automation)

Goal: a clean, repeatable Blender workflow that produces engine/web-ready assets and automates the boring parts with Python. Owned by the **3d-artist**; the asset *standards* live in `3d-modeling` — this skill covers the *tool*. Lean on `engineering-principles` and `git-workflow`.

## Stack (current baseline — verify with `tech-research`)
- **Blender 5.2 LTS** (July 2026, supported to July 2028) — the current production target; 4.5 LTS only for pipelines not yet migrated off it. Pin the Blender version per project: `bpy` API breakage across majors is the usual cause of a broken add-on. The built-in **glTF 2.0 I/O** exporter is the primary delivery path (numpy-accelerated, supports Geometry Nodes instances and PBR material extensions); FBX where an engine expects it.
- Materials authored with the **Principled BSDF** map directly to the glTF metal/rough PBR model.

## Authoring workflow
- Keep the scene tidy for export: **apply transforms** (rotation/scale), set a sensible origin/pivot, real-world units/scale agreed with the target (see `3d-modeling`), and consistent object/material naming.
- Follow `3d-modeling` for topology, UVs, and texturing. Use modifiers non-destructively, then apply deliberately before export. Use collections to organize and to drive export selection.
- **Geometry Nodes** for procedural/parametric content; it exports as instances via glTF — verify the result in the target.

## Export discipline (to engines / web)
- Export **only what's needed** (selection/collection), with correct axes (+Y up for glTF), applied modifiers, and the right material/texture settings. Pack or export textures consistently; bake high-poly detail to normal/AO maps.
- Always validate the exported asset in the **actual target** (Three.js/Unity/Unreal viewer) — scale, orientation, normals, materials — not just Blender's viewport.

## Python (bpy) automation & add-ons
- Script repetitive pipeline steps with the **`bpy` API**: batch import/normalize/export, consistent naming, validation passes (check scale, n-gons, missing UVs), and one-click export presets. This is real code — apply `engineering-principles`.
- Structure add-ons properly (`bl_info`, operator/panel classes, register/unregister); keep logic in plain functions that are testable outside the operator. Pin/document the Blender version an add-on targets (the API changes across releases).
- Run headless in CI with `blender --background --python script.py` for automated conversions/exports (coordinate with devops via `cicd-pipeline`).

## Security & hygiene
- Treat downloaded `.blend` files and add-ons as untrusted — they can contain auto-running Python; review before enabling. Don't run unknown scripts against project assets.
- Version `.blend`/binary source with **Git LFS**; keep exported runtime assets and heavy source organized and separate (coordinate via `git-workflow`).
