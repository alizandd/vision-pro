---
name: threejs-3d
description: The team's standards for building interactive 3D and WebGL experiences with Three.js — loading and optimizing 3D models, authoring scenes/geometry in code, performance, and integration with the frontend. Always use this skill whenever the conversation involves Three.js, WebGL, 3D models (glTF/GLB/OBJ/PLY), interactive 3D scenes, react-three-fiber, or 3D on the web.
---

# Three.js / Interactive 3D

Goal: 3D experiences that look great and run smoothly, on real devices and constrained networks.

## Project setup
- Prefer **react-three-fiber + drei** when the app is React; use vanilla Three.js for standalone/embedded scenes.
- Keep the scene graph, controls, and resources modular and disposable (clean up geometries, materials, textures on unmount).
- Centralize a render loop; avoid multiple uncoordinated `requestAnimationFrame` loops.

## Working with models
- Prefer **glTF/GLB** as the delivery format (compact, PBR-friendly). Convert other formats (OBJ/FBX/PLY) in the pipeline.
- Optimize assets: **Draco/meshopt** compression, **KTX2/basis** textures, sensible polycount, baked lighting where possible.
- Use `GLTFLoader` with a loading manager; show progress and handle load errors gracefully.
- Budget: watch triangle count, texture resolution, and draw calls. Merge/instance repeated geometry.

## Authoring in code
- Build geometry, materials, lights, and cameras programmatically when a model isn't needed.
- Use `InstancedMesh` for many repeated objects; `BufferGeometry` for custom shapes.
- Be deliberate with lighting (ambient + directional/environment) and materials (PBR `MeshStandardMaterial`/`MeshPhysicalMaterial`).

## Interactivity & UX
- Controls (OrbitControls/custom) tuned to the experience; constrain where it aids usability.
- Raycasting for picking/hover; keep interactions accessible with non-3D fallbacks where reasonable.
- Handle resize, pixel ratio (cap `devicePixelRatio` for perf), and visibility (pause render when offscreen/tab hidden).

## Performance
- Cap pixel ratio, use frustum culling, LOD for distant objects, and lazy-load heavy assets.
- Dispose unused resources; avoid per-frame allocations.
- Profile with stats; target a stable frame rate over peak fidelity.

## Network-constrained delivery
- Compress and lazy-load assets; consider hosting via an internal/cached source given possible bandwidth/filtering constraints (coordinate with devops on asset delivery).
