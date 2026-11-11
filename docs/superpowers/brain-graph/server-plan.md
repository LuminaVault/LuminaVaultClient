# Brain Graph Server Endpoint Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `GET /v1/brain/graph` to the Go server: one graph of notes and memories across every vault the caller can read, connected by wikilinks, source lineage, tags, authors, mentioned entities, Spaces and (opt-in) similarity.

**Architecture:** A new read-only module `internal/modules/brain`, computed per request from existing tables, with no migrations. Shared attributes (tag, author, entity, Space) become hub nodes with one edge per member, so edge count grows linearly. The handler enumerates the caller's vaults, loads items and relations with `tenant_id = ANY(...)`, assembles the graph in Go, and answers with an `ETag`.

**Tech Stack:** Go, Echo v5, pgx v5, sqlc, oapi-codegen (models only), kin-openapi (test validation), testcontainers Postgres via `dbtest.Postgres`.

**Spec:** `docs/superpowers/specs/2026-11-11-second-brain-graph-design.md` (section 1). This plan covers the server piece only; web and iOS get their own plans.

`SRV` below means `/Users/fernandocorreiachill/Work/production/apps/lumina/LuminaVaultServerV2`. `INF` means `~/Work/production/platform/infra`.

## Global Constraints

- Server code only in `SRV`. No Swift server changes.
- **Do not edit** `SRV/internal/vaultaccess`, `SRV/internal/modules/vault`, `SRV/modules.yaml`, `SRV/docs/migration/routes.json`, `00001_baseline.sql` or `schema-swift.sql`. Another agent is working on vault code.
- No new tables, columns, indexes or migrations.
- `GET /v1/memory/graph`, `/v1/knowledge/*` and the dashboard preview are not changed.
- The wire says `author`, never `actor`.
- Limits: `limit` default 400, max 2000; `depth` 1 to 3, default 1; hubs need at least 2 members; `similar` is top 3 per memory at cosine similarity 0.78 or higher and is off unless requested.
- The response carries no note bodies, no memory content beyond the label, no evidence quotes.
- Tests never call a real LLM or use a real API key.
- Work on branch `feat/brain-graph` in a worktree under `SRV/.worktrees/` (superpowers:using-git-worktrees).
- Before each commit: `make gen` produces no diff, and `go test ./internal/modules/brain/... ./internal/manifest/...` passes.

## Review Focus

Each line names the task that owns its test.

1. A user with no notes and no memories: the response is `200` with `nodes: []`, `edges: []` (arrays, not `null`) and their personal vault in `vaults`. (Task 2)
2. Tags that differ only by case or surrounding spaces (`" Go "`, `go`) land on one hub, `tag:go`. (Task 4)
3. A wikilink whose target note is outside the `limit` window, or an edge to any node not in the response: the edge is dropped, never returned dangling. (Task 3)
4. A memory whose content is empty, multi-line or very long: the label is the first non-empty line, at most 80 characters, and `"Untitled"` when there is none. (Task 3)
5. An item whose `created_by_user_id` matches no row in `users`: it gets no author edge and the request still succeeds. (Task 4)

## File Structure

| File | Responsibility |
|---|---|
| `SRV/api/openapi.yaml` | Path `/v1/brain/graph` and the `BrainGraph*` schemas |
| `SRV/internal/modules/brain/oapi-codegen.yaml`, `models.gen.go` | Generated wire models |
| `SRV/internal/modules/brain/queries.sql`, `db/` | All SQL, via sqlc |
| `SRV/internal/modules/brain/module.go` | Route, middleware, query parsing, ETag |
| `SRV/internal/modules/brain/vaults.go` | Which vaults the caller can read |
| `SRV/internal/modules/brain/build.go` | Pure assembly: rows in, graph out (hubs, dedupe, sort, focus) |
| `SRV/internal/modules/brain/build_test.go` | Unit tests for `build.go`, no database |
| `SRV/internal/modules/brain/module_test.go` | HTTP tests on Postgres, validated against the spec |
| `SRV/internal/modules/brain/testdata/seed.sql` | Two-vault fixture, loaded after `parity/seed/base.sql` |
| `SRV/internal/ratelimit/ratelimit.go` | New policy `BrainGraphByUser` |
| `SRV/sqlc.yaml`, `SRV/cmd/App/main.go` | Registration |

