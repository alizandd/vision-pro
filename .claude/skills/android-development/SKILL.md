---
name: android-development
description: The team's standards for building native Android apps with Kotlin and Jetpack Compose — project structure, architecture, coroutines, UI, persistence, testing, security, and Play Store release. Always use this skill whenever the conversation involves Android, Kotlin, Jetpack Compose, Android Studio, Gradle, an Android app module, or shipping to Google Play.
---

# Android development

Goal: native Android apps that are idiomatic Kotlin, lifecycle-correct, accessible, and shippable to Google Play. Owned by the **mobile-engineer**; lean on the shared `engineering-principles`, `security`, `testing-strategy`, and `git-workflow` skills.

## Stack (current baseline — verify with `tech-research`)
- **Kotlin** (2.x) as the only language for new code; **Jetpack Compose** as the baseline UI (Views/XML only for legacy screens). Compose BOM pins consistent versions.
- **Android Studio** (current stable) with the Kotlin Compose compiler plugin. **Gradle with Kotlin DSL** (`build.gradle.kts`) and version catalogs (`libs.versions.toml`).
- Target the **latest stable API level** for `targetSdk`/`compileSdk`; set a pragmatic `minSdk` (commonly 24+; 21+ if Compose-only and justified).
- **Google Play deadline — 2026-08-31**: new apps and all updates must target **Android 16 (API 36)** or higher (Wear OS / Automotive: API 35+); existing apps must be on at least API 35 to stay discoverable to new users. An extension to 2026-11-01 can be requested in Play Console. Treat a below-36 `targetSdk` as a release blocker, and budget for the API 36 behavior changes rather than bumping the number blind.

## Architecture & structure
- **MVVM / unidirectional data flow**: `ViewModel` exposes immutable UI state via `StateFlow`; Compose observes and renders; events flow up. No business logic in composables.
- Layered modules: UI (Compose) → ViewModel → domain (use cases) → data (repositories → network/DB). Repository pattern hides data sources.
- **Hilt** for dependency injection. **Navigation Compose** with typed routes. Single-activity architecture by default.
- Use Jetpack libraries: Room (DB), DataStore (preferences — not SharedPreferences for new code), WorkManager (deferred work), Paging where needed.

## Coroutines & concurrency
- Use **coroutines + Flow** for async; scope to `viewModelScope`/`lifecycleScope`. Collect flows with `repeatOnLifecycle`/`collectAsStateWithLifecycle` to respect lifecycle.
- Dispatchers injected (not hardcoded) for testability; do I/O on `Dispatchers.IO`, never the main thread.

## UI & UX
- Material 3 + design tokens; support dark theme, dynamic color, and configuration changes (rotation, multi-window).
- **Accessibility**: content descriptions, touch target sizes, TalkBack support, sufficient contrast. Handle loading/empty/error/offline states.
- Use `@Preview` (and custom preview wrappers) for fast iteration across themes and device classes.

## Security (see the `security` skill)
- Secrets in the **Android Keystore** / EncryptedSharedPreferences — never in source, `strings.xml`, or plain prefs. Keep API keys out of the APK; proxy sensitive calls server-side.
- Request the **minimum runtime permissions**, just-in-time, with rationale. Scope storage with the Storage Access Framework / scoped storage.
- HTTPS only; use a **Network Security Config** and consider certificate pinning. Enable R8/ProGuard for release (shrink + obfuscate). Validate deep links and exported components (`android:exported` explicit).

## Testing & QA
- Unit tests (JUnit + coroutines test + Turbine for Flow); Compose UI tests with the Compose test rule; instrumented/Espresso for integration. Mock the network (MockWebServer).
- Test on multiple API levels and screen sizes; profile with Android Studio Profiler for jank, memory, and battery.

## Build & release
- CI builds via Gradle (coordinate with devops via `cicd-pipeline`); sign release with a securely stored keystore (never committed). Build **App Bundles (.aab)** for Play.
- Per-environment config via build types/flavors; no hardcoded endpoints. Version via the `release-changelog` skill; stage rollouts on Play with monitoring.
