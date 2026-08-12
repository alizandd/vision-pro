---
name: ios-development
description: The team's standards for building native iOS (and Apple-platform) apps with Swift and SwiftUI — project structure, concurrency, UI, persistence, testing, security, and App Store release. Always use this skill whenever the conversation involves iOS, iPadOS, macOS, Swift, SwiftUI, Xcode, an .xcodeproj/SPM package, or shipping to the App Store.
---

# iOS / Apple-platform development

Goal: native Apple apps that are correct, concurrency-safe, accessible, and pass App Store review the first time. Owned by the **mobile-engineer**; lean on the shared `engineering-principles`, `security`, `testing-strategy`, and `git-workflow` skills.

## Stack (current baseline — verify with `tech-research`)
- **Xcode 26 + the iOS/iPadOS/tvOS/visionOS/watchOS 26 SDKs are mandatory** for App Store Connect uploads (enforced since 2026-04-28). Building against the 26 SDK does not raise your deployment target — keep supporting older OS versions there.
- **Swift 6** with **strict concurrency** as the compiler default — data-race safety is enforced, not optional. **SwiftUI** as the baseline UI layer for new apps; UIKit only where SwiftUI has a real gap or for existing screens.
- **Xcode 16+** (Xcode 26 line) and the current iOS SDK. New App Store submissions must build with a current Xcode/SDK — track Apple's submission deadline.
- **Swift Package Manager** for dependencies (avoid CocoaPods for new work). **Swift Testing** (`@Test`/`#expect`) for new test suites; XCTest only for legacy/UI tests.

## Architecture & structure
- Default to **MVVM with SwiftUI** + observable models (`@Observable`). Keep views declarative and thin; push logic into view models and services.
- Separate layers: UI (SwiftUI) → view models → domain/services → data (network, persistence). Inject dependencies (protocols) for testability — no singletons reaching into the network.
- Model navigation explicitly (`NavigationStack` + a typed router/path); avoid scattered imperative navigation.
- Persistence: **SwiftData** for new local stores; Core Data where already established. `Codable` for DTOs; never persist secrets in plain stores.

## Concurrency (Swift 6)
- Use **`async/await`** and **actors** for shared mutable state; isolate UI updates to `@MainActor`. Don't bridge to GCD/completion handlers in new code.
- Treat every concurrency warning as an error to fix, not silence — `@unchecked Sendable` and `nonisolated(unsafe)` need an explicit, recorded justification.

## UI & UX
- Support Dynamic Type, Dark Mode, and **VoiceOver/accessibility** (labels, traits, focus) from the start — not retrofitted.
- Handle every state: loading, empty, error, offline. Use `#Preview` macros for fast iteration across size classes and color schemes.
- Respect safe areas, large titles, and platform HIG; adapt layouts for iPhone/iPad with size classes.

## Security (see the `security` skill)
- Secrets/tokens go in the **Keychain**, never `UserDefaults` or source. Use the Keychain access groups deliberately.
- **App Transport Security**: HTTPS only; justify any exception. Consider certificate pinning for high-value APIs.
- Declare a **Privacy Manifest** (`PrivacyInfo.xcprivacy`) and request only the permissions you use, with clear usage strings. Honor App Tracking Transparency.
- Use biometric (`LocalAuthentication`) gating for sensitive flows; store credentials with the right `kSecAttrAccessible` class.

## Testing & QA
- Unit-test view models and services with Swift Testing; UI-test critical flows. Mock the network/persistence via injected protocols.
- Run on real devices for performance, memory, and energy; profile with Instruments. Catch retain cycles (`weak`/`unowned` in closures).

## Build & release
- Manage signing with automatic signing in dev; **fastlane** or Xcode Cloud for CI builds, screenshots, and TestFlight/App Store upload (coordinate with devops via `cicd-pipeline`).
- Externalize config per environment (xcconfig/schemes); no hardcoded endpoints or keys. Version with the team's `release-changelog` skill.
- Pre-submission checklist: privacy manifest present, permissions justified, no debug logging of PII, dSYMs uploaded, accessibility audited.
