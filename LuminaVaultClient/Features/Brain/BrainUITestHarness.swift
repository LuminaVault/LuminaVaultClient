// DEBUG only: the Brain screen on a stubbed graph client, for UI tests and for
// looking at every state in the simulator without an account or a server.
//
//   -BrainUITestScenario graph|empty|failed|missingFocus|stale|refreshing|
//                        firstLoad|truncated|nothingMatches|sameStamp
//   -BrainUITestScheme light|dark       (optional)
//   -BrainUITestTypeSize large|xxxLarge|accessibility3   (optional)
//   -BrainUITestHideRequests YES        (optional; for screenshots)
//   -BrainUITestKeepPrefs YES           (optional; keep the last run's prefs)
//   -BrainUITestView 2d|3d              (optional; start on this view)
//   -BrainUITestPoints <n>              (optional; graph scenario: n generated
//                                        notes, memories and hubs instead of the eight)
//
// Launch arguments of the form `-key value` land in `UserDefaults.standard`.
// The screen's prefs go to a separate suite, emptied at launch (unless
// `-BrainUITestKeepPrefs YES`) so runs do not leak into each other. The stub counts the requests it answers and shows the count in
// an element named `brain.uitest.requests`, whose accessibility value is the
// last request's query. Reasoning and memory loads answer from fixed stubs.

#if DEBUG
import LuminaVaultShared
import SwiftUI

enum BrainUITestScenario: String {
    case graph, empty, failed, missingFocus, stale, refreshing, firstLoad, truncated, nothingMatches
    /// A request that names vaults gets a different graph with the same
    /// counts and the same `generatedAt`: every item moved into the first
    /// named vault and renamed.
    case sameStamp

    static var launched: BrainUITestScenario? {
        UserDefaults.standard.string(forKey: "BrainUITestScenario").flatMap(Self.init(rawValue:))
    }
}

extension View {
    /// The harness instead of this view when the app was launched with
    /// `-BrainUITestScenario`; this view otherwise.
    @ViewBuilder
    func brainUITestHarness() -> some View {
        if let scenario = BrainUITestScenario.launched {
            BrainUITestHarness(scenario: scenario)
        } else {
            self
        }
    }
}

/// Answers from a fixed graph of eight notes and memories in two vaults.
@MainActor @Observable
final class BrainUITestClient: BrainGraphClientProtocol {
    private(set) var requestCount = 0
    private(set) var lastQuery = ""
    let scenario: BrainUITestScenario

    init(scenario: BrainUITestScenario) {
        self.scenario = scenario
    }

    func fetchGraph(_ request: BrainGraphRequest) async throws -> BrainGraphResponse {
        requestCount += 1
        lastQuery = request.query
        let first = requestCount == 1
        switch scenario {
        case .graph, .truncated, .nothingMatches, .sameStamp:
            break
        case .empty:
            return Self.response(vaults: [Self.personal], nodes: [], edges: [])
        case .failed:
            throw APIError.httpError(statusCode: 500, data: Data())
        case .missingFocus:
            if request.focus != nil { throw APIError.httpError(statusCode: 404, data: Data()) }
        case .stale:
            if !first { throw APIError.rateLimited(retryAfter: nil) }
        case .refreshing:
            if !first { try await Self.hang() }
        case .firstLoad:
            try await Self.hang()
        }
        return graph(for: request)
    }

    private static func hang() async throws {
        try await Task.sleep(for: .seconds(3600))
    }

    // MARK: Fixture

    static var personalID: UUID { personal.id }

    private static let personal = BrainGraphVaultDTO(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A1") ?? UUID(), name: "Personal", personal: true
    )
    private static let work = BrainGraphVaultDTO(
        id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A2") ?? UUID(), name: "Work", personal: false
    )

