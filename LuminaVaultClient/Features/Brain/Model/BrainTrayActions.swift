// What the selection tray offers for a given selection. A port of the web app's
// `tray-actions.ts`. Pure, so the rules (which action applies to which
// selection, and why one does not) are tested without a view. Every action is
// always listed so the tray does not jump around; one that does not apply says why.

import Foundation
import LuminaVaultShared

nonisolated enum BrainTrayActionID: CaseIterable, Sendable {
    case open, focus, group, explain, ask
}

nonisolated enum BrainTrayAvailability: Equatable, Sendable {
    case enabled
    case disabled(reason: String)
}

nonisolated struct BrainTrayAction: Equatable, Sendable {
    var id: BrainTrayActionID
    var label: String
    var availability: BrainTrayAvailability

    var isEnabled: Bool { availability == .enabled }

    /// Why it is disabled; `nil` when it is enabled.
    var reason: String? {
        if case let .disabled(reason) = availability { return reason }
        return nil
    }
}

/// What running an action asks the screen to do. Only `focus` leads to a graph request.
nonisolated enum BrainTrayOutcome: Equatable, Sendable {
    /// Replaces the selection.
    case select([String])
    case focus(String)
    case open(BrainGraphNodeDTO)
    case explain(from: UUID, to: UUID)
    /// Opens the reasoning panel with `query`; `send` asks it at once.
    case ask(query: String, send: Bool)
}

nonisolated struct BrainExplainTarget: Equatable, Sendable {
    var from: UUID
    var to: UUID
}

nonisolated enum BrainTrayActions {
    static let chipMax = 24
    /// Names at most this many points in a prefilled question.
    static let askNames = 5

    private static func make(_ id: BrainTrayActionID, _ label: String, why: String?) -> BrainTrayAction {
        BrainTrayAction(id: id, label: label, availability: why.map { .disabled(reason: $0) } ?? .enabled)
    }

    /// Explain and Ask when the screen has no reasoning client (previews only).
    static let reasoningUnavailable = "Asking is not available here"

    /// `index` is the graph on screen; Select group needs members there to
    /// select. Without `reasoningAvailable`, Explain and Ask say why not.
    static func actions(
        for nodes: [BrainGraphNodeDTO], index: BrainGraphIndex?, reasoningAvailable: Bool = true
    ) -> [BrainTrayAction] {
        let all = webActions(for: nodes, index: index)
        guard !reasoningAvailable else { return all }
        return all.map { action in
            guard action.id == .explain || action.id == .ask else { return action }
            var off = action
            off.availability = .disabled(reason: reasoningUnavailable)
            return off
        }
    }

    /// The web's `trayActions`, rule for rule.
    private static func webActions(for nodes: [BrainGraphNodeDTO], index: BrainGraphIndex?) -> [BrainTrayAction] {
        let one = nodes.count == 1 ? nodes[0] : nil
        let openWhy: String? = if let one {
            BrainGraphModel.isHub(one) ? "A group cannot be opened; use Select group" : nil
        } else {
            "Select one note or memory to open it"
        }
        let groupWhy: String? = if let one, BrainGraphModel.isHub(one) {
            if let index, !BrainGraphModel.groupMembers(index, hubID: one.id).isEmpty {
                nil
            } else {
                "No notes in this group are showing"
            }
        } else {
            "Select one tag, author, mention or Space to select its group"
        }
        return [
            make(.open, "Open", why: openWhy),
            make(.focus, "Focus", why: one == nil ? "Select exactly one to focus on it" : nil),
            make(.group, "Select group", why: groupWhy),
            make(
                .explain, "Explain connection",
                why: nodes.count == 2 ? nil : "Select exactly two to explain a connection"
            ),
            make(.ask, "Ask", why: nodes.isEmpty ? "Select something to ask about it" : nil),
        ]
    }

    /// Runs `id` for `nodes`. Returns `nil`, doing nothing, when it does not apply.
    static func run(
        _ id: BrainTrayActionID, nodes: [BrainGraphNodeDTO], index: BrainGraphIndex, activeVault: UUID?,
        reasoningAvailable: Bool = true
    ) -> BrainTrayOutcome? {
        let available = actions(for: nodes, index: index, reasoningAvailable: reasoningAvailable)
        guard available.first(where: { $0.id == id })?.isEnabled == true else {
            return nil
        }
        switch id {
        case .open:
            return .open(nodes[0])
        case .focus:
            return .focus(nodes[0].id)
        case .group:
            return .select(BrainGraphModel.groupMembers(index, hubID: nodes[0].id))
        case .explain:
            let (a, b) = (nodes[0], nodes[1])
            if let target = explainTarget(a, b, activeVault: activeVault) {
                return .explain(from: target.from, to: target.to)
            }
            return .ask(query: explainQuery(a.label, b.label), send: true)
        case .ask:
            return .ask(query: askQuery(nodes.map(\.label)), send: false)
        }
    }

    /// The knowledge-node ids to explain between, when both points are entity hubs
    /// known in the active vault (the reasoning routes are scoped to it).
    static func explainTarget(
        _ a: BrainGraphNodeDTO, _ b: BrainGraphNodeDTO, activeVault: UUID?
    ) -> BrainExplainTarget? {
        guard let activeVault, let from = ref(in: a, vault: activeVault), let to = ref(in: b, vault: activeVault)
        else { return nil }
        return BrainExplainTarget(from: from, to: to)
    }

    private static func ref(in node: BrainGraphNodeDTO, vault: UUID) -> UUID? {
        guard node.kind == .entity else { return nil }
        return node.refs?.first { $0.vaultID == vault }?.id
    }

    /// What an explanation of two points is about, for its heading
    /// ("Hermes and Cloudflare"); `nil` unless exactly two are given.
    static func explainSubject(_ nodes: [BrainGraphNodeDTO]) -> String? {
        nodes.count == 2 ? "\(nodes[0].label) and \(nodes[1].label)" : nil
    }

    static func askQuery(_ labels: [String]) -> String {
        let named = labels.prefix(askNames).joined(separator: ", ")
        let rest = labels.count - askNames
        return "What connects \(named)\(rest > 0 ? " and \(rest) more" : "")?"
    }

    static func explainQuery(_ a: String, _ b: String) -> String {
        "How are \"\(a)\" and \"\(b)\" connected?"
    }

    /// At most 24 characters, the last an ellipsis when it was cut.
    static func chipLabel(_ label: String) -> String {
        guard label.count > chipMax else { return label }
        let head = String(label.prefix(chipMax - 1))
        return head.trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// Adds the memories a reasoning answer names to the lit set: only the ones on
    /// screen, uppercased to match graph ids, and not their neighbours. With
    /// nothing selected they are the whole lit set, so the rest dims.
    static func withReasoning(
        _ highlight: BrainHighlight, memoryIDs: [String], index: BrainGraphIndex
    ) -> BrainHighlight {
        let named = memoryIDs.map { $0.uppercased() }.filter { index.byID[$0] != nil }
        guard !named.isEmpty else { return highlight }
        var out = highlight
        out.lit = (highlight.lit ?? []).union(named)
        return out
    }
}