## Wire contract (used by every task)

Request query parameters:

| Name | Meaning |
|---|---|
| `vaults` | CSV of vault ids. Default: every vault the caller can read. `X-Vault-ID` is ignored on this route. |
| `links` | CSV of edge kinds from `link, source, tag, author, entity, space, similar`. Unknown values are ignored. Default (absent or nothing valid): all except `similar`. |
| `limit` | Item nodes (notes plus memories) across all vaults, most recently updated first. |
| `focus` | A node id. Returns only nodes within `depth` hops of it. |
| `depth` | Used with `focus`. |

Response `BrainGraphResponse`:

```json
{
  "generatedAt": "2026-11-11T10:00:00Z",
  "truncated": false,
  "vaults": [{"id": "<uuid>", "name": "alice's Vault", "personal": true}],
  "nodes": [{"id": "...", "kind": "memory", "label": "...", "vaultID": "<uuid>",
             "spaceID": "<uuid>", "weight": 3, "createdAt": "...",
             "pos": {"x": 1.0, "y": 2.0, "z": 3.0},
             "refs": [{"vaultID": "<uuid>", "id": "<uuid>"}]}],
  "edges": [{"from": "...", "to": "...", "kind": "tag", "weight": 0.81}]
}
```

- Required on a node: `id`, `kind`, `label`, `weight`. Required on an edge: `from`, `to`, `kind`. Everything else is omitted when absent.
- Node `kind`: `note | memory | tag | author | entity | space`.
- Node ids: notes and memories use their uuid. Every uuid inside a node or hub id is UPPERCASE, as `wire.UUID` and every other endpoint emit it (changed from lowercase after the whole-branch review); `focus` accepts either case. Hubs use `tag:<normalised tag>`, `author:user:<uuid>`, `author:model:<provider>/<model>`, `entity:<canonical_key>`, `space:<uuid>`.
- `vaultID` is set on notes, memories and Space hubs. Tag, author and entity hubs span vaults and have none.
- `weight` is the node's edge count in the returned graph.
- `pos` is set only on memories with `graph_x/y/z`.
- `refs` is set only on entity hubs: the `knowledge_nodes.id` per vault, which the client passes to `/v1/knowledge/connections/explain`.
- Edge `weight` is set only on `similar` (the cosine similarity).
- Hub edges run from the item to the hub. `link` runs source note to target note. `source` runs memory to note.
- Nodes are sorted by `(kind, id)` and edges by `(kind, from, to)` so the body is deterministic.

Errors (the standard `wire.Error` body): `400 "invalid vaults"`, `400 "invalid focus"` (empty or longer than 300 characters), `403` from `vaultaccess` when a requested vault is not readable, `404 "node not found"` when `focus` is not in the graph, `401` without a token, `429` when rate limited.

---

### Task 1: Contract, empty module, wiring

**Files:**
- Modify: `SRV/api/openapi.yaml` (add the path after `/v1/knowledge/graph`, near line 5913; add schemas beside `KnowledgeGraphResponse`)
- Create: `SRV/internal/modules/brain/oapi-codegen.yaml` (copy `internal/modules/knowledge/oapi-codegen.yaml`; `package: brain`; `include-operation-ids: [brainGraph]`)
- Create: `SRV/internal/modules/brain/module.go`, `module_test.go`
- Modify: `SRV/internal/ratelimit/ratelimit.go`, `SRV/cmd/App/main.go:229`

**Interfaces:**
- Produces: `brain.New(pool *pgxpool.Pool, identify echo.MiddlewareFunc, limits *ratelimit.Store) *Module`, `(*Module).Register(r httpserver.Router, _ echo.MiddlewareFunc)`, generated types `BrainGraphResponse`, `BrainGraphNode`, `BrainGraphEdge`, `BrainGraphVault`, `BrainGraphPosition`, `BrainGraphRef`, and `ratelimit.BrainGraphByUser`.
- Produces for tests: `setup(t) env` and `env.do(user, method, path, body, headers...)` in `module_test.go`, copied from `internal/modules/knowledge/module_test.go:60-97`, loading `parity/seed/base.sql` then `testdata/seed.sql`; and `validate(t, rec)`, the kin-openapi response check used at `knowledge/module_test.go:483`.

