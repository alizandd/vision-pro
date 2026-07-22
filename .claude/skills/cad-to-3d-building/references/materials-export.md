# Materials, texturing & glTF export (details)

Load this for Phase 6–8: PBR materials that match the look reference **and** survive the
web glTF export.

## Combine the two libraries
Architectural texture sets usually arrive **split**. Catalogue every file as
*albedo / normal / roughness* before building materials:
- **Detail set** (e.g. `RoxMat_*`): brick & foundation = **Normal + Rough only** (no
  albedo); roof = `shingle`(albedo)+N+R; siding = `lap`(albedo)+N.
- **Product albedos** (e.g. `Material__*_BaseColor.jpg`): real surfaces. Inspect them —
  in the Roxbrough/GLTF set: `__37` grey brick, `__30` grey-taupe brick, `__35` red brick,
  `__89` concrete panel, `__87` concrete block, `__36/43/85` grey concrete/stucco,
  `__44` grass, `__91` grey pavers, `__75` is a sports field (junk — verify, don't assume).

A material = **albedo from one set + Normal/Rough detail from the other**.

## Material plan used in the sample
| Part | Base Color | Normal | Rough | Tile |
|---|---|---|---|---|
| Brick `Structure` | `Material__37` (grey) | `RoxMat_Brick_Normal` | `RoxMat_Brick_Rough` | 2.2 m |
| Foundation | `Material__89` ×grey tint | `RoxMat_Foundation_Normal` | `RoxMat_Foundation_Rough` | 2.4 m |
| Roof | `RoxMat_Roof_shingle` | `RoxMat_Roof_Normal` | `RoxMat_Roof_Rough` | 1.4 m |
| Wood accent | procedural Wave+Noise (warm) | bump | — | — |
| Trim/frames/soffit/belt | off-white factor (0.86,0.85,0.81) | — | rough 0.45 | — |
| Glass | factor (0.03,0.05,0.07), rough 0.04, IOR 1.45 | — | — | — |

No grey-brick or wood albedo existed in the set, so: grey brick came from a neutral
product albedo (`__37`); wood was **procedural** and later **baked** for export.

## Two rules that save you
1. **Colour space.** Albedo = `sRGB`; **Normal & Roughness = `Non-Color`**. Wrong space →
   washed normals / wrong gloss. `pbr_material()` sets this for you.
2. **UVs that export and tile at real size.** `bpy.ops.uv.cube_project` needs a 3D-view
   context → fails headless. Use `box_uv(ob, tile)`: per face, drop the dominant-normal
   axis and set `UV = (world coords on the other two axes) / tile`. Real-world texel
   density, and real UVs so glTF carries the textures.

> **Never** drive a web-bound material from *Box projection on Object/Generated coords* or
> a pure node graph — neither exports to glTF. Either `box_uv` + image textures, or bake.

## Lighting for the render proof
- World: `ShaderNodeTexSky`, `sky_type='MULTIPLE_SCATTERING'` (5.x; the old `NISHITA`
  enum is gone). Set `sun_elevation`/`sun_rotation`; align a Sun lamp to it.
- Context sells it: grass plane (`__44`) + paver apron (`__91`) + sky.
- Cycles 64–96 + denoise (EEVEE for fast iteration).
- **Tune exposure, not light power.** Under AgX the sample needed
  `view_settings.exposure ≈ −2.2`, sky strength ~0.85. Cranking the sun blows highlights.
- **MCP:** a Cycles render can outlast the request timeout while Blender keeps going.
  Render to a path and **poll the file** for a stable size. Window/area screenshot tools
  can fail on payload size — prefer render-to-path + read the file.

## Export to web glTF (`*_3JS.glb`)
1. **Bake** procedural/box materials to a UV image (`bake_albedo`): normalized 0–1 UV →
   `bake(type='DIFFUSE', pass_filter={'COLOR'})` → save PNG → rewire into Base Color.
2. **Triangulate on export.** Add a `TRIANGULATE` modifier (don't apply to source) and
   export with `export_apply=True`. Booleans leave n-gons → otherwise you get
   *"Could not calculate tangents"* and broken normal maps on the web.
3. Export the **building collection only**: `export_format='GLB', use_selection=True,
   export_yup=True, export_apply=True, export_materials='EXPORT',
   export_image_format='AUTO', export_texcoords=True, export_normals=True`.
4. **Optimize size.** Downscale albedos ≤1024 first (sample: 13.5 MB → 10 MB by resizing
   one 4K map). For production: **KTX2/Basis** textures (→ ~1–2 MB) and **Draco** mesh
   compression (needs `DRACOLoader` in the Three.js app — coordinate via `threejs-3d`).
5. **Validate by re-importing** (`validate_glb`): assert mesh/material/image counts and
   that bbox **dimensions + orientation** match the source. Sample: 11 meshes, 6 materials,
   10 images, **4.36 × 3.14 × 12.8 m**, `+Y` up preserved.
6. Save a packed source `.blend` (`file.pack_all()` then save).

## Glass for web
Avoid `Transmission` for the web deliverable — `KHR_materials_transmission` isn't
universally supported and reads wrong in many viewers. A dark base colour + low roughness
+ IOR 1.45 (alpha = 1) reads as glazing and exports cleanly. Use real transmission only in
the render-only path.
