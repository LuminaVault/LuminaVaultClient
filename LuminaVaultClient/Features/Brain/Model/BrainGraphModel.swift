// Pure filtering, indexing, search and colour rules for the Brain graph. A port
// of the web app's `graph-model.ts`: the same seven rules in the same order.
// No UI, no networking; everything here is `nonisolated` and `Sendable`.

import Foundation
import LuminaVaultShared

nonisolated enum BrainColourBy: String, CaseIterable, Sendable {
    case vault, space, author, kind
}

nonisolated struct BrainGraphFilters: Equatable, Sendable {
    var links: [BrainLinkKindDTO: Bool]
    /// `nil` means every vault.
    var vaults: Set<UUID>?
    var showOrphans: Bool
    var colourBy: BrainColourBy
}

nonisolated struct BrainGraphIndex: Sendable {
    var byID: [String: BrainGraphNodeDTO] = [:]
    var neighbours: [String: Set<String>] = [:]
    var edgesOf: [String: [BrainGraphEdgeDTO]] = [:]
}

nonisolated struct VisibleBrainGraph: Sendable {
    var nodes: [BrainGraphNodeDTO]
    var edges: [BrainGraphEdgeDTO]
    var index: BrainGraphIndex
}

nonisolated struct BrainLegendKey: Equatable, Sendable {
    var key: String
    var label: String
    var count: Int
}

/// UI strings for kinds. Not wire types: same wording as the web screen.
nonisolated enum BrainGraphCopy {
    static func linkLabel(_ kind: BrainLinkKindDTO) -> String {
        switch kind {
        case .link: "Links"
        case .source: "Sources"
        case .tag: "Tags"
        case .author: "Authors"
        case .entity: "Mentions"
        case .space: "Spaces"
        case .similar: "Similar"
        }
    }

    static func nodeKindName(_ kind: BrainNodeKindDTO) -> String {
        switch kind {
        case .note: "Note"
        case .memory: "Memory"
        case .tag: "Tag"
        case .author: "Author"
        case .entity: "Mention"
        case .space: "Space"
        }
    }
}

