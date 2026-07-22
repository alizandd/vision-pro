---
name: 3d-modeling
description: The team's standards for producing game- and web-ready 3D assets — topology, UVs, PBR texturing, LODs, scale/orientation conventions, and the glTF/FBX delivery pipeline. Always use this skill whenever the conversation involves 3D models, meshes, topology, UV unwrapping, PBR materials/textures, LODs, baking, or preparing assets for a game engine, AR/VR, or the web. Tool-agnostic; pair with `blender` for the authoring tool and `threejs-3d`/`unity-development`/`unreal-development` for the target.
---

# 3D modeling & asset pipeline

Goal: 3D assets that look right, are lightweight enough for their target, and import cleanly into any engine or the web. Owned by the **3d-artist**; this skill is **tool-agnostic** (the `blender` skill covers the authoring tool). Pairs with `threejs-3d`, `unity-development`, and `unreal-development` for delivery.

## Delivery formats & conventions
- Prefer **glTF/GLB** for web and engine-neutral delivery (compact, PBR-native, Khronos standard); **FBX** where an engine pipeline expects it. Avoid shipping editor-native formats (.blend/.max) as runtime assets.
- **Scale**: agree on real-world units up front (glTF/Three.js = meters; Unreal = cm). **Orientation**: +Y up for glTF; apply transforms (freeze rotation/scale) before export. One consistent forward axis across the project.
- Clean export: triangulated where the target needs it, no n-gons in deforming meshes, no leftover history/empties, sensible object/material names.

## Topology
- **Quad-based, even topology** for anything that deforms (characters, faces); proper edge loops at joints. Keep poly count appropriate to the target and viewing distance — high detail belongs in normal maps, not raw geometry.
- Watch for non-manifold geometry, flipped/inconsistent normals, overlapping verts, and stray geometry. Apply smoothing/shading groups deliberately.

## UVs & texturing (PBR)
- Non-overlapping UVs with adequate padding; pack efficiently; keep texel density consistent across an asset/scene. Use a second UV channel for lightmaps when the engine bakes lighting.
- Author **PBR metal/rough** materials (the glTF standard maps directly to a Principled BSDF). Deliver maps as: base color (albedo, no baked lighting), normal, and an **ORM** (occlusion/roughness/metallic packed) texture, plus emission where needed.
- Right-size textures (power-of-two), provide mips, and compress per platform (KTX2/Basis for web; ASTC/BC for engines). Bake high-poly detail (normal/AO) onto the low-poly target.

## LODs & optimization
- Provide **LODs** for anything seen at varying distance; use instancing for repeated objects. Merge where it reduces draw calls without hurting culling.
- Budget triangles, materials/draw calls, and texture memory per target device; document the budget with the asset.

## Handoff & QA
- Validate in the **actual target** (engine/web viewer), not just the authoring tool: correct scale, materials, normals, and performance. Provide a short asset note (tri count, texture sizes, pivot, intended use).
- Version binary assets with **Git LFS** (coordinate with devops via `git-workflow`); keep source files organized and named consistently.
