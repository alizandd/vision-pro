---
name: cad-to-3d-building
description: Turn architectural CAD (AutoCAD DWG/DXF plans & elevations, or a CAD-exported glTF/FBX) plus a texture library into a clean, real-world-scale, PBR-textured, render-ready building in Blender — delivered as a web glTF (*_3JS) and a photoreal render proof. Use when ingesting CAD/blueprints, calibrating drawing units (inch/mm→m), modelling a building to elevation datums, texturing brick/foundation/roof/wood/glass, lighting an architectural render, or exporting a building model for web/render. Drives Blender via the Blender MCP. NOT for non-architectural assets or general modelling (use `blender`/`3d-modeling`), and NOT for writing the Three.js scene that loads the result (use `threejs-3d`).
---

# CAD → 3D Building (Blender, MCP-driven)

Bridge a **CAD file + a texture library** to a building that matches **two** references at
once: a *geometry/organization* standard (a clean reference model like `SS_Building.fbx`)
and a *look* standard (a marketing render). Delivers a web `*_3JS.glb` + a render proof.

This skill is the runbook; bundled `scripts/` carry the verified code. When a project
adopts this pipeline it should capture the full rationale and worked example as a project
doc (`docs/pipeline/CAD-to-3D-Building-Pipeline.md`) plus an ADR, kept alongside its render
proofs — those artifacts are project-specific and live in the consuming project, not here.

> **The fidelity bar (default for every build).** When a reference is given, the output must
> be **detail-complete** — windows, doors, glazing divisions/mullions, and trim match the
> reference *exactly* (count, position, size), not just the silhouette/massing. "Close-enough
> massing" is not done. The reason: a building reads as wrong the instant its openings are off,
> so partial fidelity fails the client even when the shape is right. The precise source for
> openings is the **2D CAD elevation** (clean, dimensioned); the 3D reference confirms depth;
> an overlay confirms the result. Massing-only is acceptable *only* if the user explicitly
> downgrades the scope. See Phase 4.5 and `references/match-to-reference.md`.
>
> **Two ground-truths, two halves of done.** A build is judged against **both**: the *geometry*
> reference (shape + openings → `match-to-reference`) **and** the *look* — the **marketing
> render**, the client's signed-off contract for materials, context, light, and camera
> (→ `match-to-render`, Phase 7). Done = it matches the render, not merely "looks like a
> building." The render team reaches that image from the same CAD; this skill is how we reach it.

## When you start
Catalogue inputs first — it decides everything:
- **CAD**: 2D `.dwg/.dxf` (plans+elevations) → model from scratch; or 3D `.gltf/.fbx`
  (already geometry) → **cleanup** pass instead of block-out.
- **Textures**: usually *split* — detail maps (Normal+Rough, often no albedo) in one set,
  product **albedos** in another. You combine them (colour from one, surface from the other).

## The phases (drive Blender via MCP `execute_blender_code`)

1. **Calibrate units.** Blender → Metric/Meters. Read DXF header `$INSUNITS/$LUNITS/
   $MEASUREMENT`; derive the scale factor (inches ⇒ ×`0.0254`). Write it down.