nonisolated enum BrainGraphModel {
    static let legendMax = 8

    static func defaultFilters() -> BrainGraphFilters {
        var links: [BrainLinkKindDTO: Bool] = [:]
        for kind in BrainLinkKindDTO.allCases { links[kind] = kind != .similar }
        return BrainGraphFilters(links: links, vaults: nil, showOrphans: true, colourBy: .vault)
    }

    static func isHub(_ node: BrainGraphNodeDTO) -> Bool {
        switch node.kind {
        case .tag, .author, .entity, .space: true
        case .note, .memory: false
        }
    }

    /// Hub nodes and the link kind that attaches to them share a raw value.
    private static func linkKind(of node: BrainGraphNodeDTO) -> BrainLinkKindDTO? {
        BrainLinkKindDTO(rawValue: node.kind.rawValue)
    }

    /// Applies the filters in one pass per stage. Hub edges run from the item to
    /// the hub with the hub's own kind, so a hub's members are the distinct items
    /// on the `from` side of those edges.
    static func visible(_ graph: BrainGraphResponse, filters: BrainGraphFilters) -> VisibleBrainGraph {
        let links = filters.links
        let vaults = filters.vaults

        // Rules 2 and 3: node-level toggles and vault restriction.
        var alive: [String: BrainGraphNodeDTO] = [:]
        var order: [String] = []
        for n in graph.nodes {
            let hub = isHub(n)
            if hub, !(linkKind(of: n).flatMap { links[$0] } ?? false) { continue }
            if let vaults, !hub || n.kind == .space {
                guard let v = n.vaultID, vaults.contains(v) else { continue }
            }
            if alive.updateValue(n, forKey: n.id) == nil { order.append(n.id) }
        }

        // Rules 1 and 5 (first pass).
        var edges: [BrainGraphEdgeDTO] = []
        var members: [String: Set<String>] = [:]
        for e in graph.edges {
            guard links[e.kind] ?? false else { continue }
            guard let from = alive[e.from], let to = alive[e.to] else { continue }
            edges.append(e)
            if isHub(to), !isHub(from), e.kind.rawValue == to.kind.rawValue {
                members[to.id, default: []].insert(from.id)
            }
        }

        // Rule 4: hubs need at least two members.
        for id in order {
            if let n = alive[id], isHub(n), (members[id]?.count ?? 0) < 2 { alive[id] = nil }
        }

        // Rule 5 again, now that hubs are gone.
        let kept = edges.filter { alive[$0.from] != nil && alive[$0.to] != nil }

        // Rule 6: orphans.
        if !filters.showOrphans {
            var linked = Set<String>()
            for e in kept {
                linked.insert(e.from)
                linked.insert(e.to)
            }
            for id in order {
                if let n = alive[id], !isHub(n), !linked.contains(id) { alive[id] = nil }
            }
        }

        // Rule 7: index.
        var index = BrainGraphIndex(byID: alive)
        for id in alive.keys {
            index.neighbours[id] = []
            index.edgesOf[id] = []
        }
        for e in kept {
            index.neighbours[e.from]?.insert(e.to)
            index.neighbours[e.to]?.insert(e.from)
            index.edgesOf[e.from]?.append(e)
            if e.to != e.from { index.edgesOf[e.to]?.append(e) }
        }
        return VisibleBrainGraph(nodes: order.compactMap { alive[$0] }, edges: kept, index: index)
    }

    /// The ids plus their direct neighbours. Ids the index does not know are ignored.
    static func litSet(_ index: BrainGraphIndex, ids: some Sequence<String>) -> Set<String> {
        var lit = Set<String>()
        for id in ids {
            guard let near = index.neighbours[id] else { continue }
            lit.insert(id)
            lit.formUnion(near)
        }
        return lit
    }

    /// Item ids attached to a hub by an edge of the hub's own kind.
    static func groupMembers(_ index: BrainGraphIndex, hubID: String) -> [String] {
        guard let hub = index.byID[hubID] else { return [] }
        var seen = Set<String>()
        var out: [String] = []
        for e in index.edgesOf[hubID] ?? [] where e.to == hubID && e.kind.rawValue == hub.kind.rawValue {
            if seen.insert(e.from).inserted { out.append(e.from) }
        }
        return out
    }

    /// Case-insensitive label search; prefix matches rank before substring matches.
    static func search(_ nodes: [BrainGraphNodeDTO], query: String, limit: Int = 8) -> [BrainGraphNodeDTO] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        var prefix: [BrainGraphNodeDTO] = []
        var inside: [BrainGraphNodeDTO] = []
        for n in nodes {
            let label = n.label.lowercased()
            if label.hasPrefix(q) {
                prefix.append(n)
            } else if label.contains(q) {
                inside.append(n)
            }
            if prefix.count >= limit { break }
        }
        return Array((prefix + inside).prefix(limit))
    }

    static func colourKey(_ node: BrainGraphNodeDTO, by: BrainColourBy, index: BrainGraphIndex) -> String {
        switch by {
        case .vault:
            return node.vaultID?.uuidString ?? (isHub(node) ? "hub" : "none")
        case .kind:
            return node.kind.rawValue
        case .space:
            return node.spaceID?.uuidString ?? "none"
        case .author:
            for e in index.edgesOf[node.id] ?? [] where e.kind == .author && e.from == node.id {
                return e.to
            }
            return "none"
        }
    }

    /// Similar is on and was asked for, and the server found none: worth saying,
    /// or the switch looks broken.
    static func noSimilarFound(
        _ graph: BrainGraphResponse?, loaded: BrainGraphRequest?, similarOn: Bool
    ) -> Bool {
        guard let graph, let loaded, loaded.similar, similarOn else { return false }
        return !graph.edges.contains { $0.kind == .similar }
    }

    /// What each colour means when points are coloured by Space, author or type:
    /// the commonest keys among the notes and memories on screen, then how many
    /// more there are. Vaults have none: their chips carry the dots. `labelOf`
    /// names a hub by id from the whole graph.
    static func colourLegend(
        _ visible: VisibleBrainGraph, by: BrainColourBy, labelOf: (String) -> String?
    ) -> (keys: [BrainLegendKey], more: Int) {
        if by == .vault { return ([], 0) }
        var counts: [String: Int] = [:]
        for n in visible.nodes where !isHub(n) {
            counts[colourKey(n, by: by, index: visible.index), default: 0] += 1
        }
        func name(_ key: String) -> String {
            if by == .kind { return BrainNodeKindDTO(rawValue: key).map(BrainGraphCopy.nodeKindName) ?? key }
            if key == "none" { return by == .space ? "No Space" : "No author" }
            return labelOf(by == .space ? "space:\(key)" : key) ?? key
        }
        let keys = counts
            .map { BrainLegendKey(key: $0.key, label: name($0.key), count: $0.value) }
            .sorted {
                if $0.count != $1.count { return $0.count > $1.count }
                let order = $0.label.localizedCompare($1.label)
                return order == .orderedSame ? $0.key < $1.key : order == .orderedAscending
            }
        return (Array(keys.prefix(legendMax)), max(0, keys.count - legendMax))
    }
}
