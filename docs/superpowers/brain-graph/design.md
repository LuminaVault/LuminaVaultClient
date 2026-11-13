# Second brain graph: one Obsidian-style graph across vaults

## Context

The Brain screen is meant to be a second brain, but today it is not Obsidian-like:

- Web (`/brain`) and iOS (Brain tab) both draw an unlabeled 3D point cloud. Position comes from note-embedding projection, not from links, so connections barely shape what you see.
- The server (`GET /v1/memory/graph`, Go, live) already computes tag / space / similar / time edges, but web throws the edge kind away and iOS draws colours that do not match its legend.
- Real `[[wikilinks]]` (`vault_links`) are in no graph. There is no author link, no cross-vault view, and people/entities live in a separate "Knowledge" layer behind a toggle.
- Selecting is awkward: on iOS a tap opens a sheet and the only deselect is closing it; each Knowledge tap resets the camera; on web the second click fires an API call, every click flies the camera, and there is no Escape, search or legend.
- iOS already has a 2D force engine (`BrainGraphEngine`, `BrainGraphCanvas`) that is dead code behind `if #available(iOS 18)`.

Owner decisions (2026-11-11):

1. Connect points by **theme (tag)**, **vault**, and **actor = author** (same author is the main meaning; people/things mentioned are a second, separate link type).
2. **2D Obsidian-style graph is the default**, with a switch to a fixed and better-looking 3D "constellation". Watch FPS, frame drops, memory and bandwidth.
3. **All my vaults together** in one graph.
4. **One graph**, no Knowledge/Memories toggle. Reason/Explain becomes a panel acting on the selection.

All server work goes in the Go server (`LuminaVaultServerV2`). Nothing changes in the Swift server.

## Approach

Three pieces, shipped in this order, one PR per repo: Go endpoint, web, iOS. Existing `/v1/memory/graph` and `/v1/knowledge/*` stay untouched, so released clients and Swift parity are unaffected.

### 1. Server: new `GET /v1/brain/graph` (Go only)

New small module `internal/modules/brain` (reference pattern: `internal/modules/knowledge`). Read-only, computed per request, **no new tables and no migrations** (this avoids the goose/Swift schema-parity rule).

Hub model, as Obsidian does for tags: shared attributes become hub nodes with one edge per member, so edges grow linearly rather than as all-pairs.

- **Item nodes:** `note` (vault file) and `memory`.
- **Hub nodes:** `tag`, `author`, `entity`, `space`. A hub is emitted only when it has two or more members. Tag, author and entity hubs are shared across vaults (keyed by tag text, author identity, entity `canonical_key`), which is what ties vaults together. Space hubs are per vault.
- **Direct edges:** `link` (resolved rows of `vault_links`, note to note: the real Obsidian link, new to the graph), `source` (memory to the note it came from; today mislabelled `wikilink`), `similar` (top-k nearest by embedding, opt-in).
- **Vault:** not a hub. Every node carries `vaultID` and the response lists `vaults[{id,name}]`; clients colour and cluster by it.
- **Author:** `created_by_user_id` for people, plus `memory_contributions` (`actor_kind = model`, provider/model) for AI authors. The wire and UI say "author"; "actor" already means three other things in this codebase.
- **Entity:** `knowledge_nodes` of kind `entity`, joined to memories through `knowledge_evidence`. Read-only; the Swift extraction worker keeps filling the tables until it is ported.

Request: `vaults` (CSV, default every vault the caller can read), `links` (CSV of edge kinds), `limit` (default 400, max 2000), `focus` + `depth` (1 to 3) for a local graph around one node.

Response: `{generatedAt, truncated, vaults[], nodes[{id, kind, label, vaultID?, spaceID?, weight, createdAt?, pos?}], edges[{from, to, kind, weight?}]}`. No bodies, no evidence, no provenance blobs.