    private static func response(
        vaults: [BrainGraphVaultDTO], nodes: [BrainGraphNodeDTO], edges: [BrainGraphEdgeDTO], truncated: Bool = false
    ) -> BrainGraphResponse {
        BrainGraphResponse(
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000), truncated: truncated,
            vaults: vaults, nodes: nodes, edges: edges
        )
    }

    /// Personal: five items, three tagged "home", three links. Work: three
    /// items tagged "work", one link. Ten connections in all. The
    /// `nothingMatches` graph is the same items with no connections.
    private func graph(for request: BrainGraphRequest) -> BrainGraphResponse {
        let points = UserDefaults.standard.integer(forKey: "BrainUITestPoints")
        if scenario == .graph, points > 0 { return Self.generated(points) }
        let moveTo = scenario == .sameStamp ? request.vaults?.first : nil
        return Self.graph(
            for: request, linked: scenario != .nothingMatches, truncated: scenario == .truncated, moveTo: moveTo
        )
    }

    private static func graph(
        for request: BrainGraphRequest, linked: Bool, truncated: Bool, moveTo: UUID?
    ) -> BrainGraphResponse {
        let p = personal.id, w = work.id
        func item(_ id: String, _ label: String, _ kind: BrainNodeKindDTO, _ vault: UUID, _ weight: Int) -> BrainGraphNodeDTO {
            BrainGraphNodeDTO(id: id, kind: kind, label: label, vaultID: vault, weight: weight)
        }
        var nodes = [
            item("N1", "Garden plans", .note, p, 3),
            item("N2", "Reading list", .note, p, 2),
            item("N3", "Sleep log", .memory, p, 1),
            item("N4", "Travel notes", .note, p, 2),
            item("N5", "Budget 2027", .note, p, 2),
            item("N6", "Meeting notes", .note, w, 2),
            item("N7", "Design review", .memory, w, 2),
            item("N8", "Hiring plan", .note, w, 1),
        ]
        var edges: [BrainGraphEdgeDTO] = []
        if linked {
            nodes += [
                BrainGraphNodeDTO(id: "tag:home", kind: .tag, label: "home", weight: 3),
                BrainGraphNodeDTO(id: "tag:work", kind: .tag, label: "work", weight: 3),
            ]
            edges = [
                BrainGraphEdgeDTO(from: "N1", to: "tag:home", kind: .tag),
                BrainGraphEdgeDTO(from: "N3", to: "tag:home", kind: .tag),
                BrainGraphEdgeDTO(from: "N4", to: "tag:home", kind: .tag),
                BrainGraphEdgeDTO(from: "N1", to: "N2", kind: .link),
                BrainGraphEdgeDTO(from: "N2", to: "N5", kind: .link),
                BrainGraphEdgeDTO(from: "N4", to: "N5", kind: .link),
                BrainGraphEdgeDTO(from: "N6", to: "tag:work", kind: .tag),
                BrainGraphEdgeDTO(from: "N7", to: "tag:work", kind: .tag),
                BrainGraphEdgeDTO(from: "N8", to: "tag:work", kind: .tag),
                BrainGraphEdgeDTO(from: "N6", to: "N7", kind: .link),
            ]
        }
        var vaults = [personal, work]
        if let moveTo {
            nodes = nodes.map { n in
                guard n.vaultID != nil else { return n }
                return BrainGraphNodeDTO(id: n.id, kind: n.kind, label: "Moved \(n.label.lowercased())", vaultID: moveTo, weight: n.weight)
            }
            vaults = vaults.filter { $0.id == moveTo }
        } else if let named = request.vaults, !named.isEmpty {
            let keep = Set(named)
            vaults = vaults.filter { keep.contains($0.id) }
            nodes = nodes.filter { $0.vaultID.map(keep.contains) ?? true }
            let alive = Set(nodes.map(\.id))
            edges = edges.filter { alive.contains($0.from) && alive.contains($0.to) }
        }
        return response(vaults: vaults, nodes: nodes, edges: edges, truncated: truncated)
    }

    /// About `count` points for looking at large skies: notes and memories in
    /// three vaults (every fourth item a memory, half of those with a server
    /// position), a tag per item, an author per item, a link to an earlier
    /// item for half of them. Deterministic.
    private static func generated(_ count: Int) -> BrainGraphResponse {
        let words = [
            "Garden", "Reading", "Sleep", "Travel", "Budget", "Meeting", "Design", "Hiring", "Recipes", "Running",
            "Music", "Physics", "History", "Coffee", "Writing", "Ideas",
        ]
        let family = BrainGraphVaultDTO(
            id: UUID(uuidString: "00000000-0000-0000-0000-0000000000A3") ?? UUID(), name: "Family", personal: false
        )
        let vaults = [personal, work, family]
        let tags = max(2, count / 25)
        let authors = max(2, count / 100)
        let items = max(1, count - tags - authors)
        var rng: UInt64 = 0x5EED
        func next(_ n: Int) -> Int {
            rng = rng &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((rng >> 33) % UInt64(max(1, n)))
        }
        var nodes: [BrainGraphNodeDTO] = []
        var edges: [BrainGraphEdgeDTO] = []
        var degree: [String: Int] = [:]
        func link(_ from: String, _ to: String, _ kind: BrainLinkKindDTO) {
            edges.append(BrainGraphEdgeDTO(from: from, to: to, kind: kind))
            degree[from, default: 0] += 1
            degree[to, default: 0] += 1
        }
        for i in 0 ..< items {
            let id = "P\(i)"
            link(id, "tag:t\(next(tags))", .tag)
            link(id, "author:a\(next(authors))", .author)
            if i > 0, next(2) == 0 { link(id, "P\(next(i))", .link) }
        }
        for i in 0 ..< items {
            let id = "P\(i)"
            let memory = i % 4 == 3
            let pos = memory && next(2) == 0
                ? GraphPosition3D(x: Double(next(200)) - 100, y: Double(next(200)) - 100, z: Double(next(200)) - 100)
                : nil
            nodes.append(BrainGraphNodeDTO(
                id: id, kind: memory ? .memory : .note,
                label: "\(words[next(words.count)]) \(words[next(words.count)].lowercased()) \(i)",
                vaultID: vaults[i % vaults.count].id, weight: degree[id] ?? 0, pos: pos
            ))
        }
        for t in 0 ..< tags { nodes.append(BrainGraphNodeDTO(id: "tag:t\(t)", kind: .tag, label: "tag \(t)", weight: degree["tag:t\(t)"] ?? 0)) }
        for a in 0 ..< authors {
            nodes.append(BrainGraphNodeDTO(id: "author:a\(a)", kind: .author, label: "Author \(a + 1)", weight: degree["author:a\(a)"] ?? 0))
        }
        return response(vaults: vaults, nodes: nodes, edges: edges)
    }
}

