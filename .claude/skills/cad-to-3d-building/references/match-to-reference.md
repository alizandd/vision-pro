# Match-to-Reference detailing (Phase 4.5)

Load this when a **reference model** (architect FBX/glTF, or any ground-truth 3D) must drive
the detailing of a CAD-built model — i.e. our model already exists and has to be snapped to
the reference feature-by-feature.

> **Standing rule — detail-complete to the reference.** When a reference model is given, the
> model must match it **exactly**, not just in massing/silhouette but in the fine detail:
> **window/door openings (count, position, size), glazing divisions/mullions, and trim** are
> matched, not approximated. "Close enough silhouette" is *not* done. Only the *look* (PBR
> materials/textures) comes from elsewhere (the look-standard render, Phase 6) — the
> reference's flat placeholder materials are never copied, but its **geometry, including every
> opening, is authoritative.**

Helper: `scripts/match_to_reference.py` (verified on the Roxborough Towns_BL_K reference).

## The loop: align → diff → punch-list → fix → re-diff

1. **Import + clean the reference.** FBX/glTF arrives with import baggage — for the
   Roxborough FBX: `scale 0.01` (cm→m) and `rotation (90°, 0, 180°)` (Z-up + yaw). Import,
   then **apply rotation + scale** (`transform_apply(rotation=True, scale=True)`) so datum
   queries read clean world coordinates. Put it in its own collection.

2. **Align 1:1 by datums, not bbox.** `align_reference(ref, model_objs, x, y, z)` translates
   the reference so three datums coincide with the model: **ground** (`z='min'`),
   **front plane** (`y='min'` when front faces −Y), **left corner** (`x='min'`). Aligning by
   bbox-center smears error across the whole model; aligning by real datums keeps the planes
   you measure against true. If the reference front faces +Y, flip the axis mode.

3. **Diff numerically.** `report(ref, model_objs)` returns:
   - `bbox_delta_m` — overall W/D/H gap (model minus ref).
   - `z_levels` — every horizontal datum (floor / sill / head / belt / eave / ridge) paired
     ref↔model with `delta_mm` and an `ok` flag (≤ `TOL_DATUM_M`), plus *missing in model* /
     *extra in model* rows.
   - `roof_pitch` — area-weighted degrees for ref vs model, `ok` if within `TOL_PITCH_DEG`.

4. **Diff visually.** `overlay_render(ref, model, view, path)` renders the reference as a
   translucent coloured **ghost over the solid model** (EEVEE ortho) from
   `front/back/left/right/top/iso`. Silhouette gaps (roof too tall, wall too wide, sill too
   high) jump out where the ghost pokes past the solid. Restores the reference's materials
   afterwards. Renders can outlast the MCP timeout → **poll the output file**.

5. **Turn the diff into a punch-list.** Each failing row/overhang = one concrete item:
   *"ridge −0.5 m"*, *"sill datum 0.485 m missing"*, *"eave overhang short 0.3 m"*,
   *"pitch 34.7° → 32.8°"*. Prioritise the big silhouette movers (roof, floor heights,
   footprint) before trim.

6. **Fix the named parts.** Edit the corresponding `Rox_Building` parts to the reference
   value — move the part, retype a box's Z span, change roof slope. Keep materials. Because
   parts are separated and named (`<unit>_<floor>_<type>_<index>`), each fix is local.

7. **Re-diff until tolerance.** Re-run `report()`; loop. **Done** when all datums ≤ 50 mm,
   roof pitch ≤ 2°, and every `overlay_render` view is silhouette-flush.

## Measuring a single combined reference mesh

The reference is usually **one mesh** with no per-part objects, so you can't select "the
roof object". Measure by **geometry query** instead (all in `match_to_reference.py`):

- **Z datums** — `z_datums()`: area-weighted clustering of horizontal-face centroids
  (`|normal.z| > 0.9`). Each cluster is a real building datum.
- **Wall planes** — `wall_planes()`: vertical faces (`|normal.z| < 0.1`) clustered by their
  facing axis offset → front/back/left/right plane positions.
- **Roof pitch** — `roof_pitch()`: `acos(|normal.z|)` over sloped faces, area-weighted.
- **Component isolation via material slots** — pass `mat_filter="roof"` (etc.) to restrict a
  query to faces in matching material slots. The reference's material slots are used here
  **only as a face selector** to isolate a component for measuring — this is *not* material
  work and does not change our PBR materials.

Degenerate (zero-area) faces in imported meshes are skipped automatically — they carry
garbage normals and would poison the clustering.

## Matching openings (windows / glass / doors)

The standing rule means every opening must match. Extract them from the reference and rebuild
ours to match — same count, position, size, and division pattern. `openings()` in the script:

1. **Filter** to the faces of one facade: vertical faces whose normal faces the facade
   direction (e.g. front = `n.y < -0.7`), optionally narrowed by `mat_filter` to a glass/door
   material slot.
2. **Island-cluster** them into discrete openings via face adjacency (each connected run of
   glass = one window). Returns each opening's facade-plane rectangle `{u0,u1,v0,v1}` (X/Z for
   a ±Y facade, Y/Z for a ±X facade) plus its centre and size.