Bandwidth and load:
- `ETag` over the payload and `304` on `If-None-Match`; gzip as the server already does.
- Filters applied in SQL, not after reading 2000 rows (the current handler's weakness in `internal/modules/memory/graph.go:258-280, 416-445`).
- `similar` via a per-node `LATERAL` top-k lookup instead of the all-pairs self-join (`graph.go:518-537`), and only when requested.
- Add the tier-scaled rate limit that `/v1/memory/graph` lacks.

Vault access: enumerate the caller's vaults with a read-only query against `vault_memberships` inside the new module and check each through the existing `vaultaccess.Service.ResolveVault` (`internal/vaultaccess/vaultaccess.go:89`). **Do not edit `internal/vaultaccess` or `internal/modules/vault`**: another agent is working there.

Conventions to follow: spec first in `api/openapi.yaml` with `x-lv-module`, `oapi-codegen.yaml` include list, hand-written Echo v5 handler, `make gen`, tests on `dbtest.Postgres` validated against the spec.

Open item to settle in the first task: the route manifest (`docs/migration/routes.json`, `scripts/gen-modules.py`, `internal/manifest/manifest_test.go`) is generated from Swift sources and has no precedent for a Go-only route. Reuse whatever the quick-bug-capture plan (`docs/superpowers/plans/2026-11-06-quick-bug-capture.md`) settled for native routes; if that is not yet implemented, add the smallest "native" marker the manifest test accepts. Production ingress also needs `/v1/brain` routed to `api-go-production` in the infra repo (`~/Work/production/platform/infra`), which deploys on merge.

### 2. Shared behaviour on web and iOS

Same model on both, so it is designed once.

**Selecting** (selection never triggers an API call or a camera move):
- Hover (web) or tap: the point and its neighbours light up, the rest dims, labels appear for the lit set.
- Tap the same point, tap empty space, or press Escape: deselect.
- Shift-click (web) or long-press (iOS): add or remove from a multi-selection.
- A selection tray lists the picked points as chips, each with its own remove button, plus Clear.
- Actions are explicit buttons on the tray: **Open** (note or memory detail), **Focus** (local graph, depth 1 to 3), **Explain connection** (exactly two selected), **Ask** (reasoning over the selection).
- Tapping a hub selects its whole group (all notes with that tag, author, entity or Space).

**Finding and filtering** (one panel, Obsidian-style):
- Search with jump-to-node.
- Link-type toggles: Links, Tags, Authors, Mentions, Spaces, Similar. One colour per type, taken from the palette, and the same colours in the legend and on the canvas.
- Vault chips (all on by default), "show orphans", depth when focused.
- Colour points by vault (default), Space, author or type.
- Toggles filter in place with no refetch and no spinner. Only a change of vault set or focus refetches.

**Getting there:**
- "Show in graph" from note and memory detail opens the graph focused on that point.
- Deep link `brain?focus=<id>`.
- Existing tab, sidebar and command-palette entries stay.

**Reasoning:** the old Knowledge layer's Reason/Explain tools become a side panel (web) or sheet (iOS) fed by the selection. Explain uses entity hubs' knowledge ids; for notes it falls back to the reason endpoint with the selected titles. Claims and events stop being drawn as points.

**3D constellation (the switch):** points as star sprites with size and brightness by weight, faint lines only for the selected neighbourhood plus the strongest links, positions from the server's `pos`. No per-node sphere meshes, no heavy bloom.

Performance budget for both: 60 fps while interacting on 1,000 points, nothing redrawn when at rest, simulation paused when hidden or off-screen, labels culled by zoom level.

### 3. Web (`LuminaVaultWebApp`, stay inside `src/lib/brain/`, `src/lib/components/brain/`, `src/routes/(app)/brain/`)

- New 2D renderer as the default. Proposed library: `force-graph` (the 2D canvas sibling of the `3d-force-graph` already in use, same data shape). The dependency must pass the Sonatype check before install; that MCP server is currently failing auth, so this needs the token renewed or an explicit waiver.
- `three` + `3d-force-graph` (about 403 KB gzipped) load only when the user switches to 3D.
- Rewrite `graph-3d.ts` to the constellation design: one `Points` object with a shared material, dispose on teardown, update data in place instead of destroying the scene on every URL change (`+page.svelte:79-170`), re-read palette tokens on theme change, cap device pixel ratio.
- Replace `brain-view-model.svelte.ts` and `knowledge-view-model.svelte.ts` with one view model on `/v1/brain/graph`; keep the reasoning calls. This removes the broken singular `provider/model/source` filter params.
- Replace `BrainFilterBar` (four native selects) with the filter panel; rework `BrainHud`, `BrainNodeSheet`, `ReasoningWorkbench` into the tray and side panel so the filter bar and workbench stop sharing the top-right corner.
- Point `npm run gen:api` at `LuminaVaultServerV2/api/openapi.yaml` for the new types (it currently reads the Swift spec).
- Keyboard: Escape, `/` to search, arrow keys through neighbours. Provide a list alternative to the canvas for accessibility.
- Tests: view-model unit tests (selection state machine, filter-in-place), Playwright mock for `/v1/brain/graph` in `e2e/fixtures/`, theme-switch-without-reload case.

### 4. iOS (`LuminaVaultClient`, `Features/Brain/`)

- Make the 2D graph the default: revive `BrainGraphEngine` + `BrainGraphCanvas`, move the physics step off the main actor, add labels with a zoom threshold, neighbour highlight, hit targets of at least 44 pt, tap-empty-space to clear.
- Rebuild `BrainGraphRealityView` as the constellation: one shared mesh and material, one entity per point instead of three, palette tokens instead of hard-coded hexes and `Color.black`, and updates applied in `update` so the camera survives selection and filter changes (drop the `.id(identity)` rebuild at `BrainTabView.swift:261, 274`).
- One view model on the new endpoint replacing `BrainGraphViewModel` plus the projection in `KnowledgeGraphProjection.swift`; add DTOs to `LuminaVaultShared/Sources/LuminaVaultShared/APIDTOs.swift`.
- Toolbar per `docs/DESIGN_SYSTEM.md` §13.7: one primary action plus an overflow menu; 2D/3D switch and filters in the bottom bar; stock `.searchable`.
- Reuse `LVSelectionChip`, `LVChipGrid`, `LVFlowLayout`, `MemoryDetailSheet`, `.lvProminent`. Delete the private `FlowLayout` copy in `BrainNodeDetailSheet`.
- "Show in graph" from `MemoryDetailSheet`; a `brain` case in `NotificationRouter.swift` for the deep link; refresh when `ActiveVaultStore` changes.
- `DESIGN_SYSTEM.md` §13.8 to 13.9 bans glow and particles outside a short list of surfaces. The constellation view is an owner-requested exception and gets added to that list in the same PR.
- Expect a four-line merge conflict in `BrainTabView.swift` with the `feat/quick-assistant` worktree.
- Tests: selection state machine and filter-in-place in the view-model tests, engine tests for settle and hit-testing, a snapshot suite for the 2D graph, `#Preview`s with fixture graphs.

## Not in this plan

- Porting the Swift extraction, layout and theme workers to Go (migration wave 6 to 8).
- Editing links from the graph, or saving graph views.
- Changes to `/v1/memory/graph`, `/v1/knowledge/*` or the dashboard preview.

## Verification

- Server: `make gen`, `make check`, module tests covering two vaults (shared tag hub, shared author hub, no access to a third vault's nodes), `focus`/`depth`, `ETag` 304, and spec validation. Then `curl` the endpoint on a local run with two seeded vaults and compare payload size with `/v1/memory/graph`.
- Web: `npm run check`, `npm run lint`, `npm run test:unit`, `npm run test:e2e`; then drive `/brain` in Chrome: select, multi-select, Escape, search, toggle each link type, switch 2D/3D, switch theme without reload, and record frame rate with 1,000 points in the performance panel.
- iOS: unit and snapshot tests, then the simulator and one real device: tap, long-press, clear, filters without spinner, 2D/3D switch keeping selection, Instruments for frame time and memory on 1,000 points.
- After the infra ingress change merges: call `/v1/brain/graph` against production with the owner's account and confirm both vaults appear.

## Final polish pass (owner request, after all three pieces are done)

- Web: run the `impeccable` skill in polish mode on `LuminaVaultWebApp` (brain files) to strip AI-slop visuals and copy.
- iOS: run the `impeccable-swift` skill in polish mode on `LuminaVaultClient` (`Features/Brain/`). The owner called it `/impeccable-ios`; the installed skill is named `impeccable-swift`.
- Re-run each repo's tests and the manual checks above after the polish changes.

## First step on approval

Save this as `docs/superpowers/specs/2026-11-11-second-brain-graph-design.md`, then write the task-level plan for piece 1 (server) with superpowers:writing-plans.