/// Answers every question with the same short answer, evidence, path and
/// one suggestion; explains every pair the same way.
nonisolated struct BrainUITestKnowledgeClient: KnowledgeGraphClientProtocol {
    private static let edge = KnowledgeEdgeDTO(
        id: UUID(), from: UUID(), to: UUID(), predicate: .relatedTo, state: .suggested, confidence: 0.64,
        rationale: "Both were written the same week."
    )
    private static let nodes = [
        KnowledgeNodeDTO(id: UUID(), kind: .entity, label: "Sleep", confidence: 0.9),
        KnowledgeNodeDTO(id: UUID(), kind: .entity, label: "Garden", confidence: 0.8),
    ]

    private static var answer: ReasoningQueryResponse {
        ReasoningQueryResponse(
            answer: "",
            paths: [KnowledgePathDTO(nodes: nodes, edges: [], confidence: 0.72)],
            evidence: [KnowledgeEvidenceDTO(id: UUID(), memoryID: UUID(), quote: "Slept better after a day in the garden.")],
            confidence: 0.72,
            suggestions: [edge]
        )
    }

    func fetchGraph(limit _: Int, minimumConfidence _: Double) async throws -> KnowledgeGraphResponse {
        KnowledgeGraphResponse(nodes: [], edges: [], generatedAt: Date())
    }

    func reason(query _: String, maxDepth _: Int, limit _: Int) async throws -> ReasoningQueryResponse {
        Self.answer
    }

    func reasonStream(query _: String, maxDepth _: Int, limit _: Int) -> AsyncThrowingStream<ReasoningStreamEventDTO, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(ReasoningStreamEventDTO(type: "context", response: Self.answer))
            continuation.yield(ReasoningStreamEventDTO(type: "token", message: "Both sit under home: "))
            continuation.yield(ReasoningStreamEventDTO(type: "token", message: "the sleep log mentions the garden."))
            continuation.finish()
        }
    }

    func explain(from _: UUID, to _: UUID, maxDepth _: Int) async throws -> ConnectionExplanationResponse {
        ConnectionExplanationResponse(
            explanation: "They share a tag and a week.", paths: [KnowledgePathDTO(nodes: Self.nodes, edges: [], confidence: 0.7)],
            confidence: 0.7
        )
    }

    func review(edgeID: UUID, action: KnowledgeReviewAction, note _: String?) async throws -> KnowledgeEdgeDTO {
        KnowledgeEdgeDTO(
            id: edgeID, from: Self.edge.from, to: Self.edge.to, predicate: Self.edge.predicate,
            state: action == .confirm ? .confirmed : .dismissed, confidence: Self.edge.confidence
        )
    }
}