2. **Ingest CAD as a backdrop.** Blender 5.x has **no DXF importer** — parse it with
   `scripts/dxf_extract.py` (extracts building-layer LINE/LWPOLYLINE, clusters the sheet
   into individual views, isolates one elevation, writes metre-scale JSON). Build it as an
   edge mesh; to make it visible, **convert to curve + bevel** (edge meshes don't render).
   Park the job at an X offset so it never overlaps a reference at the origin.
3. **Block-out** masses to datums read off the linework (floor/eave/ridge Z levels, wall X).
   bmesh boxes (front face `Y=0`, thickness `+Y`). *(3D input: re-origin/scale/normals
   instead.)*
4. **Detail** to the reference bar: foundation course, brick wall (Boolean-EXACT window
   cuts), belt course, windows (frame + mullion cross + recessed glass), wood accent panel,
   eave soffit+fascia, sloped roof.
4.5. **Match-to-Reference (detail-complete) — only when a reference *model* is the
   ground-truth.** When an architect FBX/glTF (or any 3D reference) is given, the standing
   rule is: **the model must match the reference exactly — not just massing, but the fine
   detail.** Window/door openings (count, position, size), glazing divisions/mullions, and
   trim are matched to the reference, not approximated. Run the **align → diff → punch-list →
   fix → re-diff** loop with `scripts/match_to_reference.py`: import + **apply rotation/scale**,
   `align_reference` by datums (ground + front plane + corner, *not* bbox-center), then
   `report()` (numeric datum/pitch diff), `openings()` (extract every window/door rectangle
   per facade from the reference), and `overlay_render()` (ghost-over-solid). Fix the named
   parts to the reference — massing AND openings — looping until datums ≤ 50 mm, pitch ≤ 2°,
   **and every opening matches in count and within ~50 mm in position/size**. PBR materials
   stay sourced from the look reference (the reference's flat placeholders are never copied).
   See `references/match-to-reference.md`. (Skip only when CAD plans/elevations are the sole
   authority — i.e. no reference model exists.)
5. **Organize** like the reference: a `Move` parent empty, collections, and the
   `<unit>_<floor>_<type>_<index>` naming (glazing in its own `FG` group, one glass mat).
6. **Texture (PBR).** Principled BSDF; combine libraries. Normal/Rough = **Non-Color**,
   albedo = sRGB. Use the **headless box-UV** helper (real-world tiling + exportable UVs);
   never box-projection-on-Object-coords if you need a glTF (won't export).
7. **Light & render — match the marketing render.** The marketing render is the **look
   ground-truth**; the final image is not done until it matches it. Replicate the **hero
   camera** (straight-on, eye-level, long lens so verticals stay vertical, centered), build the
   **material palette read from the render** (e.g. dark grey brick / warm wood / dark shingle /
   black frames / reflective glazing), and add the **context that sells it** (lawn, paver drive,
   clipped hedges, corner shrubs, entry planters, backdrop trees, bollard lights). Sky Texture
   `MULTIPLE_SCATTERING` + aligned sun; Cycles 64–96 + denoise; tune **exposure** (~−2 under
   AgX), not light power. Then run the **look loop**: render → compare side-by-side with the
   marketing image → tune the offending element → repeat until per-element parity. Render to a
   path and **poll the file** (renders outlast MCP timeouts). See `references/match-to-render.md`.
8. **Export + validate.** Bake any procedural material to a UV image first. Triangulate via
   modifier + `export_apply=True` (fixes tangents). Export the building collection,
   `export_yup=True`. Downscale textures ≤1024 (KTX2/Draco for production). **Re-import the
   GLB** and assert mesh/material counts + bbox/orientation.
9. **QA + docs.** Run the DoD checklist; update ADR/tasks; save a packed `.blend`.

## Bundled resources
- `scripts/dxf_extract.py` — verified DXF parser + clustering (`python3 dxf_extract.py in.dxf out.json`).
- `scripts/blender_pipeline.py` — verified `bpy` helpers: `make_box`, `bool_diff`,
  `make_window`, `box_uv`, PBR material builder, sky/sun, bake, export+validate.
- `scripts/match_to_reference.py` — verified Phase-4.5 helpers: `align_reference` (datum
  snap), `report` (numeric datum/wall/pitch diff), `z_datums`/`wall_planes`/`roof_pitch`
  (single-mesh geometry queries), `overlay_render` (ghost-over-solid diff).
- `references/dxf-ingest.md` — DXF internals, layer selection, clustering, backdrop tricks.
- `references/match-to-reference.md` — the align→diff→fix loop, measuring a single combined
  reference mesh, tolerances, and reference-matching gotchas.
- `references/match-to-render.md` — the look loop: hero camera, the material recipe read from
  the marketing render, context/landscaping, lighting, and per-element parity check.
- `references/materials-export.md` — material plan table, UV/colour-space rules, bake & glTF
  export options, size optimization, validation.

## Definition of done
Real metric scale · parts separated + named like the reference · PBR materials that match
the look · render proof · valid `*_3JS.glb` (`+Y` up, UV textures, triangulated, optimized,
re-imports clean) · docs updated. *(If a reference model drove Phase 4.5 — the model is
**detail-complete to the reference**: all horizontal datums ≤ 50 mm, roof pitch ≤ 2°, every
`overlay_render` view silhouette-flush, and **every window/door/glazing opening matches the
reference in count and within ~50 mm in position and size**.)* *(If a marketing render is the
look standard — the **final render matches it**: hero camera reproduced, per-element material
parity (brick/wood/roof/frames/glass), context + sky + light present, exposure matched; matched
frame saved beside the marketing image. See Phase 7 / `references/match-to-render.md`.)*

## Gotchas that will bite (each hit & solved in the worked example)
- Drawing units in **inches**; sheet `$EXTMIN/MAX` is the whole layout, not one building.
- DXF importer missing in 5.x → parse it; edge meshes render blank → curve+bevel.
- `NISHITA` enum gone → `MULTIPLE_SCATTERING`. Render washed out → drop exposure.
- Box/procedural materials **don't export** to glTF → UV-map or bake.
- Boolean cuts → n-gons → tangent warning → triangulate on export.
- MCP request times out while Cycles keeps rendering → poll the output file.
- Imported reference FBX/glTF carries scale (e.g. `0.01` cm→m) + rotation (e.g. `90°,0,180°`
  Z-up) → **apply rotation/scale before measuring** or every datum is wrong.
- Match-to-Reference: align by **datums, not bbox-center** (bbox hides the error); a
  single-mesh reference → select components by `material_index`/normal, not by object; never
  copy the reference's placeholder materials onto our model.
- **`object.bound_box` goes stale** after mesh edits / `transform_apply` → measure datums from
  **evaluated vertices** (`evaluated_get(depsgraph).to_mesh()`), or alignment silently lies
  (false "delta 0"). Snap walls + roof in the **same** coordinate frame, not one to absolute
  reference coords and the other to model coords.
