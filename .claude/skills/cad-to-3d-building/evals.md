# cad-to-3d-building — eval coverage

Documented eval cases (this repo uses checklist-style evals, not a harness). A change to the
skill must still satisfy all four conditions in `skill-authoring`. Re-check these when editing.

Tier: **action-allowed** (drives Blender, writes files/exports) → needs sustained success +
the user gate on scope downgrades, not one lucky pass.

## Trigger (should fire / should not)
Positive — must load this skill:
- "Turn this DWG/DXF (or CAD-exported FBX/glTF) into a textured building in Blender."
- "Here's the architect's reference model — make our model match it exactly."
- "Calibrate the drawing units and block out the building to the elevation datums."

Negative — must NOT load this skill (route elsewhere):
- "Write the Three.js scene that loads this GLB." → `threejs-3d`.
- "Model a chair / a non-architectural asset." → `blender` / `3d-modeling`.
- "Optimize this glTF's textures for the web only." → `threejs-3d` / general Blender.

## Execution (correct output across the input range)
- **2D CAD input** → metric scale (units calibrated), block-out to datums, detailed, organized,
  PBR-textured, valid `*_3JS.glb` that re-imports clean + render proof.
- **3D reference given** → **detail-complete to the reference** (the fidelity bar): bbox/datums
  ≤ 50 mm, roof pitch ≤ 2°, every overlay view silhouette-flush, **and every window/door/glazing
  opening matches in count and within ~50 mm in position/size**, with the reference's division
  pattern. Openings sourced from the **2D CAD elevation**, not reverse-engineered from a dense
  FBX. Materials never copied from the reference's flat placeholders.
- **Scope downgrade** → massing-only is allowed *only when the user explicitly asks for it*;
  otherwise the default is detail-complete. A silent downgrade is a failure.
- **Marketing render given (look standard)** → the final render **matches that image**: hero
  camera reproduced (straight-on, eye-level, long lens), per-element material parity
  (brick/wood/roof/frames/glass tone + finish), context/landscaping + sky + daylight present,
  exposure matched, matched frame saved beside the marketing image. "Looks like a building" but
  not like the render = **not done** (`references/match-to-render.md`).

## Regression
- Adding/altering this skill must not steal routing from `blender`, `3d-modeling`, `threejs-3d`.
- The Phase 4.5 additions must not make the skill fire for non-reference builds.

## Token budget
- Body stays a lean runbook; depth lives in `references/` and `scripts/`. Co-loaded with the
  other domain skills it must not degrade unrelated turns.

## Known failure modes (regression guards)
- Stale `object.bound_box` after edits → measure from evaluated vertices (`world_bbox`).
- Massing matched but openings approximated → **not done** (this is the bar that bit us; the
  fix is the detail-complete default + opening match from the CAD elevation).
- Auto opening-extraction on a dense full-interior FBX → unreliable; use the 2D elevation.