- [ ] **Step 1: Write the spec.** Operation: `operationId: brainGraph`, `tags: [Brain]`, `x-lv-module: brain`, the five query parameters above with their bounds, responses `200` (`BrainGraphResponse`) and `304`. Schemas exactly as in the wire contract.
- [ ] **Step 2: Add the rate-limit policy** `BrainGraphByUser` next to `CaptureByUser` in `ratelimit.go`, same shape, 30 requests per 60 seconds.
- [ ] **Step 3: Write failing tests** in `module_test.go` with an empty `testdata/seed.sql`:
  - `TestGraphRequiresAuth`: no token gives `401`.
  - `TestGraphEmptyMatchesSpec`: alice gets `200`; the body passes `validate`; `nodes` and `edges` decode to empty non-nil arrays.
  - `TestGraphRateLimited`: the 31st request inside one window (use `Store.SetClock`) gives `429`.
- [ ] **Step 4:** `go test ./internal/modules/brain/...` fails (package does not compile).
- [ ] **Step 5: Implement.** Add the `//go:generate` line as in `knowledge/module.go:8`, run `make gen`. `Register` mounts `GET /v1/brain/graph` behind `identify` and `ratelimit.TieredMiddleware(limits, ratelimit.BrainGraphByUser, ratelimit.UserOrIPKey, ratelimit.PGTier(pool))`. There is no entitlement gate, matching `/v1/memory/graph`. The handler returns an empty `BrainGraphResponse` with `generatedAt` from an injectable `now`.
- [ ] **Step 6: Wire it** in `cmd/App/main.go` by appending `brain.New(pool, identify, limits)` to the module list that holds `knowledge.New`.
- [ ] **Step 7:** `go test ./internal/modules/brain/... ./internal/manifest/... ./cmd/...` passes. The route is absent from `routes.json`; if `internal/manifest` fails because of that, stop and report rather than editing `modules.yaml` or `routes.json`.
- [ ] **Step 8:** Commit `feat(brain): graph endpoint contract and empty module`.

### Task 2: Vault scope

**Files:**
- Create: `SRV/internal/modules/brain/vaults.go`, `queries.sql`, `testdata/seed.sql` (fill)
- Modify: `SRV/sqlc.yaml` (new entry copied from the knowledge entry at lines 465-483, adding the `uuid[]` to `[]uuid.UUID` override), `module.go`, `module_test.go`

**Interfaces:**
- Consumes: `vaultaccess.Service.ResolveVault(ctx, userID, vaultID uuid.UUID, perm vaultaccess.Permission) (vaultaccess.Access, error)`.
- Produces: `type scope struct { ID uuid.UUID; Name string; Personal bool }` and `(m *Module) scopes(ctx context.Context, userID uuid.UUID, requested []uuid.UUID) ([]scope, error)`; sqlc query `CandidateVaults(ctx, userID) []CandidateVaultsRow{ID, Name}`.

Seed (`testdata/seed.sql`), using alice `a11ce000-0000-4000-8000-000000000001` and bob `b0b00000-0000-4000-8000-000000000002` from `base.sql`: one team with one team vault "Team Vault" where alice is a `viewer` member and bob is not; one archived team vault where alice is a member. Read the `teams` table definition in `schema-swift.sql` for its required columns.

- [ ] **Step 1: Write failing tests:**
  - `TestVaultsDefaultToAllReadable`: alice's response `vaults` is exactly her personal vault (`personal: true`) and "Team Vault", sorted by name; the archived vault and bob's vault are absent.
  - `TestVaultsParamNarrows`: `?vaults=<team vault>` returns only that vault.
  - `TestVaultsParamRejectsUnreadable`: `?vaults=<bob's vault>` gives `403`.
  - `TestVaultsParamMalformed`: `?vaults=nope` gives `400` with message `invalid vaults`.
  - `TestNewUserHasEmptyGraph` (Review Focus 1): bob gets `200`, his personal vault in `vaults`, empty arrays.
