---
name: windows-desktop
description: The team's standards for building native Windows desktop apps with .NET, C#, and WinUI 3 / Windows App SDK — project structure, MVVM, packaging (MSIX), testing, security, and distribution. Always use this skill whenever the conversation involves a Windows desktop app, WinUI 3, Windows App SDK, WPF, .NET MAUI on Windows, C# desktop UI, or MSIX packaging.
---

# Windows desktop development

Goal: native Windows 11 apps that are modern (Fluent), maintainable, packaged, and secure. Owned by the **windows-engineer**; lean on the shared `engineering-principles`, `security`, `testing-strategy`, and `git-workflow` skills.

## Stack (current baseline — verify with `tech-research`)
- **C# on current .NET** (LTS preferred) with **WinUI 3 + the Windows App SDK** for new native Windows apps — Fluent Design, modern windowing, decoupled from the OS via NuGet.
- **WPF** remains valid for existing line-of-business apps; choose **.NET MAUI** only when genuinely cross-platform (it uses WinUI under the hood on Windows). State the choice and why (ADR) — don't default to MAUI for a Windows-only app.
- Official **WinUI .NET CLI templates** allow create/build/run from the command line for CI.

## Architecture & structure
- **MVVM**: Views (XAML) bind to ViewModels; models/services hold logic. Use the **CommunityToolkit.Mvvm** source generators (`[ObservableProperty]`, `[RelayCommand]`) — no code-behind business logic.
- Layer: UI (XAML/WinUI) → ViewModel → services → data. Dependency injection via `Microsoft.Extensions.DependencyInjection`; config via `Microsoft.Extensions.Configuration`.
- Keep async UI responsive: `async/await` with `Task`, never block the UI thread; marshal to the dispatcher for UI updates. Use `IProgress<T>`/`CancellationToken` for long work.

## UI & UX
- Follow Fluent Design and Windows 11 conventions (Mica/Acrylic, theming, light/dark). Support window resizing, DPI scaling, and multiple monitors.
- **Accessibility**: UI Automation properties, keyboard navigation, high-contrast themes, narrator support. Handle loading/empty/error states.

## Packaging & distribution
- Prefer **packaged (MSIX)** apps — single-project MSIX gives full API surface and package identity (needed for many App SDK features, notifications, file associations). Use **unpackaged** only with a clear reason.
- Distribute via the Microsoft Store or signed MSIX/App Installer with auto-update. Sign packages with a trusted code-signing cert (store the cert/secrets securely — coordinate with devops).

## Security (see the `security` skill)
- Store secrets with **DPAPI** / Windows Credential Manager / `PasswordVault` — never in source, app settings, or registry in plaintext.
- Run least-privilege; avoid requiring admin elevation unless essential (and justify it). Validate all external input; be careful with `Process.Start`, file paths, and deserialization.
- HTTPS via `HttpClient` (reused, not per-call); validate certificates. Keep dependencies patched (devops CVE watch).

## Testing & QA
- Unit tests with xUnit/NUnit/MSTest on ViewModels and services (UI-free, DI-mocked). UI/automation tests via WinAppDriver/Appium where flows justify it.
- CI build + test through the .NET CLI / WinUI templates (coordinate with devops via `cicd-pipeline`). Version via the `release-changelog` skill.
