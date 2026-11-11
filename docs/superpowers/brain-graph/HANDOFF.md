# Second brain graph: handoff

Written 2026-11-11, at the end of the session that built it. Read this first; it says what is done, what is left, and where everything lives.

## What this work is

One Obsidian-style graph of notes and memories across all of a user's vaults, connected by wikilinks, sources, tags, authors, mentions and Spaces. A labelled 2D graph by default, a 3D constellation behind a switch, explicit selection with a tray, search, and filters that work in place.

- Design: `docs/superpowers/specs/2026-11-11-second-brain-graph-design.md`
- Plans: `docs/superpowers/plans/2026-11-11-brain-graph-server.md`, `...-web.md`, `...-ios.md`
- Ledgers (every ruling made and every minor finding deferred): `docs/superpowers/handoff/ledger-web.md`, `ledger-ios.md`
- Reports worth keeping: `docs/superpowers/handoff/web-task-8-report.md` (performance numbers), `web-final-fix-*.md`, `ios-task-5-report.md`, `ios-task-6-report.md`

## Where each piece stands

| Piece | Repo | State |
|---|---|---|
| `GET /v1/brain/graph` | Lumina-Vault-Server-Go | Merged (PR #56, `c53b614`). **Live in production** since 2026-11-11 18:54Z. |
| Production routing + image | LuminaVaultInfra | Merged (PR #595, `2fbb4a3`): Go API image `f53d14f`, `/v1/brain` routed to Go. |
| Web `/brain` screen | LuminaVaultWebApp | Merged (PR #110, `1a40954`). **Not deployed to production** (deploy is a manual workflow). |
| Swift wire types | LuminaVaultShared | Merged (PR #65, `28a262c`). No version tag. |
| iOS Brain tab | LuminaVaultClient | **6 of 12 tasks done, not pushed.** Task 7 interrupted. See below. |
| Polish pass | web + iOS | Not started. |

## What is left, in order

### 1. Check production with a real account (5 minutes, needs a login)

Production answered correctly to an unauthenticated probe (401 on `/v1/brain/graph`, health 200, existing Go routes unaffected). Nobody has yet called it with a token.

- `curl -H "Authorization: Bearer <token>" https://api.luminavault.fyi/v1/brain/graph` should return 200, list every vault the account belongs to under `vaults`, and contain no node from a vault it cannot read.
- The image `f53d14f` went to production **without** the migration's usual staging evidence (gate G2). Watch `api-go-production` for restarts and 5xx for the next day. Reverting PR #595 restores the previous image.
- The comment in `apps/api-go/values-production.yaml` still says "NOT yet G2-verified"; update it once someone has looked.

### 2. Deploy the web app to production (manual)

The `/brain` page is on `main` but not live. Now that `/v1/brain` is routed, dispatch the `Deploy` workflow in LuminaVaultWebApp with `deploy_production=true`. Then open `/brain` and check: the graph loads, both vaults show as chips, a filter toggle makes no network request, the 2D/3D switch works.

### 3. Finish iOS (the bulk of what is left)

Worktree: `/Users/fernandocorreiachill/Work/production/apps/lumina/.worktrees/brain-graph-client`, branch `feat/brain-graph`, on top of `3a93726`. The branch is pushed to `LuminaVault/LuminaVaultClient` (no pull request opened). It also carries a copy of this handoff, the design, the plans and the ledgers under `docs/superpowers/brain-graph/`.

To push from an agent session use the https URL, because the configured SSH remotes do not authenticate there (same for Shared, Web and Infra):

    git push https://github.com/LuminaVault/LuminaVaultClient.git feat/brain-graph

Done and reviewed (Tasks 1 to 6 of `plans/2026-11-11-brain-graph-ios.md`):

| Task | What | Commits |
|---|---|---|
| 1 | Shared DTOs | in LuminaVaultShared `28a262c` |
| 2 | Request builder, API client, mock | `f65e52f` (+ `51a51d8`, a TEMPORARY package pin) |
| 3, 4 | Graph model, selection, tray rules (ports of the web logic) | `46fd6ce`, `ce121f9`, `15bf505` |
| 5 | Graph store: when the app may ask the server | `d3264ca`, `d170f99` |
| 6 | 2D force layout off the main actor | `dfc9709`, `5d40ba1` |

Task 7 (2D canvas) was interrupted a few minutes in. It left **uncommitted, unfinished** files: `LuminaVaultClient/Features/Brain/Render/` and two test files (`BrainGraphCanvasLogicTests.swift`, `BrainGraphThemeTests.swift`). The tests were written first and do not compile yet. Either continue from them or delete them and restart the task; nothing depends on them.

Remaining tasks: 7 (2D canvas), 8 (the screen: toolbar, filters, list, states), 9 (selection tray, detail, reasoning), 10 (RealityKit constellation), 11 ("Show in graph", deep link, active vault), 12 (delete the old screen, measure, verify). The plan has the full brief for each.

Things the next person must know for iOS:

- **Build and test command** (one build at a time in the worktree):
  `xcodebuild test -project LuminaVaultClient.xcodeproj -scheme LuminaVaultClient -configuration Debug -destination "platform=iOS Simulator,id=F4A79358-3F5C-48E0-A5B6-9760EBC3BBCC" -derivedDataPath $PWD/.superpowers/dd -only-testing:LuminaVaultClientTests/<Suite>`
  The worktree has untracked local config files (`Config/*.xcconfig`, `GoogleAuth.xcconfig`) copied from the `.sample` files; never commit them.
- **Package pin.** Commit `51a51d8` pins LuminaVaultShared to the branch `feat/brain-graph`. Before the iOS PR, replace it with a **revision pin to `28a262c128605ad02354ef18ddf9c46c6b7bc638`** (Shared `main`, same content). The owner decided against tagging a version.
- **How the canvas must use the layout actor** (`GraphLayout2D`): hold exactly one `updates()` stream for the life of one `.task` (dropping it pauses the layout); drop snapshots from an older `generation`; pair `ids[i]` with `points[i]` by index; hop to the main actor to draw; drag with `pin(id, at:)` and end with `pin(id, at: nil)`; Reduce Motion maps to `setQuiet(true)`; call `stop()` only when the screen goes away for good.
- **Known visible issue to fix before the iOS PR:** a very crowded cluster (a single-author vault of about 1,000 notes) shimmers for its last frames before coming to rest. Cause: collisions are resolved for all points at once in `ForceSimulation2D`. Try a collision strength below 1 or resolving pairs in sequence. Details in `ledger-ios.md`.
- The project's default actor isolation is MainActor: pure model types must be `nonisolated` and `Sendable`.
- CI records snapshot baselines on iOS 26.4; this Mac has 26.2. Do not commit baselines recorded locally.
- Open `Open` for a memory in another vault needs a per-request vault header in `BaseHTTPClient`, as the web client got (one line). If that is not acceptable, show "Switch to <vault> to open this memory".

### 4. Polish pass (owner request)

After iOS is done: run the `impeccable` skill in polish mode on the web brain files, and `impeccable-swift` on `LuminaVaultClient/Features/Brain/`. Re-run each repo's tests afterwards.

## Known limits and follow-ups (none blocks the above)

Web (also listed in PR #110):
- Switching 3D to 2D rebuilds the 2D view: the layout settles again and pan and zoom are lost.
- The filter panel is a modal sheet; the reasoning panel docks beside the graph from about 1200 px of viewport width.
- With "reduce motion" on, a fresh 2D graph shows only the background while it settles (about 1 to 1.5 s at 1,000 notes).
- On a focused graph, clearing the selection and then refetching selects the focus point again.
- A graph grown in several steps that each stay under doubling is not laid out afresh in 3D.
- `sync` of a request that is already loading sends it again after the debounce. Fixed on iOS (`d170f99`); mirror it in `brain-graph-view-model.svelte.ts`.
- On machines without GPU acceleration, 2D zoom on a retina display is slow; rendering at lower resolution during the gesture fixes it (measured 183 ms to 16.7 ms per frame).

Server:
- `focus` at depth 2 through a large hub returns most of the graph. Clients already omit `author` in focused requests.
- `limit` is one window across all vaults, so a busy vault can crowd out a quiet one.
- The `text/%` content-type match for notes is case-sensitive.
- Hub labels are not length-capped; the OpenAPI bounds are stricter than the handler.

## Decisions made during the session that someone should know about

- Every uuid inside a node id is UPPERCASE on the wire; `focus` accepts either case.
- Only text files count as notes. Rejected memories are excluded.
- Similarity is opt-in, capped to the 400 most recent memories, with a 2 second timeout.
- The graph endpoint is limited to 30 requests a minute at base, scaled by tier (about 10 on the free tier). Both clients therefore fetch only on first load, a change of vault set, focus or depth, and the first Similar toggle.
- Web: no new package was added; the 2D graph is custom Canvas on d3 modules that were already installed. Clicking a hub selects the hub; "Select group" is an explicit button.
- Web: one line changed in `src/lib/api/client.ts` so a request can name its own vault.
- Web: `.impeccable/config.json` is committed with one ignore (the refresh progress bar is not a marquee).
- LuminaVaultShared: no version tag; iOS pins by revision.
- Sonatype dependency check was unavailable all session (expired token). No new dependency was added anywhere, so it was never needed.

## Cleaning up

The worktrees for the Server, Web, Shared and Infra work were removed on 2026-11-11 after their pull requests merged (each was clean and sat on its PR's head commit). The only worktree left is the iOS one, `lumina/.worktrees/brain-graph-client`, which is still in use and holds the interrupted Task 7 files.

Still to tidy, when convenient:

- Remote branches `feat/brain-graph` (Web, Shared, Server) and `api-go/brain-route` (Infra) can be deleted. Local branches of the same names remain in those repos; they were squash-merged, so `git branch -d` will refuse and `-D` is needed.
- The local `main` checkouts of Web, Shared, Server and Infra are behind their remotes; pull before working on them.

The ledgers, reports and a dozen screenshots from the removed worktrees were copied to `docs/superpowers/handoff/` first; those copies are the ones to keep.