- [ ] **Step 2:** Run them; they fail.
- [ ] **Step 3: Implement.** `CandidateVaults` selects non-archived vaults where `personal_owner_user_id = $1` or the id is in the caller's `vault_memberships`. With no `requested`, `scopes` passes every candidate through `ResolveVault(..., vaultaccess.Read)` and silently drops those that return a `*wire.Error`; any other error is returned. With `requested`, each id goes through `ResolveVault` and its error is returned as is. The handler puts the result in `vaults`.
- [ ] **Step 4:** Tests pass; `make gen` leaves no diff.
- [ ] **Step 5:** Commit `feat(brain): resolve the caller's readable vaults`.

### Task 3: Items, direct edges, limit

**Files:**
- Create: `SRV/internal/modules/brain/build.go`, `build_test.go`
- Modify: `queries.sql`, `module.go`, `module_test.go`, `testdata/seed.sql`

**Interfaces:**
- Produces (in `build.go`):
  - `type item struct { ID, VaultID uuid.UUID; SpaceID *uuid.UUID; Kind string; Label string; CreatedAt *time.Time; Pos *[3]float64 }`
  - `type relation struct { From, To string; Kind string; Weight *float64 }`
  - `type hub struct { ID, Kind, Label string; VaultID *uuid.UUID; Refs []BrainGraphRef }`
  - `func assemble(items []item, hubs []hub, rels []relation) (nodes []BrainGraphNode, edges []BrainGraphEdge)`: drops relations with a missing endpoint, drops self-loops, dedupes edges on `(kind, from, to)` (and on the unordered pair for `link` and `similar`), drops hubs with fewer than 2 remaining members, sets `weight` to edge count, sorts as the contract says.
  - `func memoryLabel(content string) string` and `func noteLabel(path string) string`.
  - `func parseLinks(raw string) map[string]bool`.
- Produces (sqlc): `Items(ctx, vaultIDs []uuid.UUID, rowLimit int32)`, `NoteLinks(ctx, vaultIDs, noteIDs)`, `MemorySources(ctx, memoryIDs)`.

- [ ] **Step 1: Write failing unit tests** in `build_test.go`:
  - `TestMemoryLabel` (Review Focus 4): `""` and `"\n \n"` give `"Untitled"`; `"\n# Title\nbody"` gives `"# Title"`; a 200-character line gives exactly 80 characters; a multi-byte string is cut on a rune boundary.
  - `TestNoteLabel`: `"folder/My Note.md"` gives `"My Note"`; `"README"` gives `"README"`; `"a/日本語.md"` gives `"日本語"`.
  - `TestAssembleDropsDanglingAndSelfEdges` (Review Focus 3).
  - `TestAssembleDedupesUndirectedPairs`: `link` A to B and B to A give one edge.
  - `TestAssembleDropsSmallHubs`: a hub with one member is absent along with its edge.
  - `TestAssembleSortsAndWeights`.
  - `TestParseLinks`: `""` and `"bogus"` give the six defaults; `"tag,similar,bogus"` gives exactly `tag` and `similar`.
