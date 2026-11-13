# SDD ledger — plan: /Users/fernandocorreiachill/Work/production/apps/lumina/docs/superpowers/plans/2026-11-11-brain-graph-ios.md
Spec: /Users/fernandocorreiachill/Work/production/apps/lumina/docs/superpowers/specs/2026-11-11-second-brain-graph-design.md
Two repos. Task 1 in LuminaVaultShared (worktree .worktrees/brain-graph, branch feat/brain-graph, MERGE_BASE 32980ba). Tasks 2-12 in LuminaVaultClient (worktree to be created). This ledger file lives in the Shared worktree for Task 1; the client ledger will be in the client worktree's .superpowers/sdd/2026-11-11-brain-graph-ios/.

## Preflight scan
| Tasks | Produces vs consumes | Finding |
|---|---|---|
| 1 -> 2..12 | BrainGraph DTOs via a released package version | Client pins Shared by version; tag v5.34.0 needs the owner's go-ahead (publish). Ruling: client work proceeds on a temporary branch pin in its worktree; Task 12 replaces it with the version pin |
| 2 -> 5 | BrainGraphRequest, BrainGraphClientProtocol | consistent |
| 3 -> 4,5,7,8,9,10 | VisibleBrainGraph, index | consistent |
| 4 -> 8,9 | BrainSelection, BrainHighlight, tray rules | consistent |
| 5 -> 8 | BrainGraphStore | consistent |
| 6 -> 7 | LayoutSnapshot stream | consistent |
| 7,10 -> 8 | canvas / reality view with identical inputs | Task 8 is listed before 10; Task 8 wires only 2D and Task 10 adds the switch — consistent |
| 9 self | Open for a memory in another vault needs a per-request vault header in BaseHTTPClient | Ruling: allowed if it is a minimal, additive change (same as web's one-line client change); otherwise fall back to the "Switch to <vault>" message |
| 12 self | package pin swap depends on the tag | Stop-class: publish; owner go-ahead |

## Progress
Task 1: dispatched (sonnet), BASE 32980ba
Task 1: implementer af344bfae69541a59, commit 5f60f44 (DONE): 14 new tests, suite 198 pass; version recorded only as git tags
Task 1: review (sonnet): Approved. Server emits whole-second UTC "Z" timestamps; client decodes with .iso8601 → agree. ⚠️ resolved by controller: swift test run (see below).
Task 1: minor (deferred): missing top-level vaults/nodes/edges decode to empty instead of failing; dropped elements are not counted
Task 1: complete (commits 32980ba..5f60f44, review clean)
Shared PR opened: https://github.com/LuminaVault/LuminaVaultShared/pull/65 at 5f60f44 (not merged, not tagged — owner go-ahead needed for v5.34.0). swift test 198/198 run by controller.
Client worktree: /Users/fernandocorreiachill/Work/production/apps/lumina/.worktrees/brain-graph-client, branch feat/brain-graph, MERGE_BASE 3a93726. Project uses file-system-synchronized groups (new files need no pbxproj edit). This file is now the live ledger.
Task 2: dispatched (sonnet), BASE 3a93726
Owner 2026-11-11: merge web #110 → merged 1a40954 (squash). Shared #65 merged 28a262c (squash), NO tag (owner: not needed for Vapor; controller explained the iOS app is the consumer — open choice: tag v5.34.0 or pin the app to revision 28a262c). Production promotion: owner said "yes"; controller has no cluster access (kubeconfig readable only by another OS user) → opened DRAFT infra PR https://github.com/LuminaVault/LuminaVaultInfra/pull/595 (api-go production → f53d14f + /v1/brain route), G2 checklist unfilled, not merged.
Task 2: implementer af045675281219c56, commits 51a51d8 (TEMPORARY branch pin) and f65e52f (DONE_WITH_CONCERNS: observations). Test command: xcodebuild test -project LuminaVaultClient.xcodeproj -scheme LuminaVaultClient -configuration Debug -destination "platform=iOS Simulator,id=F4A79358-3F5C-48E0-A5B6-9760EBC3BBCC" -derivedDataPath $PWD/.superpowers/dd -only-testing:LuminaVaultClientTests/<Suite>. Untracked local config copied from .sample files. Project default isolation is MainActor: pure model types must be `nonisolated`.
Task 2: review (sonnet): Approved; query strings match web graphQuery on six cases; concurrency sound; pin isolated; no local files committed. ⚠️ resolved by controller: branch feat/brain-graph exists on the Shared remote at 5f60f44 (ls-remote over https earlier); implementer built and ran tests (12/12, 8/8).
Task 2: minor (deferred): web joins vault ids as given while iOS uppercases (web ids already uppercase)
Task 2: complete (commits 3a93726..f65e52f, review clean)
Tasks 3+4: batched, implementer afe3163ee6addd873 (sonnet), BASE f65e52f, running
Owner 2026-11-11: does not want to decide tag vs pin, and questioned tagging. Ruling: NO tag. Task 12 replaces the temporary branch pin with a REVISION pin to LuminaVaultShared main commit 28a262c128605ad02354ef18ddf9c46c6b7bc638 (content identical to feat/brain-graph 5f60f44) — uses only what is merged, publishes nothing — cost if wrong: the app's package requirement style changes from version to revision; one-line change back once a version is tagged
Tasks 3+4: commits 46fd6ce, ce121f9 (DONE): 69 web cases ported, 5 skipped (hover); 81 tests green; 2,000-node filter ~10 ms in Debug
Tasks 3+4: review (sonnet) at ce121f9: ports faithful (seven visible rules, selection, tray rules, every string identical to web). 1 Important: two ported no-op tests (remove of an unselected id; prune with nothing hidden) assert value equality only, where web asserts no reassignment → would not catch spurious Observation notifications.
Tasks 3+4: fix round 1/5 QUEUED until Task 5's implementer finishes (one xcodebuild at a time in this worktree): add withObservationTracking assertions (zero changes on no-op remove / prune / clear-when-empty), Set alongside array in selectGroup, drop the print, add the rule-4-then-rule-6 case
Tasks 3+4: minor (deferred): chipLabel trims both ends and counts Characters (web trimEnd, UTF-16); search uses canonical equivalence
Task 5: implementer a0bd699322887a942 (sonnet), BASE ce121f9, running
Task 5: commit d3264ca (DONE_WITH_CONCERNS): all web view-model cases ported, prefs 8 of 10 (2 skipped: UserDefaults cannot throw), 51 tests green. Deviations: refreshError also clears on a 429 / missing focus (controller's rule); failure status exposed as failureStatus: Int?; a cancelled very first load restores .loading with nothing running (UI must sync from .task).
Tasks 3+4: fix round 1/5 dispatched (resume afe3163ee6addd873)
Tasks 3+4: fix commit 15bf505 (no-notification assertions with mutation proof; rule-4-before-6 test; Set in selectGroup); 83 tests green. Note: Observation does not notify on assigning an equal array, so the prune/clear guards are only observable for in-place writes.
Task 5: review (opus) at d3264ca: port faithful; no stale overwrite, no write after dispose, cancellation wired. Important: (1) sync(R) while R is in flight re-sends R after the debounce (and .task re-fires on tab reappear on iOS); (2) a transport-cancelled FIRST load restores .loading with nothing running → endless spinner; (3) the 400 ms debounce is not pinned by a test (399 ms check cannot observe a premature request). Minors: retry() unguarded; 429 copy says "today's limit" (limit is per minute); vault sort vs web for accented names; TestSleeper can strand a cancelled waiter; dispose test does not assert cancellation; prefs test suites not cleaned up; report miscount.
Task 5: fix round 1/5 QUEUED behind Task 6's build (one xcodebuild at a time): Important 1-3 + minors 1,2,3,4,5,6
Task 5: Ruling: keep the deviations (refreshError clears on 429/missing focus; failureStatus; sync retry returning the Task) — reviewer agreed
Web follow-up (owner): the web view model shares Important 1 (sync of an in-flight request re-sends it); it triggers rarely on web; mirror the fix later
Tasks 3+4: scoped re-review af6845567938b0555 running. Task 6: implementer ab15486a94a880e40 (opus) running, BASE = HEAD at dispatch (15bf505).
Tasks 3+4: fix round 1/5 (3 addressed, 0 open; commit 15bf505)
Tasks 3+4: minor (deferred): helper doc comment in BrainSelectionTests says an equal write notifies, which contradicts what the implementer observed — reword to "counts onChange firings"
Tasks 3+4: complete (commits f65e52f..15bf505, review clean)
Task 6: commit dfc9709 (DONE_WITH_CONCERNS): ForceSimulation2D + GraphLayout2D actor + BrainIDHash; 26 tests green. Release timing (M4 Pro): 1,040 pts 0.41 ms/tick, 170 ticks, 69 ms; 2,080 pts 0.78 ms/tick, 132 ms; single author 1,000 notes 0.37 ms/tick; zero allocation on warm ticks. Layout within a few percent of d3 on the same graphs.
Task 6: Ruling: settle must be visible, not instant — the actor paces ticks (2 ticks per 16 ms frame ≈ 1.4 s for a fresh 1,000-point graph) unless quiet; add pause()/resume() for a hidden tab — to be sent with the review findings
Task 5: fix round 1/5 dispatched (resume a0bd699322887a942)
Task 5: fix commit d170f99 (inFlight tracking; cancelled first load → .failed; debounce pinned via recorded durations, fails at 300; retry guarded; per-minute copy; localizedStandardCompare); 141 tests green in 6 suites
Task 5: fix round 1/5 (10 addressed, 0 open; commit d170f99); stuck in-flight flag ruled out (set only in startLoad, cleared in abandon and in perform under the token guard)
Task 5: complete (commits 15bf505..d170f99 for store files, review clean)
Task 6: review a50900d0f00cf24ce (opus) running
Task 6: review (opus) at dfc9709: maths/determinism/cost/teardown verified by running (identical FNV digest across launches and input orders; max tick 0.41 ms at 1,000, 0.84 ms at 2,000; idle 0 CPU). Important: (1) updates stream is single-use — dies when the first consumer task is cancelled (tab hide/show freezes the graph); (2) non-finite pin traps in Grid.build (crash, exit 133). Minors: crowded-cell sampling not momentum-conserving; alpha not decayed for empty graph; tickCount not reset on fresh; far pin degrades grid; NFC/NFD ids merge; release-only cost test; TestClock polls real time.
Task 6: fix round 1/5 dispatched (resume ab15486a94a880e40): Important 1-2 + pacing (2 ticks per 16.67 ms step, no catch-up) + pause/resume + updates() resubscription + minors + manual test clock
Task 6: fix commit 5d40ba1: updates() resubscribable, paced (2 ticks / 16.67 ms), pause/resume, non-finite pin guard + clamp, manual test clock; 45 layout tests, 5 clean repeats. Release: 1,040 pts 0.42 ms/tick; 2,080 pts 0.80; single author 0.38; clump 0.43 warm. Clump vs d3: hub moved 170 pt (d3 92), group 65 pt from d3's, 0 overlaps.
Task 6: Ruling: accept the implementer's deviation on item 5 (crowded cell acts as one softened body at its centroid instead of weighted symmetric sampling, which measured worse: hub flung 1,067 pt) — judged by measurement — cost if wrong: clump case settles further from d3
Task 6: Ruling: accept "next step due one frame after now" after a stall (the reviewer's own test wants one step after a 1 s stall)
Task 6: carry to Task 7: the canvas must hold its updates() stream for as long as it wants frames (dropping it pauses the layout)
Task 3 follow-up: BrainGraphModel.visible still merges NFC/NFD-equivalent ids (Swift String equality) before the layout sees them — minor (deferred)
Task 6: scoped re-review ad3051bdc98b087c3 (opus) running
Task 7: implementer ab9e7d9ead2777c51 (opus), BASE 5d40ba1, running (2D canvas; renders its own screenshots via ImageRenderer; deletes the old BrainGraphCanvas.swift)
Task 6: fix round 1/5 re-review (opus): findings 1-11 ADDRESSED; two runners, busy loop (idle CPU 0.14-0.24 ms/s in six states), resubscribe race all ruled out by running drivers; determinism digest identical across input orders.
Task 6: minor (deferred, VISIBLE — fix before the iOS PR): shimmer near rest caused by collision applied to all points at once (906 of 1,001 points still move >1 pt/tick in the last 20 ticks of a single-author graph; d3: 33) — try collision strength < 1 or sequential pair resolution
Task 6: minor (deferred): Int(NaN) trap if finite extent overflows (unreachable in practice; add an isFinite guard); positions()/LayoutSnapshot.ids keyed by String merge NFC/NFD ids; pin(id, nil) on a settled layout publishes one extra snapshot
Task 6: complete (commits dfc9709, 5d40ba1; review clean)
