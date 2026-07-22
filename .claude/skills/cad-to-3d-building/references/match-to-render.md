# Match-to-Render — reaching the marketing-render look (Phase 6–7)

Load this when a **marketing render** is the look ground-truth and our final output must reach
it. This is the *look* counterpart to `match-to-reference.md` (which handles *geometry*). The
render team goes CAD → photoreal image; this is the same path in our Blender pipeline, with the
marketing image as the target you iterate against.

> **Standing rule — match the render.** When a marketing render is given, the **final render is
> not done until it matches that image** — same camera, materials, context, and light. Geometry
> fidelity (`match-to-reference`) gets the *shape* right; this gets the *look* right. Both are
> required for the deliverable. The reason: the client signed off on the *render*, so the render
> is the contract; "looks like a building" is not "looks like THIS building."

## The look loop: replicate camera → render → compare → tune → repeat
1. **Replicate the hero camera first** (see below) — you can't compare looks from a different
   angle. Match framing before touching materials.
2. **Render** (EEVEE for iteration, Cycles for the proof).
3. **Compare side-by-side** with the marketing image (and, where useful, an A/B overlay). Judge
   per element: brick tone, wood tone, roof, frames, glass, sky, landscaping, exposure.
4. **Tune** the offending element (material colour/roughness, light, exposure, context), not
   everything at once.
5. **Repeat** until each element reads like the target. Save the matched frame as the proof.

## Hero camera (architectural marketing shot)
- **Straight-on frontal** to the hero elevation, **centered**, building symmetric in frame.
- **Eye-level** (~1.6 m), camera level (no tilt) so **verticals stay vertical** — use a long
  lens (~85–135 mm equiv: low `lens` FOV / large distance) to kill converging verticals.
- Building fills ~60–70 % of frame height; foreground driveway/lawn leads in at the bottom.

## Material recipe (read from the K street render — adjust per project)
| Element | Look in the render | Build notes |
|---|---|---|
| Brick (walls + base) | **dark warm grey**, fine modular, visible mortar, matte | grey-brick albedo + brick Normal/Rough; rough ~0.8; base course slightly lighter/larger |
| Wood accent panels | **warm medium-brown** horizontal timber slats, satin | wood albedo, rough ~0.45, slat normal; **2 wide panels**, centre is glazing (per render) |
| Roof | **dark brown / charcoal asphalt shingle**, matte | shingle albedo + normal; rough ~0.85 |
| Window frames | **matte black**, slim | base (0.02,0.02,0.02), rough ~0.4 |
| Glazing | dark but **reflective + interior depth** (curtains/blinds visible), not flat black | low rough (~0.05), IOR 1.45, a faint interior card or brighter back face — avoid pure black |
| Garage doors | dark charcoal, flush, faint horizontal reveals | dark panel, rough ~0.5 |
| Entry doors | dark, with a small transom/sidelight | |

## Context / landscaping (the render's realism comes from this — don't skip it)
- **Lawn** (mown green) + **paver/concrete driveway** centred to the garages.
- **Clipped low hedges** along the façade; **flowering shrubs** (hydrangea) at the corners;
  **two planters** flanking the entries; **path bollard lights** along the drive.
- **Backdrop trees** (tall evergreen + deciduous) left and right to frame the building and hide
  the horizon seam.

## Lighting & sky
- Bright **daylight**, **soft sun** (slightly diffuse → soft eave shadows), **blue sky with
  soft white clouds**. Sun high and roughly frontal so the façade is evenly lit.
- Sky Texture `MULTIPLE_SCATTERING` + aligned Sun (see `materials-export.md`). Tune **exposure**
  under AgX, not light power.

## Post
- Subtle grade: natural white balance, lifted but not washed, saturated greens, light vignette.

## Done = matches the render
Per-element parity with the marketing image (brick/wood/roof/frames/glass tone + finish),
hero-camera framing reproduced, context + sky + light present, exposure matched. Save the
matched frame next to the marketing image as the proof. This is the **look** half of the DoD;
the **geometry** half is `match-to-reference.md`.
