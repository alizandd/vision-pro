---
name: unity-development
description: The team's standards for building games and real-time/interactive apps in Unity with C# — project structure, render pipeline choice, performance, assets, testing, and multi-platform builds. Always use this skill whenever the conversation involves Unity, a Unity project, C# MonoBehaviours/ScriptableObjects, URP/HDRP, or shipping a Unity build to any platform.
---

# Unity development

Goal: Unity projects that run smoothly on the target hardware, stay maintainable as they grow, and build cleanly to every platform. Owned by the **game-developer**; lean on the shared `engineering-principles`, `security`, `testing-strategy`, and `git-workflow` skills. Pairs with `3d-modeling` and `blender` for assets.

## Stack (current baseline — verify with `tech-research`)
- **Unity 6.3 LTS** with **C#** — the current LTS, supported to December 2027. **Unity 6.0 LTS support ends October 2026**, so move projects still on it. Use the latest LTS for new projects, not tech-stream releases. (Unity 7 is beta in Dec 2026 / release Q1 2027 — not a target yet.)
- 6.3 adds **signed packages with trust indicators in the Package Manager**; unsigned packages warn. Treat an unsigned third-party package as a supply-chain decision, not a click-through.
- **URP (Universal Render Pipeline)** is the default for new projects (mobile/XR/web/cross-platform); **HDRP** only for high-end PC/console with a stated reason. The Built-In pipeline is legacy — avoid for new work.
- **Input System** package (not legacy `Input`). **Burst + Jobs/ECS (DOTS)** only where profiling justifies the complexity.

## Architecture & structure
- Composition over deep inheritance: small focused **MonoBehaviours**; share data/config via **ScriptableObjects** (avoid singletons/`static` global state).
- Decouple systems with events/messaging or a service locator/DI; don't let components reach across the scene with `Find`. Cache references in `Awake`.
- Keep `Update` lean: avoid per-frame allocations (GC spikes), `GetComponent`, and `Camera.main` in hot loops. Use object **pooling** for spawned objects.
- Organize assets by feature; consistent naming; **Addressables** for content loading/memory management over `Resources`.

## Performance
- Budget by platform (mobile vs PC): draw calls (batching/GPU instancing), triangle/texture budgets, overdraw, physics cost. Profile with the **Unity Profiler / Frame Debugger / Memory Profiler** — measure before optimizing.
- Bake lighting where possible; use LODs and occlusion culling; compress textures per platform (ASTC on mobile). Cap allocations to keep GC quiet.

## Assets & content (see `3d-modeling`, `blender`)
- Import models as **glTF/FBX** with correct scale/orientation and sane import settings; set up materials for the chosen pipeline (URP/HDRP Lit). Atlas textures; right-size import resolution.
- Keep source art outside the build; commit only what's needed.

## Source control
- Use **Git with Unity-specific `.gitignore`**, **Git LFS** for binary assets, and force **text/visible meta + asset serialization** so diffs/merges work. Never lose `.meta` files. Coordinate with devops via `git-workflow`.

## Security & testing
- Validate all external/networked input and downloaded content; don't trust client state in multiplayer (authoritative server). Keep secrets/keys out of the client build — proxy server-side.
- **Unity Test Framework** (EditMode for logic, PlayMode for integration). CI builds via Unity command-line/CLI per platform (coordinate with devops via `cicd-pipeline`); version via `release-changelog`.
