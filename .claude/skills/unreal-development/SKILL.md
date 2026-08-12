---
name: unreal-development
description: The team's standards for building games and real-time experiences in Unreal Engine 5 with C++ and Blueprints — project structure, C++/Blueprint split, Nanite/Lumen, performance, source control, testing, and multi-platform builds. Always use this skill whenever the conversation involves Unreal Engine, UE5, C++ gameplay, Blueprints, Nanite, Lumen, or shipping an Unreal build.
---

# Unreal Engine development

Goal: Unreal projects that hit frame budget on target hardware, keep a clean C++/Blueprint boundary, and build to every platform. Owned by the **game-developer**; lean on the shared `engineering-principles`, `security`, `testing-strategy`, and `git-workflow` skills. Pairs with `3d-modeling` and `blender` for assets.

## Stack (current baseline — verify with `tech-research`)
- **Unreal Engine 5.8** (June 2026 — the latest and **last planned UE5 major**; Epic is now on UE6, with UE5 continuing to get bug/regression fixes) with **C++ for systems/gameplay foundations** and **Blueprints for composition, tuning, and designer-facing logic**.
- Core renderer features: **Nanite** (virtualized geometry), **Lumen** (dynamic GI — SWRT with HWRT fallback), **Virtual Shadow Maps**. Know their limits (see below).

## C++ / Blueprint boundary
- Put performance-critical and core systems in **C++** (`UCLASS`/`USTRUCT`/`UPROPERTY`/`UFUNCTION` with correct specifiers); expose tunables and high-level flow to **Blueprints**.
- Avoid heavy per-tick logic in Blueprints; don't duplicate logic across both. Use the Gameplay Ability System / data assets for scalable gameplay where it fits.
- Respect Unreal idioms: `TObjectPtr`, soft references for async asset loads, the reflection/GC system (don't hold raw pointers to `UObject`s), and naming conventions (`A`/`U`/`F`/`E` prefixes).

## Rendering & performance
- **Nanite** suits high-poly static/instanced meshes — it does **not** support skeletal/animated meshes, translucency, or standard opacity masks; use traditional LODs for characters, foliage with translucency, and masked materials.
- Budget per platform: profile with **Unreal Insights**, `stat unit`, GPU Visualizer. Watch draw calls, overdraw, shader complexity, and Lumen/VSM cost on lower-end targets.
- Use level streaming / **World Partition** for large worlds; pool actors; keep materials and instance counts in check.

## Assets & content (see `3d-modeling`, `blender`)
- Import via **glTF/FBX** with correct scale (Unreal is cm), orientation, and LODs; set up PBR materials and master/instance material patterns. Right-size textures and use virtual textures where helpful.

## Source control
- **Git + Git LFS** (or Perforce for large teams) with an Unreal-specific `.gitignore` (ignore `Binaries/`, `Intermediate/`, `Saved/`, `DerivedDataCache/`). Treat `.uasset`/`.umap` as binary; use the editor's **One File Per Actor** to reduce map merge conflicts. Coordinate with devops via `git-workflow`.

## Security & testing
- Authoritative server for multiplayer — never trust client input; replicate carefully and validate RPCs. Keep secrets/keys out of the shipped build.
- **Automation/Functional tests** for gameplay systems; Gauntlet for device/perf testing where justified. CI builds with **UnrealBuildTool / `RunUAT`** per platform (coordinate with devops via `cicd-pipeline`); version via `release-changelog`.
