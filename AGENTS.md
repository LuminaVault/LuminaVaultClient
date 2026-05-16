# LuminaVaultClient — Agent Instructions

These rules apply to every agent (Claude, Codex, etc.) working in this repo. They are non-negotiable unless the user explicitly overrides them in-session.

## 1. Swift 6 Concurrency

- Target Swift 6 language mode with strict concurrency checking on the iOS target.
- SwiftUI views: prefer `@Observable` + `@State` over `@StateObject` for new code. Mark view models `@Observable` and `final` where possible.
- Networking and view-model glue runs in structured `async`/`await`. Avoid spawning `Task { ... }` from view bodies; spawn from `.task { ... }` modifiers or explicit lifecycle hooks so cancellation is wired correctly.
- Use `actor` for shared mutable state. Anything crossing isolation boundaries must be `Sendable`.
- Never silence concurrency warnings with `@unchecked Sendable` or `nonisolated(unsafe)` without a code comment explaining why.

## 2. Bruno Collection — Backend Is The Source

- The API contract lives in `LuminaVaultServer/Sources/AppAPI/openapi.yaml`. The client does **not** author the API.
- Bruno collections under `LuminaVaultServer/LuminaVaultCollection/LuminaVaultServer/` are **generated** from that spec via `make bruno-regen` on the server.
- If the client needs an endpoint shape change, file it against the server and update `openapi.yaml` there. Do not work around contract mismatches in the client.

## 3. LuminaVaultShared — Single Source for DTOs

- All wire-format DTOs shared with the server live in the sibling repo `LuminaVaultShared/Sources/LuminaVaultShared/APIDTOs.swift`.
- The client **must not** define its own copy of any DTO that already exists in `LuminaVaultShared`. Import the shared package instead.
- UI-only / view-state types are fine in the client, but name and locate them clearly (`...ViewState`, `...UIModel`) so the boundary is obvious.
- When adding a new DTO that crosses the wire: add it to `LuminaVaultShared` first, then consume from `LuminaVaultClient`.
- If you find duplicate DTOs, treat it as a bug: consolidate into `LuminaVaultShared` and delete the duplicate.

## How To Apply

- Before opening a PR that touches API calls: confirm the DTO comes from `LuminaVaultShared` and the endpoint exists in server `openapi.yaml`.
- Before merging concurrency-sensitive code: build with strict concurrency and ensure no new warnings.

---

<claude-mem-context>
# Memory Context

# [LuminaVaultClient] recent context, 2026-05-14 9:28pm GMT+1

Legend: 🎯session 🔴bugfix 🟣feature 🔄refactor ✅change 🔵discovery ⚖️decision 🚨security_alert 🔐security_note
Format: ID TIME TYPE TITLE
Fetch details: get_observations([IDs]) | Search: mem-search skill

Stats: 13 obs (4,244t read) | 38,281t work | 89% savings

### May 14, 2026
2544 1:42p 🔵 HER-40 Linear Issue: Hermie Mascot Animations via Rive Integration
2545 " 🔵 LuminaVaultClient Project Structure and Asset Locations
2578 6:18p 🟣 HermieMascotView.swift scaffolded for HER-40
2579 " 🔴 Pre-existing build error in HealthKitService.swift blocking arm64 compile
2581 6:20p 🔵 HermieMascotView.swift requires RiveRuntime dependency not yet in project
2583 " 🔵 HealthKitService.swift line 221 error: HKSource.bundleIdentifier is non-Optional String
2585 " 🟣 HER-40 scaffolding change summary: project, MainTabView, Resources, and HermieMascotView
S231 Scaffold Linear issue HER-40: Hermie Mascot Animations for LuminaVaultClient iOS app (May 14 at 6:21 PM)
2587 6:22p 🔵 No .gitignore in LuminaVaultClient project root; xcshareddata/swiftpm created for RiveRuntime SPM resolution
2588 " 🔵 Package.resolved confirms RiveRuntime SPM lock file exists in xcshareddata
2590 6:23p ✅ HER-40 files staged for commit on branch fernandocorreia316/her-40-hermie-mascot-animations
2595 6:26p 🟣 Hermie Mascot Animations Scaffold Initiated (HER-40)
2596 6:27p 🟣 Hermie Mascot Rive Animation Integration Scaffolded (HER-40)
2601 6:28p 🟣 GitHub PR #1 Opened for HER-40 Hermie Mascot Animations
S233 Scaffold HER-40: Hermie Mascot Animations for LuminaVaultClient iOS app (May 14 at 6:29 PM)
**Investigated**: Project structure of LuminaVaultClient (SwiftUI iOS app); existing static OnboardingMascot image usage in MainTabView; availability of Rive animation assets in project and LuminaVaultAssets folder; pre-existing build issues in HealthKitService.swift.

**Learned**: - The Rive asset (`hermie.riv`) does not yet exist in the project — it needs to be exported by designers and dropped into `LuminaVaultClient/Resources/Hermie/`.
    - The Rive state machine must be named exactly "State Machine 1" with trigger inputs named `idle`, `thinking`, and `happy`.
    - A pre-existing iOS 26 SDK compile error exists in `HealthKitService.swift:221` where `bundleIdentifier` is no longer optional — unrelated to HER-40 but blocks full xcodebuild success.
    - LuminaVaultClient/pull/1 is the first PR ever opened on the LuminaVaultClient GitHub repo.
    - `HermieMascotState` in MainTabView is currently hardcoded to `.idle` — dynamic state wiring from AppState is a follow-up task.

**Completed**: - Rive SPM dependency `rive-app/rive-ios` 6.20.3 added to LuminaVaultClient Xcode target (Package.resolved updated).
    - `LuminaVaultClient/Components/HermieMascotView.swift` created with `HermieMascotState` enum (idle/thinking/happy) and Rive trigger firing logic; graceful fallback to static Mascot image when `hermie.riv` is absent.
    - `LuminaVaultClient/Resources/Hermie/` placeholder directory and README created documenting the required Rive asset contract.
    - `MainTabView` updated to render `HermieMascotView(state: .idle, …)` replacing the static OnboardingMascot image.
    - Commit `b27f32a` (6 files changed, 164 insertions, 12 deletions) pushed to branch `fernandocorreia316/her-40-hermie-mascot-animations`.
    - GitHub PR #1 opened: https://github.com/LuminaVault/LuminaVaultClient/pull/1 — closes Linear HER-40.

**Next Steps**: HER-40 scaffold is fully complete and PR is open. No active in-progress work. Pending follow-ups tracked in the PR: (1) designer delivers `hermie.riv` asset, (2) wire HermieMascotState from AppState, (3) fix pre-existing HealthKitService.swift:221 iOS 26 compile error.


Access 38k tokens of past work via get_observations([IDs]) or mem-search skill.
</claude-mem-context>