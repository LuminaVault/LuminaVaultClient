import Foundation
import LuminaVaultShared

/// Adapts the durable reasoning graph to the existing GPU-backed graph
/// renderers while preserving knowledge-node IDs for selection/explanation.
enum KnowledgeGraphProjection {
    static func make(
        graph: KnowledgeGraphResponse,
        focusedPath: KnowledgePathDTO? = nil,
        selectedNodeIDs: Set<UUID> = []
    ) -> MemoryGraphResponse {
        let sourceNodes = focusedPath?.nodes ?? graph.nodes
        let sourceEdges = focusedPath?.edges ?? graph.edges.filter {
            $0.state != .dismissed && $0.state != .stale
        }
        let liveIDs = Set(sourceNodes.map(\.id))
        let nodes = sourceNodes.map { node in
            MemoryGraphNodeDTO(
                id: node.id,
                title: node.label,
                tags: [node.kind.rawValue],
                createdAt: node.occurredAt ?? graph.generatedAt,
                score: max(1, node.confidence * 100),
                activity: selectedNodeIDs.contains(node.id) ? 1 : activity(for: node.kind)
            )
        }
        let edges = sourceEdges.compactMap { edge -> MemoryGraphEdgeDTO? in
            guard liveIDs.contains(edge.from), liveIDs.contains(edge.to) else { return nil }
            return MemoryGraphEdgeDTO(
                from: edge.from,
                to: edge.to,
                kind: edgeKind(for: edge.predicate),
                tag: edge.predicate.rawValue,
                similarity: edge.confidence,
                weight: edge.confidence
            )
        }
        return MemoryGraphResponse(nodes: nodes, edges: edges, generatedAt: graph.generatedAt)
    }

    private static func activity(for kind: KnowledgeNodeKindDTO) -> Double {
        switch kind {
        case .claim: 0.9
        case .event: 0.6
        case .entity: 0.25
        }
    }

    private static func edgeKind(for predicate: KnowledgeEdgePredicateDTO) -> MemoryEdgeKindDTO {
        switch predicate {
        case .causes, .precedes: .temporal
        case .supports: .semantic
        case .contradicts: .tag
        case .relatedTo: .space
        case .mentions, .about, .derivedFrom: .wikilink
        }
    }
}