3. **Diff against ours** — pair nearest openings; flag count mismatches, and any centre/size
   off by > ~50 mm. Missing openings (reference has one we don't) and extra openings (we have
   one the reference doesn't) are both failures.
4. **Rebuild to match** — reposition/resize our window/door parts (and re-cut the wall Boolean
   if an opening moved), keeping `make_window`'s frame + mullion-cross + recessed glass. Match
   the reference's **division pattern** (panes/mullions), not just the outer rectangle.
5. **Re-extract and re-diff** until counts match and every opening is within tolerance; confirm
   visually with a `front`/`right` `overlay_render` — glazing should sit dead-on under the
   ghost.

Run `openings()` per facade (front/back/left/right) — a single combined reference mixes all
four, so always constrain by facing direction first.

**When the reference is a dense, full-interior mesh (the common case).** `openings()` is
reliable only on a *clean* reference — one where glazing is a distinct material, or the
reference is just an exterior shell. A full architect FBX often has **interior geometry**
(rooms, partitions → thousands of front-facing interior faces) and **no glass material** (all
one slot), so material- and recess-based extraction is unreliable. In that case:

- **The 2D CAD elevation is the precise source for openings**, not the FBX. The drawing gives
  exact window/door positions and sizes; it is clean and dimensioned. Use `dxf_extract.py` on
  the elevation sheet and read the opening rectangles from the linework (the same elevation
  you blocked out from in Phase 3).
- **Use the FBX only to confirm 3D** — sill/head datums, reveal depth, mullion projection —
  not to count or place openings.
- Cross-check the rebuilt openings against the FBX with a `front`/`right` `overlay_render`.

So the precedence for openings is: **CAD elevation (exact 2D) → FBX (3D confirmation) →
overlay (final visual check).**

## Tolerances (Phase 4.5 Definition of Done)

| Check | Tolerance | In code |
|---|---|---|
| Horizontal datums (floor/sill/head/eave/ridge) | ≤ 50 mm | `TOL_DATUM_M` |
| Wall planes / footprint | ≤ 50 mm | `TOL_DATUM_M` |
| Roof pitch | ≤ 2° | `TOL_PITCH_DEG` |
| **Openings (windows/doors/glazing)** | **same count; centre & size ≤ 50 mm; division pattern matched** | `openings()` |
| Silhouette | visually flush in all `overlay_render` views | — |

## Gotchas

- **Apply rotation + scale before measuring** — otherwise every datum is off by the import
  scale/rotation and the diff is meaningless.
- **Align by datums, never bbox-center** — bbox alignment hides the very errors you're
  hunting (a too-tall model still "centers" fine).
- **Single-mesh reference** → select faces by `material_index` / normal, not by object.
- **Reference materials are placeholders** — flat colours, no PBR. Never copy them onto our
  model; they exist only to (a) isolate components for measuring and (b) ghost the overlay.
- **`overlay_render` swaps the reference's materials** for the ghost and restores them after;
  if a render is interrupted mid-call the reference may be left single-material — re-run or
  re-import to restore.
- **Renders outlast the MCP timeout** — render to a path and poll the file from the host.
- **`object.bound_box` goes stale** — after direct mesh edits / `transform_apply`, the cached
  bound box lies, which silently corrupts alignment (wrong anchor, a *false* "delta 0", a roof
  snapped to coordinates the walls never reached). **Always measure from evaluated vertices**
  (`obj.evaluated_get(depsgraph).to_mesh()`); `world_bbox()` in the script now does this. This
  one bit hard on the Roxborough run — the macro scale looked perfect on `bound_box` but the
  walls were ~1.5 m off in reality.
- **Snap walls and roof in the same coordinate frame.** Snapping the roof to *absolute*
  reference coords while the walls sit in slightly-off model coords leaves them misaligned.
  Fix the footprint (walls + frieze + base) and the roof against the *same* measured datums.
- **Dense full-interior reference** → don't trust auto opening-extraction; the FBX has interior
  walls (front-facing interior faces) and usually no glass material. Get exact openings from
  the **2D CAD elevation**; use the FBX only for 3D confirmation. (Roxborough run: 28 k
  front-facing faces, all one material, with big interior planes at Y≈1.34 m and 8.78 m.)
- **Roof must overhang the walls — check from the TOP, not just front/iso.** Don't scale the
  walls to the reference's *full* bbox: the full bbox includes the reference's own **roof eave
  overhang**, so the walls end up as wide as the roof and the eave vanishes (walls poke out past
  the roof — obvious only in a top view). Scale walls to the **wall footprint** (roof bbox minus
  ~0.4–0.6 m eave each side), and confirm with a **top `overlay_render`** that the roof
  overhangs on all sides. (Roxborough run: walls were scaled to the full bbox → roof read inset
  from above; fixed by enlarging roof+soffit to overhang ~0.4 m.) **Always add a top view to the
  overlay checks**, since silhouette-from-front hides eave/overhang errors.
