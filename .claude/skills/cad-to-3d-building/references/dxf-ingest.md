# DXF / CAD ingest (details)

Load this when the input is 2D AutoCAD (`.dwg`/`.dxf`) and you need it in Blender as a
1:1 backdrop to model against.

## DWG vs DXF
Blender reads neither `.dwg` nor (in 5.x) `.dxf` natively. If you only have `.dwg`,
convert to `.dxf` first (ODA File Converter, or any CAD that exports DXF). The Roxbrough
job shipped both — we used the `source/*.dxf`.

## Why we parse instead of import
- Blender 5.1: `bpy.ops.import_scene.dxf` exists as a stub but is **not registered**
  ("could not be found"). The old `io_import_dxf` add-on was dropped.
- A real sheet is a mess for geometry: dimensions, leaders, hatching, title block, and
  **multiple views** (front/rear/side elevations, sections) spread across a large layout.
  Importing it whole gives unusable soup.

So `scripts/dxf_extract.py` parses the ASCII DXF and keeps only what helps.

## DXF structure cheat-sheet
- File is alternating lines: a **group code** then its **value**.
- Header vars live in `SECTION/HEADER`; entities in `SECTION/ENTITIES`.
- Units: `$INSUNITS` (1=inch, 4=mm, 6=m), `$LUNITS` (4=architectural ⇒ inches),
  `$MEASUREMENT` (0=imperial, 1=metric).
- Entity layer = group code **8**. `LINE` = start `10/20`, end `11/21`.
  `LWPOLYLINE` = repeated `10/20` vertex pairs.
- **Roxbrough values:** `LUNITS=4, INSUNITS=1, MEASUREMENT=0` ⇒ inches ⇒ × `0.0254`.

## Which layers to keep
Building linework only. Roxbrough's useful layers: `BLDG` (443 segs), `FOOTING`,
`A-DOORS`, plus `GRADES`/`GRID` for datums. Drop `DIM`, `TEXT`/`MTEXT`, `HATCH`,
`DEFPOINTS`. The script's `KEEP_LAYERS` encodes this (falls back to all segments if a
drawing uses non-standard layer names — inspect and extend the set).

## Isolating one view (clustering)
The sheet holds many drawings. The script bins segment endpoints into a 1 m grid and
**flood-fills** (8-connectivity) into connected components, then keeps components whose
bbox is building-shaped (height 7–16 m, width 4–45 m) and returns the densest.
- Roxbrough: 44 components → picked a **12.94 × 13.08 m** front elevation, 332 segments
  (the rest were other elevations, sections, and detail callouts).
- If you get the wrong cluster, widen/narrow `--minh/--maxh`, or print all candidates and
  pick by index.

## Building the backdrop in Blender
- Map drawing `(x, y)` → world `(X, Z)` with front face at `Y=0` (elevations are vertical).
- Create an **edge mesh** (`from_pydata(verts, edges, [])`).
- **Edge-only meshes don't render** (EEVEE/Cycles shade surfaces). To see it:
  `object.convert(target='CURVE')` then `data.bevel_depth ≈ 0.03`. (A *Wireframe modifier
  needs faces and will produce nothing on an edge mesh.) For a viewport-only guide you can
  skip the curve and just rely on `show_in_front`.
- Park the whole job at an **X offset** (we used +25 m) so it never overlaps a reference
  model sitting at the origin.

## Reading datums for modelling
- **Floor/eave/ridge Z levels:** bucket near-horizontal segments by Z, weighted by length.
  Roxbrough: strong lines at **Z≈5.2** (floor), **Z≈10.4** (eave), plus ridge near top.
- **Wall/opening X positions:** bucket near-vertical segments by X. Roxbrough: corners at
  the building edges, mullions/openings between.
- These numbers drive Phase 3 block-out so the model sits on the real CAD.

## If the input is already 3D (glTF/FBX)
Skip all of the above: `import_scene.gltf` / `import_scene.fbx` work natively. Then run a
**cleanup** pass — set origin, apply/derive correct scale (check a known dimension),
recalculate normals, re-organize to the naming convention, and re-link or rebuild
materials (FBX often references external textures that are missing — that's exactly why a
reference FBX can render grey).
