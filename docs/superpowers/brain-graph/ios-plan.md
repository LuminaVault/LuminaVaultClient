# Brain Graph iOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the iOS Brain tab as one Obsidian-style graph across all vaults: a labelled 2D force graph by default, a RealityKit constellation behind a switch, explicit selection with a tray, search, and in-place filters, matching the web screen's behaviour.

**Architecture:** New wire DTOs go in `LuminaVaultShared` and are released as a new package version. In the client, pure Swift modules (graph model, selection, tray rules, request state) mirror the web modules one for one and carry the tests. A layout actor runs the 2D force simulation off the main actor and publishes position snapshots; a SwiftUI `Canvas` draws them only when something changed. The 3D view is a RealityKit scene built from shared resources and updated in place. `BrainTabView` wires store, selection and renderer and owns no logic.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, `@Observable`, Swift Testing for new tests (XCTest where a suite already uses it), RealityKit (iOS 18), SwiftUI `Canvas` + `TimelineView`, the app's `LVPalette` / `LVTypography` / `LVSpacing` tokens.

**Spec:** `docs/superpowers/specs/2026-11-11-second-brain-graph-design.md` (sections 2 and 4). Server contract: "Wire contract" in `docs/superpowers/plans/2026-11-11-brain-graph-server.md`. The web implementation is the behavioural reference: `LuminaVaultWebApp` branch `feat/brain-graph` (PR #110), files under `src/lib/brain/`.

`IOS` = `/Users/fernandocorreiachill/Work/production/apps/lumina/LuminaVaultClient`. `SHARED` = `/Users/fernandocorreiachill/Work/production/apps/lumina/LuminaVaultShared`. `WEB` = the web worktree `LuminaVaultWebApp/.worktrees/brain-graph`.

## Global Constraints

- Swift 6 language mode, strict concurrency, no new warnings. No `@unchecked Sendable` or `nonisolated(unsafe)` without a comment saying why. No `Task {}` spawned from view bodies; use `.task`.
- Wire DTOs live only in `SHARED`. The client defines view-state types only, named `...ViewState` or `...UIModel` where they could be confused with wire types.
- The client consumes `SHARED` as a remote package pinned by version (`upToNextMajor` from 5.32.0; latest tag `v5.33.0`). Task 1 produces `v5.34.0`. **Tagging and pushing a release needs the owner's go-ahead.** Until the tag exists, client work happens against a temporary branch pin in the worktree that must be replaced by the version pin before the client PR.
- No new Swift packages. `Grape` is already a dependency but unused by this work; do not adopt it.
- Minimum iOS 18.0. The `if #available(iOS 18.0, *)` branches in `Features/Brain/` go away.
- Server facts the client must respect (same as web): every uuid inside a node id is UPPERCASE; hub ids are `tag:<text>`, `author:user:<UUID>`, `author:model:<provider>/<model>`, `entity:<key>`, `space:<UUID>`; about 10 graph requests a minute on the free tier; the client fetches only on first load, a change of vault set, focus or depth, and the first Similar toggle, with refetches debounced 400 ms; a focused request omits `author` unless the focus is an author hub (then `limit=800`, depth 1); `similar` is requested only when turned on; notes are text files only; `truncated` means the 800-item window was cut.
- Selecting never calls the API and never moves the camera.
- Colours come from `LVPalette` tokens; no hex literals and no `Color.black` in `Features/Brain/`. One colour per connection kind, the same in the legend and on the canvas.
- Chrome follows `IOS/docs/DESIGN_SYSTEM.md` §13: inline title, one primary toolbar action plus an overflow menu, materials only in bars, `.lvProminent` for prominent buttons. §13.8 to §13.9 forbid glow and particles outside a short list of surfaces: the constellation view is an owner-approved exception and is added to that list in Task 10.
- Tap targets at least 44 pt. Dynamic Type respected in every label outside the canvas. VoiceOver has a full path that does not need the canvas (Task 8's list). Reduce Motion: no auto-rotation, no animated camera or layout; layouts settle off screen and appear settled.
- Performance budget on an iPhone 15-class device: 60 fps while panning and zooming 1,000 points in 2D and orbiting in 3D; nothing redrawn while at rest; simulation stops when the tab is not visible; memory flat across ten 2D↔3D switches.
- Copy: a point is a "note" or "memory"; totals say "connections"; "Links" means wikilinks; the 3D view is the "Constellation". Same strings as the web screen wherever a string exists there.
- Branches: `feat/brain-graph` in both repos, in worktrees. `IOS` has two other worktrees (`feat/quick-assistant` touches four lines of `BrainTabView.swift`); do not touch them.
- Build and test with `xcodebuild` against the `LuminaVaultClient` scheme on an available iOS 18+ simulator; read `IOS/.github/workflows/ci.yml` for the exact invocation and reuse it. Snapshot baselines are recorded by the repo's `record-snapshots` workflow; follow how `RecapSnapshotTests` does it.

## Review Focus

1. A vault with no notes: an empty state with a way to capture, not a spinner or a blank canvas. (Task 8)
2. A 429 keeps the graph on screen with one notice and a Retry; it never blanks the canvas or loops. (Task 5)
3. A selected point hidden by a filter leaves the selection and its chip leaves the tray. (Tasks 4, 9)
4. Arriving from "Show in graph" for a memory that no longer exists: "That is no longer in your graph" with a way back to the full graph. (Tasks 5, 8)
5. Switching the active vault elsewhere in the app while Brain is not visible: on return the vault chips and the reasoning sheet reflect the new active vault without a manual reload and without a second graph request. (Task 11)

## File Structure

`SHARED`
| File | Responsibility |
|---|---|
| `Sources/LuminaVaultShared/BrainGraphDTOs.swift` | `BrainGraphResponse`, node, edge, vault, position, ref, kind enums |
| `Tests/LuminaVaultSharedTests/BrainGraphDTOTests.swift` | Decoding against real server JSON |

`IOS/LuminaVaultClient/`
| File | Responsibility |
|---|---|
| `API/Brain/BrainGraphEndpoints.swift`, `BrainGraphClientProtocol.swift`, `BrainGraphHTTPClient.swift` | `GET /v1/brain/graph` |
| `Features/Brain/Model/BrainGraphRequest.swift` | Request value + query building (port of `brain-api.ts`) |
| `Features/Brain/Model/BrainGraphModel.swift` | Filter, index, neighbours, search, colour key (port of `graph-model.ts`) |
| `Features/Brain/Model/BrainSelection.swift` | Selection state machine (port of `selection.svelte.ts`) |
| `Features/Brain/Model/BrainTrayActions.swift` | What each tray action may do (port of `tray-actions.ts`) |
| `Features/Brain/Model/BrainGraphStore.swift` | Loading, refetch rules, stale/retry, known vaults (port of `brain-graph-view-model.svelte.ts`) |
| `Features/Brain/Model/BrainPrefs.swift` | Persisted toggles and 2D/3D choice |
| `Features/Brain/Layout/GraphLayout2D.swift` | Actor running the 2D force simulation off the main actor |
| `Features/Brain/Layout/ConstellationLayout.swift` | Pure 3D layout (port of `constellation-layout.ts`) |
| `Features/Brain/Render/BrainGraphCanvas.swift` | 2D drawing, labels, gestures (rewritten) |
| `Features/Brain/Render/BrainGraphRealityView.swift` | 3D constellation (rewritten) |
| `Features/Brain/Render/BrainGraphTheme.swift` | Palette → drawing colours |
| `Features/Brain/BrainTabView.swift` | Wiring, toolbar, states |
| `Features/Brain/BrainFilterSheet.swift`, `BrainListView.swift`, `BrainSelectionTray.swift`, `BrainNodeDetailSheet.swift` | Screen parts |
| `Features/Brain/KnowledgeReasoningSheet.swift`, `KnowledgeReasoningViewModel.swift` | Kept; lose graph loading and node selection |

Deleted at the end: `BrainGraphEngine.swift`, `BrainGraphViewModel.swift`, `KnowledgeGraphProjection.swift`, `API/Memory/MemoryGraph*.swift` if nothing else uses them, and the tests of deleted types.

---

### Task 1: Shared DTOs (repo `SHARED`)

**Files:**
- Create: `Sources/LuminaVaultShared/BrainGraphDTOs.swift`, `Tests/LuminaVaultSharedTests/BrainGraphDTOTests.swift`

**Interfaces:**
- Produces (all `public`, `Codable`, `Sendable`):

```swift
public enum BrainNodeKindDTO: String, Codable, Sendable { case note, memory, tag, author, entity, space }
public enum BrainLinkKindDTO: String, Codable, Sendable, CaseIterable { case link, source, tag, author, entity, space, similar }
public struct BrainGraphVaultDTO: Codable, Sendable, Identifiable, Equatable { public let id: UUID; public let name: String; public let personal: Bool }
public struct BrainGraphRefDTO: Codable, Sendable, Equatable { public let vaultID: UUID; public let id: UUID }
public struct BrainGraphNodeDTO: Codable, Sendable, Identifiable, Equatable {
    public let id: String            // uuid for notes/memories, prefixed id for hubs; never parsed as UUID
    public let kind: BrainNodeKindDTO
    public let label: String
    public let vaultID: UUID?
    public let spaceID: UUID?
    public let weight: Int
    public let createdAt: Date?
    public let pos: GraphPosition3D?  // existing type
    public let refs: [BrainGraphRefDTO]?
}
public struct BrainGraphEdgeDTO: Codable, Sendable, Equatable { public let from: String; public let to: String; public let kind: BrainLinkKindDTO; public let weight: Double? }
public struct BrainGraphResponse: Codable, Sendable { public let generatedAt: Date; public let truncated: Bool; public let vaults: [BrainGraphVaultDTO]; public let nodes: [BrainGraphNodeDTO]; public let edges: [BrainGraphEdgeDTO] }
```

- Decoding is tolerant where the old graph DTOs are: an unknown node or link kind makes that element fail softly (drop the node or edge, keep the response), missing optional keys decode to nil, missing `truncated` decodes to false.

- [ ] **Step 1: Write failing tests** with JSON captured from the Go server's own tests or OpenAPI example (read `LuminaVaultServerV2/api/openapi.yaml`, `BrainGraph*` schemas, on its `origin/main`): a full response decodes; uppercase uuids decode into `UUID`; a hub node has nil `vaultID` and its id is kept verbatim; an entity hub's `refs` decode; a `similar` edge carries `weight`; an unknown `kind` on one node drops that node only; a response without `truncated` decodes to false; every public type is `Sendable` (compile-time check through a generic function).
- [ ] **Step 2:** `swift test --filter BrainGraphDTOTests` fails to compile.
- [ ] **Step 3: Implement.** Public memberwise inits for every type (tests and the client's mocks need them). Use the package's existing `JSONDecoder` date strategy helpers if it has them; check how `MemoryGraphNodeDTO` tests decode dates.
- [ ] **Step 4:** `swift build`, `swift test`, `make lint` pass.
- [ ] **Step 5:** Commit `feat(dto): brain graph across vaults (5.34.0)`. Open a PR. Do not tag.

### Task 2: API client (repo `IOS`)

**Files:**
- Create: `API/Brain/BrainGraphEndpoints.swift`, `BrainGraphClientProtocol.swift`, `BrainGraphHTTPClient.swift`, `Features/Brain/Model/BrainGraphRequest.swift`; tests `LuminaVaultClientTests/BrainGraphRequestTests.swift`; mock `LuminaVaultClientTests/Mocks/MockBrainGraphClient.swift`
- Modify: wherever `MemoryGraphHTTPClient` is constructed and injected (find it from `MainTabView.swift`), to also build the new client; the Xcode project's package pin (temporary branch pin, see Global Constraints)

**Interfaces:**
- Produces:

```swift
struct BrainGraphRequest: Equatable, Sendable {
    var vaults: [UUID]?      // nil = all
    var focus: String?
    var depth: Int           // clamped 1...3
    var similar: Bool
    var query: String        // "/v1/brain/graph?..." — same rules and parameter order as web graphQuery
}
protocol BrainGraphClientProtocol: Sendable { func fetchGraph(_ request: BrainGraphRequest) async throws -> BrainGraphResponse }
```

- The endpoint sets `presentsPaywallOn402 = false`, like the old graph endpoint. The request does not send `X-Vault-ID` semantics beyond what `BaseHTTPClient` always adds (the route ignores it).

- [ ] **Step 1: Write failing tests** mirroring `WEB/src/lib/brain/brain-api.test.ts` case by case (unfocused default `limit=800`; `similar` appended last; focused drops `author` and `limit` and adds `focus` and `depth`; author focus keeps `author`, sends `limit=800`, depth 1; vault ids uppercased and comma-joined; depth clamped).
- [ ] **Step 2:** Build and run the test file; it fails.
- [ ] **Step 3: Implement.**
- [ ] **Step 4:** Tests pass; app builds with no new warnings.
- [ ] **Step 5:** Commit `feat(brain): graph request and API client`.

### Task 3: Graph model

**Files:**
- Create: `Features/Brain/Model/BrainGraphModel.swift`; tests `BrainGraphModelTests.swift`

**Interfaces:**
- Produces: `BrainGraphFilters` (`links: [BrainLinkKindDTO: Bool]`, `vaults: Set<UUID>?`, `showOrphans`, `colourBy`), `BrainGraphIndex` (`byID`, `neighbours`, `edgesOf`), `VisibleBrainGraph` (`nodes`, `edges`, `index`), and pure functions `visibleGraph(_:filters:)`, `litSet(_:ids:)`, `groupMembers(_:hubID:)`, `searchNodes(_:query:limit:)`, `colourKey(_:by:index:)`, `isHub(_:)`, `defaultFilters()`. All `Sendable`, no UI imports.
- Same seven rules, in the same order, as `WEB/src/lib/brain/graph-model.ts`.

- [ ] **Step 1: Write failing tests** by porting `WEB/src/lib/brain/graph-model.test.ts` case by case, including the 2,000-node timing guard (under 30 ms in release configuration; skip the timing assertion in debug).
- [ ] **Step 2:** Fails. **Step 3:** Implement with single passes and dictionary/set lookups. **Step 4:** Passes.
- [ ] **Step 5:** Commit `feat(brain): pure graph model`.

### Task 4: Selection and tray rules

**Files:**
- Create: `Features/Brain/Model/BrainSelection.swift`, `BrainTrayActions.swift`; tests for both

**Interfaces:**
- Produces: `@MainActor @Observable final class BrainSelection` (`selected: [String]`, `click(_:additive:)`, `selectGroup(_:additive:)`, `remove(_:)`, `clear()`, `prune(visible:)`, `highlight(index:) -> BrainHighlight`), `struct BrainHighlight { selected: Set<String>; lit: Set<String>? }` (no hover on touch), and `BrainTrayActions`: for a selection and index, each of Open / Focus / Select group / Explain connection / Ask as enabled or disabled with a reason string, plus `explainTarget(_:_:activeVault:)` and the prefilled question (first five labels, then "and N more").
- Rules are those of `WEB/src/lib/brain/selection.svelte.ts` and `tray-actions.ts`; additive selection comes from a long press.

- [ ] **Step 1:** Port `selection.test.ts` and `tray-actions.test.ts` case by case. **Step 2:** Fail. **Step 3:** Implement. **Step 4:** Pass.
- [ ] **Step 5:** Commit `feat(brain): selection and tray rules`.

### Task 5: Graph store

**Files:**
- Create: `Features/Brain/Model/BrainGraphStore.swift`, `BrainPrefs.swift`; tests for both

**Interfaces:**
- Produces: `@MainActor @Observable final class BrainGraphStore` with `state` (`.loading`, `.loaded(BrainGraphResponse)`, `.missingFocus`, `.failed(String)`), `refreshing`, `rateLimited`, `refreshError`, `stale`, `loaded: BrainGraphRequest?`, `knownVaults`, `truncatedCount: Int?`, `sync(_:)`, `retry()`, `dispose()`. Debounce through an injected clock so tests do not sleep. `BrainPrefs` persists link toggles, show-unlinked, colour-by and the 2D/3D choice in `UserDefaults` under one key, tolerant of unknown or corrupt values.
- Behaviour is that of `WEB/src/lib/brain/brain-graph-view-model.svelte.ts` after the final fix wave, including: a failed or missing-focus state always refetches on the next `sync`; superseded requests are cancelled; a response that arrives after a newer request started is ignored; `dispose` stops late writes.

- [ ] **Step 1:** Port `brain-graph-view-model.test.ts` and `brain-prefs.test.ts` case by case, with `MockBrainGraphClient` and a test clock. Add: a task cancelled by SwiftUI (`error.isBenignCancellation`) restores the previous state.
- [ ] **Step 2:** Fail. **Step 3:** Implement. **Step 4:** Pass.
- [ ] **Step 5:** Commit `feat(brain): graph store with request rules`.

### Task 6: 2D layout off the main actor

**Files:**
- Create: `Features/Brain/Layout/GraphLayout2D.swift`; tests `GraphLayout2DTests.swift`

**Interfaces:**
- Produces: `actor GraphLayout2D` with `func setGraph(_ graph: VisibleBrainGraph)` (keeps positions of known ids, seeds new ids from a hash of the id near their placed neighbours, parks hidden ids), `func positions() -> [String: CGPoint]`, `func pin(_ id: String, at: CGPoint?)`, and `var updates: AsyncStream<LayoutSnapshot>` delivering at most 30 snapshots a second while the simulation is warm and one final snapshot when it settles. `LayoutSnapshot` is `Sendable` (`ids: [String]`, `points: [CGPoint]`, `settled: Bool`). A pure, synchronous `struct ForceSimulation2D` holds the maths so it can be tested without the actor.
- Forces as on web: link distance 40 for hub edges, 60 for `link`/`source`, 90 for `similar`; repulsion with a distance cap through a spatial grid; weak centring; collision at radius + 2. Radius formulas as web `nodeRadius`.

- [ ] **Step 1: Write failing tests** on `ForceSimulation2D`: deterministic for the same input in any order; known ids keep their positions when the node set changes; a linked pair ends closer than an unlinked pair; no two points closer than their radii after settling; 1,000 points settle in under 600 ms of CPU in release; the stream ends with `settled == true` and then yields nothing more until `setGraph` or `pin` is called.
- [ ] **Step 2:** Fail. **Step 3:** Implement (reuse the grid idea from the old `BrainGraphEngine.swift`). **Step 4:** Pass.
- [ ] **Step 5:** Commit `feat(brain): 2D force layout off the main actor`.

### Task 7: 2D canvas

**Files:**
- Rewrite: `Features/Brain/Render/BrainGraphCanvas.swift` (moved); create `Features/Brain/Render/BrainGraphTheme.swift`; tests `BrainGraphCanvasLogicTests.swift`; snapshot suite `BrainGraph2DSnapshotTests.swift`

**Interfaces:**
- Consumes: `VisibleBrainGraph`, `BrainHighlight`, `LayoutSnapshot`.
- Produces: `struct BrainGraphCanvas: View` with inputs `graph`, `highlight`, `colourOf: (BrainGraphNodeDTO) -> Color`, and callbacks `onTap(id, additive)`, `onBackgroundTap()`, `onOpen(id)` (double tap); a `BrainGraphViewport` value (`scale`, `offset`, `isAutomatic`) with pure functions for fit, recentre-on-resize and the automatic-view rule (as web `nextAutoView` / `resizeAction`); pure label helpers (visibility rule, placement below / above / right avoiding circles, at most 160 labels, small-graph rule at 80 points).

Behaviour: as the web 2D renderer. Points filled by colour, hubs as rings, selected ring in the highlight token, everything outside the lit set at 0.12 opacity and its labels hidden, label plates in the background colour. Redraw only when a snapshot, the viewport, the highlight or the theme changed: the `TimelineView` is paused otherwise and when the tab is not visible. Gestures: tap, double tap, long press (additive), drag on a point moves and pins it, drag on background pans with inertia, pinch zooms 0.15 to 6. Hit radius is `max(radius, 22 pt / scale)`. The view stays automatically fitted until the user pans or zooms. VoiceOver: the canvas is one element labelled "Graph of N notes and memories. Use the list to browse." and not focusable beyond that.

- [ ] **Step 1: Write failing tests** for the pure helpers (port the relevant cases from `WEB/src/lib/brain/render-2d.test.ts`).
- [ ] **Step 2:** Fail. **Step 3:** Implement. **Step 4:** Pass; add `#Preview`s with a 25-point and a 600-point fixture in light and dark; add the snapshot suite (25-point graph: at rest; with a selection; light and dark).
- [ ] **Step 5:** Run the app in the simulator against a stubbed client and look at it: screenshots at rest, selected, zoomed; fix what looks wrong.
- [ ] **Step 6:** Commit `feat(brain): 2D graph canvas`.

### Task 8: Brain screen

**Files:**
- Rewrite: `Features/Brain/BrainTabView.swift`; create `BrainFilterSheet.swift`, `BrainListView.swift`; modify `Features/MainTabView.swift` (client injection); tests `BrainTabStateTests.swift`; UI test `BrainGraphUITests.swift`

Behaviour:
- Navigation bar: inline title "Brain"; `.searchable` ("Search notes and memories", suggestions from `searchNodes`, picking one selects it and centres on it); one primary action (Filters, with a badge when filters differ from default) and an overflow menu (2D / Constellation, List, Reload). The capture toolbar item stays.
- A quiet line under the bar: "N notes and memories · M connections", plus "Most recent 800 shown" when truncated and "Showing an earlier graph · Retry" when stale.
- `BrainFilterSheet` (medium detent): connection kinds as toggles with their colour dot (the legend), Similar off by default with "No similar notes found." when empty, vault chips (the last one cannot be turned off), Colour by (Vault, Space, Author, Type) with a legend of the visible keys, Show unlinked notes, depth stepper when focused, Authors and Colour by Author disabled with "Not shown in a focused graph" when focused on a non-author, Reset. Toggles filter in place.
- `BrainListView`: a full-screen sheet listing visible notes and memories (label, kind, vault, "K connections"), sorted by weight, searchable; rows toggle selection (`.isSelected` trait). This is the VoiceOver and Switch Control path.
- States: first load "Mapping your notes…"; refreshing shows a thin progress indicator in the bar and keeps the graph; empty "Nothing to map yet" with a capture button (`LVEmptyState`); failed with Retry, plus "Show all vaults" when the request named vaults; missing focus "That is no longer in your graph. It may have been deleted." with "Show full graph"; "Nothing matches these filters" with Reset.
- Focus: `focus` and `depth` are view state set by the tray or a deep link; a "Full graph" button appears in the bar when focused; a focused graph selects its focus point once on load.
- Derivation order on every change: build `visible` → `selection.prune` → renderer data → renderer highlight.
- No `if #available` branches; no layer picker.

- [ ] **Step 1: Write failing tests** for the screen's pure state mapping (which state card for which store state and filter result; the badge count; the status line text).
- [ ] **Step 2: Write failing UI tests** against a stubbed client (launch argument): counts line; a filter toggle changes counts and makes no request; a vault chip makes exactly one request; search selects; list row selection shows a chip; empty, failed and missing-focus states.
- [ ] **Step 3:** Fail. **Step 4:** Implement. **Step 5:** Pass. Look at it in the simulator on an iPhone and an iPad, light and dark, large Dynamic Type; fix what looks wrong.
- [ ] **Step 6:** Commit `feat(brain): graph screen, filters and list`.

### Task 9: Selection tray, detail, reasoning

**Files:**
- Create: `Features/Brain/BrainSelectionTray.swift`; modify `BrainNodeDetailSheet.swift`, `KnowledgeReasoningSheet.swift`, `KnowledgeReasoningViewModel.swift`, `BrainTabView.swift`; tests; delete `KnowledgeGraphProjection.swift` and its tests

Behaviour:
- Tray in the bottom safe-area inset when at least one point is selected: "N selected", chips (kind icon, label, remove button "Remove <label> (<kind>)"), horizontally scrolling; actions Open, Focus, Select group, Explain connection, Ask, and Clear; unavailable actions stay visible, disabled, with the reason as accessibility hint. Uses `LVSelectionChip` / `LVFlowLayout` where they fit.
- Open: a memory loads through the memory client **for the memory's own vault** (check how `BaseHTTPClient` sets `X-Vault-ID` and allow a per-request override the way the web client now does; if the client cannot, show "Switch to <vault> to open this memory" for other-vault memories and say so in the report). A note shows title, vault and Space.
- Reasoning sheet: question box, streamed answer, evidence, paths, suggested connections with Confirm / Dismiss, a line naming the active vault. Ask prefills and does not send. Explain uses `explainTarget`, else sends the prefilled question. Explaining a suggestion keeps the answer and the other suggestions. Memories named by a result join the lit set (ids uppercased, only those in the visible index, no neighbours).
- `KnowledgeReasoningViewModel` loses `load`, `graph`, `selectNode`, `selectedNodeIDs`; the knowledge graph endpoint is no longer called.

- [ ] **Step 1:** Port the remaining `tray-actions` and reasoning view-model tests; UI tests: two selected enable Explain; remove one chip; Clear; Focus makes one request without `author` in `links`; a hidden selected point leaves the tray.
- [ ] **Step 2:** Fail. **Step 3:** Implement. **Step 4:** Pass. Look at it in the simulator.
- [ ] **Step 5:** Commit `feat(brain): selection tray, detail and reasoning`.

### Task 10: Constellation

**Files:**
- Create: `Features/Brain/Layout/ConstellationLayout.swift`; rewrite `Features/Brain/Render/BrainGraphRealityView.swift`; modify `BrainTabView.swift`, `IOS/docs/DESIGN_SYSTEM.md` (§13.8 to §13.9 exception); tests `ConstellationLayoutTests.swift`

**Interfaces:**
- Produces: `struct ConstellationLayout` (pure, `Sendable`): `mutating func layout(_ graph: VisibleBrainGraph) -> (positions: [String: SIMD3<Float>], fresh: Bool)` with the rules of `WEB/src/lib/brain/constellation-layout.ts` at its final state (server `pos` scaled by the 95th percentile with outliers clamped; deterministic force layout for the rest, seeded from id hashes; known ids fixed; fresh when fewer than half the visible ids are known; bounded cost through a sampled spatial grid; newcomers pulled inside 1.5 radii). Run it off the main actor.
- `BrainGraphRealityView` takes the same inputs and callbacks as the 2D canvas.

Behaviour: stars as one entity each sharing a single mesh and a small set of materials (one per colour key in use; unlit material), sized by weight, hubs as a quieter ring mark; at most 800 stars (the request limit). Lines as one generated mesh (`LowLevelMesh` or a single `MeshResource` rebuilt only when the lit set or data changes): the lit neighbourhood, plus the 300 strongest `link` / `similar` edges at rest. Dimmed stars at 0.15. A faint static backdrop of points in dark appearance only. Background from the palette. Labels as a SwiftUI overlay of at most 24, re-ranked when the camera stops. Orbit by drag, zoom by pinch, tap / long press / double tap as in 2D with a 22 pt minimum hit radius. Updates applied in `update`, never by recreating the view: the camera survives selection, filters and theme changes. Idle turn only when nothing is selected, the tab is visible, Reduce Motion is off, after 5 s idle, capped at 30 updates a second and 90 s. Nothing runs while the tab is not visible. The 3D scene is created only when the user picks the Constellation.

- [ ] **Step 1:** Port `constellation-layout.test.ts` case by case, including the deterministic cost guard. **Step 2:** Fail. **Step 3:** Implement the layout. **Step 4:** Pass.
- [ ] **Step 5:** Build the RealityKit view; run it in the simulator and on a device if one is connected, with 25, 400 and 800 points; look at screenshots in light and dark; record frame times with an `XCTOSSignpostMetric` or Instruments run if available, and say plainly which you could and could not measure.
- [ ] **Step 6:** Add the Constellation to the allowed list in `DESIGN_SYSTEM.md` §13.8 to §13.9 with one sentence saying why.
- [ ] **Step 7:** Commit `feat(brain): RealityKit constellation behind a switch`.

### Task 11: Entry points and vault changes

**Files:**
- Modify: `Features/Memory/MemoryDetailSheet.swift` (or `MemoryDetailView.swift`), `Services/.../NotificationRouter.swift`, `Features/MainTabView.swift`, `BrainTabView.swift`; tests

Behaviour: "Show in graph" on the memory detail switches to the Brain tab focused on that memory (id uppercased). A `brain` route in `NotificationRouter` accepts an optional focus id. When `ActiveVaultStore` changes, the reasoning sheet's vault line and `explainTarget` use the new active vault; the graph request does not change (it already covers all vaults), so no request is made.

- [ ] **Step 1:** Tests for the router case and for "active vault change makes no graph request". **Step 2:** Fail. **Step 3:** Implement. **Step 4:** Pass.
- [ ] **Step 5:** Commit `feat(brain): show in graph, deep link, active vault`.

### Task 12: Remove the old screen, measure, verify

**Files:**
- Delete: `BrainGraphEngine.swift`, `BrainGraphViewModel.swift`, their tests, `MockMemoryGraphClient.swift`, `API/Memory/MemoryGraph*.swift` and `KnowledgeGraph` graph-fetch code if nothing else uses them (grep first; `RelatedMemoriesSheet` and Home use other endpoints and stay)
- Modify: the Xcode project's package pin to the released `SHARED` version (after the owner approves the tag)

- [ ] **Step 1:** Delete and fix references; build with no warnings.
- [ ] **Step 2:** Measure with XCTest performance tests on the simulator and, if connected, a device: 2D pan and zoom at 1,000 points (signpost intervals around draw), idle CPU after settle (zero draws over 2 s), memory across ten 2D↔3D switches. Record numbers and what they were measured on.
- [ ] **Step 3:** Full unit, snapshot and UI test run on the CI simulator destination.
- [ ] **Step 4:** Commit `chore(brain): remove the old graph and record measurements`.
