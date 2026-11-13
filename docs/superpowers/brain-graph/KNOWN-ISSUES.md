# Brain graph (iOS): known issues

Shipped with PR #224 (merged 2026-11-13, `92cd3c0`). None blocks use. Each entry says what happens, where the code is, what is already known, and where to start.

## 1. Memory grows on each 2D ↔ Constellation switch

- **What happens:** about 0.7 MB per round trip (2D → Constellation → 2D). A control that opens and closes a sheet grows about 0.26 MB.
- **Measured on:** simulator, Debug build, low machine load. Never measured on a device or in a Release build: the UI test harness that drives the switch exists only in Debug.
- **Already ruled out:** every RealityKit entity is removed when the Constellation disappears, and every scene object is freed. Removing all entities on disappear made no difference.
- **Where:** `Features/Brain/Render/BrainGraphRealityView.swift`, `ConstellationScene.swift`, `ConstellationMeshes.swift` (`ConstellationSharedMeshes`), `ConstellationLabels.swift`.
- **Start with:** Instruments (Allocations, generations) on a device in a Release build, ten round trips. Check first whether the growth is in our code at all or in RealityKit / Metal caches (shared meshes, materials, label textures), and whether it levels off after more round trips.

## 2. The Constellation shows at most 800 points and does not say so

- **What happens:** past 800 points the lightest ones are dropped. A dropped point can still be selected (it has a chip in the tray but no star), and centring on it from search does nothing.
- **Where:** `Features/Brain/Render/ConstellationRules.swift` (the cap, around line 228).
- **Start with:** show a line such as "Showing the 800 most connected of N" when the cap applies, and make search and selection of a dropped point either switch to 2D or say that the point is not shown here.

## 3. The selection tray lies over the bottom of the graph

- **What happens:** the tray is laid over the graph instead of resizing it, so points and labels under the tray are hidden until the graph is panned. This was chosen so that selecting a point never moves the camera (before, selecting moved a 2D point by 24 pt).
- **Related:** the first search centres using an estimated tray height of 120 pt, because the tray has not been measured yet; it can sit slightly off-centre once. The tray is capped at half the canvas height and scrolls beyond that.
- **Where:** `Features/Brain/BrainTabView.swift` (the `.overlay(alignment: .bottom)` tray and `bottomInset`), `BrainSelectionTray.swift`, `Render/BrainCentreRequest.swift`.
- **Start with:** decide whether the selected point should be nudged clear of the tray when it would be covered (an explicit, animated camera move only in that case). Open design question: is half the canvas the right cap?

## 4. A `brain` deep link that arrives under one of Brain's own sheets is applied underneath

- **What happens:** if the filter, detail or reasoning sheet of the Brain tab is open when a `brain` deep link or "Show in graph" arrives, the graph changes behind the sheet and the sheet stays open.
- **Where:** `Features/Brain/BrainTabView.swift` (entry handling, around lines 353 to 367), `Model/BrainEntry.swift`, `BrainShowInGraph.swift` (`closesOnShowInGraph()` covers the six sheets outside the Brain tab only).
- **Start with:** close the Brain tab's own sheets when an entry is applied, the same way the outside sheets close.

## 5. Grape is still linked in the project

- **What happens:** nothing imports Grape any more (the old graph is deleted), but the package is still a dependency in `LuminaVaultClient.xcodeproj/project.pbxproj` and in `Package.resolved`. It costs resolve and build time only.
- **Start with:** remove the package reference and product dependency in Xcode, rebuild, commit the project file and `Package.resolved`.

## Not yet verified (no defect known)

- 60 fps at 1,000 points on a phone. Only the simulator was measured.
- Recovery from a touch the system cancels (put one finger down, then a second), and the VoiceOver double tap on the graph. Both fixes rest on reading the code; they need a device.
- "Show in graph", the deep link and the tab switch inside the real `MainTabView`. The test harness has no tab bar, so this needs a signed-in run.
- After the merge of `main`, the Quick Assistant card and a Brain sheet opening at the same time. Main's guard for this sat in code the new screen no longer has; the new sheets open straight from a tap, so it should not be reachable. One manual check is enough.

## Smaller follow-ups

- `BrainChipFlow` in `BrainFilterSheet.swift` duplicates `LVFlowLayout`.
- Six negative assertions in `GraphLayout2DTests` wait 20 ms of real time and could pass under load when they should fail.
- On a theme switch the graph draws one frame with the old point colours.
- There is no error colour in the palette; errors use the accent colour with a warning glyph.
- `docs/DESIGN_SYSTEM.md` contradicts itself on constellation backdrops (§13.9 allows the Constellation; §13.8 and §14 rule starfields out on a tab root).

The full decision ledger is `ledger-ios.md` in this folder; the session reports are kept outside the repository under `docs/superpowers/handoff/` in the workspace.
