// DEBUG only: the Brain screen on a stubbed graph client, for UI tests and for
// looking at every state in the simulator without an account or a server.
//
//   -BrainUITestScenario graph|empty|failed|missingFocus|stale|refreshing|
//                        firstLoad|truncated|nothingMatches|sameStamp
//   -BrainUITestScheme light|dark       (optional)
//   -BrainUITestTypeSize large|xxxLarge|accessibility3   (optional)
//   -BrainUITestHideRequests YES        (optional; for screenshots)
//
// Launch arguments of the form `-key value` land in `UserDefaults.standard`.
// The screen's prefs go to a separate, emptied suite so runs do not leak into
// each other. The stub counts the requests it answers and shows the count in
// an element named `brain.uitest.requests`.

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
    let scenario: BrainUITestScenario

    init(scenario: BrainUITestScenario) {
        self.scenario = scenario
    }

    func fetchGraph(_ request: BrainGraphRequest) async throws -> BrainGraphResponse {
        requestCount += 1
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
        prefs?.removePersistentDomain(forName: suite)
        if scenario == .nothingMatches {
            var stored = BrainPrefs.defaults()
            stored.filters.showOrphans = false
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
            BrainTabView(client: client, focus: scenario == .missingFocus ? "N404" : nil, prefs: prefs)
        }
        .overlay(alignment: .bottomLeading) {
            if !UserDefaults.standard.bool(forKey: "BrainUITestHideRequests") {
                Text("requests: \(client.requestCount)")
                    .font(.caption2)
                    .padding(LVSpacing.xs)
                    .allowsHitTesting(false)
                    .accessibilityIdentifier("brain.uitest.requests")
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