- [ ] **Step 2: Write failing HTTP tests** (seed: in alice's vault two notes N1, N2 with a resolved `vault_links` row N1 to N2 and an unresolved row, and a memory M1 with `source_vault_file_id = N1`; in the team vault a note N3 and a memory M2):
  - `TestItemsSpanVaults`: nodes include N1, N2, N3, M1, M2 with the right `kind` and `vaultID`; nothing from bob's vault.
  - `TestLinkAndSourceEdges`: exactly one `link` edge N1 to N2, one `source` edge M1 to N1.
  - `TestLimitTruncates`: `?limit=1` gives one item node and `truncated: true`; `?limit=2000` gives `truncated: false`; `?limit=0` and `?limit=99999` are clamped to 1 and 2000.
  - `TestLinksParamFilters`: `?links=source` returns no `link` edge.
- [ ] **Step 3:** Run; they fail.
- [ ] **Step 4: Implement.** `Items` is one `UNION ALL` over `vault_files` and `memories` for `tenant_id = ANY($1)`, ordered by `coalesce(updated_at, created_at) DESC NULLS LAST, id`, `LIMIT $2`; the handler asks for `limit + 1` rows and sets `truncated` when the extra row comes back. The memory half selects `left(content, 400)`, not the full content. `NoteLinks` reads `vault_links` where `resolved` and both ends are in the selected notes. Each relation query runs only when its kind is requested.
- [ ] **Step 5:** All tests pass.
- [ ] **Step 6:** Commit `feat(brain): notes, memories, wikilinks and source edges`.

### Task 4: Hubs for tags, Spaces, authors and entities

**Files:**
- Modify: `queries.sql`, `build.go`, `build_test.go`, `module.go`, `module_test.go`, `testdata/seed.sql`

**Interfaces:**
- Consumes: `item`, `hub`, `relation`, `assemble` from Task 3.
- Produces: `func normaliseTag(s string) string` (trim, lowercase; empty result means skip); sqlc `Spaces(ctx, spaceIDs)`, `Authors(ctx, userIDs) []{ID, Username}`, `ModelAuthors(ctx, memoryIDs) []{MemoryID, Provider, Model}`, `Entities(ctx, vaultIDs, memoryIDs) []{ID, TenantID, CanonicalKey, Label, MemoryID}`.

Rules:
- `tag`: from `memories.tags`. Hub label is the normalised tag.
- `space`: from `space_id` on notes and memories. Hub label is `spaces.name`, with `vaultID`.
- `author` (person): `created_by_user_id` on notes and memories, joined to `users`. Hub label is `users.username`. No matching user means no edge.
- `author` (model): `memory_contributions` rows with `actor_kind = 'model'` and a non-null `model`, distinct per memory. Hub id `author:model:<provider>/<model>` (provider empty string when null), label is the model.
- `entity`: `knowledge_nodes` with `kind = 'entity'` and `confidence >= 0.5`, joined through `knowledge_evidence.node_id` to selected memories. Hub is keyed by `canonical_key` across vaults, label from the highest-confidence row, `refs` holding one `{vaultID, id}` per vault.

- [ ] **Step 1: Write failing tests.** Unit: `TestNormaliseTag` (`" Go "` gives `"go"`, `"  "` gives `""`). HTTP, extending the seed:
  - `TestSharedTagHubAcrossVaults`: M1 tagged `{" Go ", "solo"}` and M2 tagged `{"go"}` give node `tag:go` with `weight: 2`, no `vaultID`, two `tag` edges; `tag:solo` is absent (Review Focus 2).
  - `TestSpaceHub`: two items in one Space give `space:<id>` with the Space name and `vaultID`.
  - `TestUserAuthorHub`: N1 and M1 created by alice give `author:user:<alice>` with label `alice`.
  - `TestModelAuthorHub`: two memories with a model contribution of provider `anthropic`, model `claude-haiku-5-5` give `author:model:anthropic/claude-haiku-5-5` labelled `claude-haiku-5-5`.
  - `TestUnknownAuthorIsSkipped` (Review Focus 5): a memory whose `created_by_user_id` matches no user returns `200` and has no `author` edge.
  - `TestEntityHubCarriesRefs`: an entity with `canonical_key` `acme` evidenced by M1 (alice's vault) and M2 (team vault) gives `entity:acme` with two `refs`, one per vault; an entity with confidence 0.4 is absent.
  - `TestLinksParamDropsHubKinds`: `?links=tag` returns no `author`, `entity` or `space` nodes or edges.
- [ ] **Step 2:** Run; they fail.
- [ ] **Step 3: Implement** the four queries and the hub construction, each skipped when its kind is not requested.
- [ ] **Step 4:** Tests pass; every response in the file still passes `validate`.
- [ ] **Step 5:** Commit `feat(brain): tag, space, author and entity hubs`.

### Task 5: Opt-in similarity

**Files:**
- Modify: `queries.sql`, `module.go`, `module_test.go`, `testdata/seed.sql`

**Interfaces:**
- Produces: sqlc `SimilarMemories(ctx, memoryIDs []uuid.UUID, minSimilarity float64, perNode int32) []{FromID, ToID, Similarity}`.

- [ ] **Step 1: Write failing tests** (seed: M1 and M2 get the same 1536-dimension embedding via `array_fill(0.1::real, ARRAY[1536])::vector`; a third memory gets an orthogonal one):
  - `TestSimilarIsOffByDefault`: no `similar` edge without the parameter.
  - `TestSimilarOptIn`: `?links=similar` gives exactly one `similar` edge between M1 and M2 with `weight >= 0.78`, and none to the third memory.
- [ ] **Step 2:** Run; they fail.
- [ ] **Step 3: Implement** as a `LATERAL` top-k per selected memory (`ORDER BY embedding <=> m.embedding LIMIT $3`, restricted to the selected ids, `embedding IS NOT NULL`), filtered to `1 - distance >= $2`, called with `0.78` and `3`. `assemble` already dedupes the unordered pair. Do not reuse the all-pairs self-join in `internal/modules/memory/graph.go:518-537`.
- [ ] **Step 4:** Tests pass.
- [ ] **Step 5:** Commit `feat(brain): opt-in similarity edges`.

### Task 6: Focus, ETag, compression

**Files:**
- Modify: `build.go`, `build_test.go`, `module.go`, `module_test.go`

**Interfaces:**
- Produces: `func neighbourhood(nodes []BrainGraphNode, edges []BrainGraphEdge, focus string, depth int) ([]BrainGraphNode, []BrainGraphEdge, bool)` (the bool is false when `focus` is not a node; edges are treated as undirected; `weight` is recomputed for the kept subgraph), and `func etag(resp BrainGraphResponse) string`.

- [ ] **Step 1: Write failing tests.**
  - Unit `TestNeighbourhood`: on a chain A-B-C-D, depth 1 from A keeps A and B; depth 2 keeps A, B, C; an unknown focus returns false.
  - Unit `TestETagIgnoresGeneratedAt`: two responses differing only in `generatedAt` have the same tag; adding a node changes it.
  - HTTP `TestFocusDepth`: `?focus=<M1>&depth=1` returns M1 and its direct neighbours only; `?focus=<unknown uuid>` gives `404` `node not found`; `?focus=` gives `400` `invalid focus`; `?depth=9` is clamped to 3.
  - HTTP `TestFocusIgnoresDefaultLimit`: with `focus` set and no `limit`, items are loaded at the maximum (2000), so a neighbour older than the newest 400 is still returned. Seed is too small to prove this through HTTP, so assert it on the handler's parsed parameters.
  - HTTP `TestETagRoundTrip`: the first response has an `ETag` header in quotes and `Cache-Control: private, no-cache`; repeating with `If-None-Match` gives `304` and an empty body; after inserting a memory the same request gives `200` and a different tag.
- [ ] **Step 2:** Run; they fail.
- [ ] **Step 3: Implement.** `etag` is the hex SHA-256 of the JSON of the response with `generatedAt` zeroed, wrapped in double quotes. The handler compares it with `If-None-Match` before writing the body.
- [ ] **Step 4: Check compression.** Search `SRV/internal/httpserver` for a gzip or compress middleware. If responses are already compressed, add `TestGraphIsCompressed` asserting `Content-Encoding: gzip` when the request sends `Accept-Encoding: gzip`. If they are not, add Echo's gzip middleware to this route only, with the same test.
- [ ] **Step 5:** `make check` passes for the whole repo.
- [ ] **Step 6:** Commit `feat(brain): focus neighbourhood, ETag and compression`.
- [ ] **Step 7: Measure.** Run the server locally against the test fixture or a local database, `curl` both `/v1/brain/graph` and `/v1/memory/graph` with `Accept-Encoding: gzip`, and record both compressed sizes and response times in the pull request description.

### Task 7: Route production traffic (needs the owner's go-ahead)

Merging to `INF` `main` deploys, so this task runs only after the owner approves the server pull request and says to route traffic.

**Files:**
- Modify: `INF/apps/api/values-staging.yaml`, then `INF/apps/api/values-production.yaml`

- [ ] **Step 1:** Confirm the image SHA pinned for the Go API in `INF` contains the Task 6 commit. If not, follow the app's promotion path first.
- [ ] **Step 2:** Under `ingress.extraPaths`, add `- path: /v1/brain  # go-native (second brain graph)` using the same `service:` as the existing `/v1/knowledge/graph` entry in that file. Staging first.
- [ ] **Step 3:** After the staging merge syncs, `curl -H "Authorization: Bearer <token>" https://<staging host>/v1/brain/graph` returns `200` with both of the test account's vaults.
- [ ] **Step 4:** Repeat for production and confirm with the owner's account that every vault they belong to appears in `vaults`.