/// Every memory has the same short body.
nonisolated struct BrainUITestMemoryClient: MemoryClientProtocol {
    func get(id: UUID) async throws -> MemoryDTO {
        MemoryDTO(
            id: id, content: "Slept **7 hours**. Woke up once.", tags: ["sleep", "home"],
            createdAt: Date(timeIntervalSince1970: 1_800_000_000), reviewState: "approved"
        )
    }

    func upsert(_: MemoryUpsertRequest) async throws -> MemoryUpsertResponse { throw APIError.unauthorized }
    func patch(id _: UUID, _: MemoryPatchRequest) async throws -> MemoryDTO { throw APIError.unauthorized }
    func list(limit _: Int, offset _: Int) async throws -> MemoryListResponse { throw APIError.unauthorized }
    func search(_: MemorySearchRequest) async throws -> MemorySearchResponse { throw APIError.unauthorized }
    func delete(id _: UUID) async throws { throw APIError.unauthorized }
}

struct BrainUITestHarness: View {
    let scenario: BrainUITestScenario
    @State private var client: BrainUITestClient
    private let prefs: UserDefaults?

    init(scenario: BrainUITestScenario) {
        self.scenario = scenario
        _client = State(initialValue: BrainUITestClient(scenario: scenario))
        let suite = "brain-uitest"
        let prefs = UserDefaults(suiteName: suite)
        if !UserDefaults.standard.bool(forKey: "BrainUITestKeepPrefs") {
            prefs?.removePersistentDomain(forName: suite)
        }
        if scenario == .nothingMatches {
            var stored = BrainPrefs.defaults()
            stored.filters.showOrphans = false
            stored.save(to: prefs)
        }
        if let view = UserDefaults.standard.string(forKey: "BrainUITestView").flatMap(BrainViewChoice.init(rawValue:)) {
            var stored = BrainPrefs.load(from: prefs)
            stored.view = view
            stored.save(to: prefs)
        }
        self.prefs = prefs
    }

    private static var scheme: ColorScheme? {
        switch UserDefaults.standard.string(forKey: "BrainUITestScheme") {
        case "dark": .dark
        case "light": .light
        default: nil
        }
    }

    private static var typeSize: DynamicTypeSize? {
        switch UserDefaults.standard.string(forKey: "BrainUITestTypeSize") {
        case "large": .large
        case "xxxLarge": .xxxLarge
        case "accessibility3": .accessibility3
        default: nil
        }
    }

    var body: some View {
        BrainUITestThemed {
            BrainTabView(
                client: client,
                memoryClient: BrainUITestMemoryClient(),
                knowledgeClient: BrainUITestKnowledgeClient(),
                activeVault: { [personal = BrainUITestClient.personalID] in personal },
                focus: scenario == .missingFocus ? "N404" : nil,
                prefs: prefs
            )
        }
        .overlay(alignment: .bottomLeading) {
            if !UserDefaults.standard.bool(forKey: "BrainUITestHideRequests") {
                Text("requests: \(client.requestCount)")
                    .font(.caption2)
                    .padding(LVSpacing.xs)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("brain.uitest.requests")
                    .accessibilityValue(client.lastQuery)
            }
        }
        .preferredColorScheme(Self.scheme)
        .modifier(BrainUITestTypeSize(size: Self.typeSize))
    }
}

/// The app's palette for whichever scheme is showing.
private struct BrainUITestThemed<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content.environment(\.lvPalette, LVTheme.cyanGold.palette(for: scheme))
    }
}

private struct BrainUITestTypeSize: ViewModifier {
    let size: DynamicTypeSize?

    func body(content: Content) -> some View {
        if let size {
            content.dynamicTypeSize(size)
        } else {
            content
        }
    }
}
#endif
