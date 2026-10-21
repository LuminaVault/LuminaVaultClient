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
- Bruno collections in the sibling repo `LuminaVaultCollection/LuminaVaultServer/` are **generated** from that spec via `make bruno-regen` on the server.
- If the client needs an endpoint shape change, file it against the server and update `openapi.yaml` there. Do not work around contract mismatches in the client.

## 3. LuminaVaultShared — Single Source for DTOs

- All wire-format DTOs shared with the server live in the sibling repo `LuminaVaultShared/Sources/LuminaVaultShared/APIDTOs.swift`.
- The client **must not** define its own copy of any DTO that already exists in `LuminaVaultShared`. Import the shared package instead.
- UI-only / view-state types are fine in the client, but name and locate them clearly (`...ViewState`, `...UIModel`) so the boundary is obvious.
- When adding a new DTO that crosses the wire: add it to `LuminaVaultShared` first, then consume from `LuminaVaultClient`.
- If you find duplicate DTOs, treat it as a bug: consolidate into `LuminaVaultShared` and delete the duplicate.

## 4. Guided onboarding — read the contract, and never set a latch

- The cross-platform contract is `LuminaVaultShared/docs/guided-start.md` (the
  sibling repo). Web and a future Android client read the same document, so
  step ids, copy, targets and the visibility rule are not this repo's to
  change alone.
- `firstCaptureCompleted`, `firstKBCompileCompleted` and `firstQueryCompleted`
  are latched by the server. The client polls them and never writes them. A
  local "saved" is not a server "saved" — capture is offline-queued, so the
  latch is the only trustworthy completion signal.
- Spotlight targets are places in the UI, steps are tasks. They are one-to-one
  only by coincidence today.
- The spotlight is built on anchor preferences only. `.coordinateSpace(.named:)`
  does not cross the tab or sheet hosting boundary and `frame(in: .named(…))`
  silently returns window coordinates there — about ninety points of error with
  no warning. Anchors from a sheet never reach the tab-level overlay at all.

## How To Apply

- Before opening a PR that touches API calls: confirm the DTO comes from `LuminaVaultShared` and the endpoint exists in server `openapi.yaml`.
- Before merging concurrency-sensitive code: build with strict concurrency and ensure no new warnings.
