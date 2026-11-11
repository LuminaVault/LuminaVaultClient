// Selection state machine for the Brain graph. A port of the web app's
// `selection.svelte.ts` minus hover, which has no touch equivalent. Selecting
// never calls the API and never moves the camera.

import Foundation
import Observation

/// What the renderer needs to dim and emphasise points. `lit == nil` dims nothing.
nonisolated struct BrainHighlight: Equatable, Sendable {
    var selected: Set<String>
    var lit: Set<String>?
}

/// Which points are selected, in the order picked. Additive selection comes from
/// a long press.
@MainActor @Observable
final class BrainSelection {
    private(set) var selected: [String] = []

    func click(_ id: String, additive: Bool) {
        if additive {
            if let at = selected.firstIndex(of: id) {
                selected.remove(at: at)
            } else {
                selected.append(id)
            }
            return
        }
        let onlyThis = selected.count == 1 && selected[0] == id
        selected = onlyThis ? [] : [id]
    }

    func selectGroup(_ ids: [String], additive: Bool) {
        var next = additive ? selected : []
        for id in ids where !next.contains(id) { next.append(id) }
        selected = next
    }

    func remove(_ id: String) {
        guard selected.contains(id) else { return }
        selected.removeAll { $0 == id }
    }

    func clear() {
        if !selected.isEmpty { selected = [] }
    }

    /// Drops selected ids that a filter has hidden, keeping the order of the rest.
    func prune(visible: Set<String>) {
        if selected.contains(where: { !visible.contains($0) }) {
            selected = selected.filter { visible.contains($0) }
        }
    }

    func highlight(index: BrainGraphIndex) -> BrainHighlight {
        BrainHighlight(
            selected: Set(selected),
            lit: selected.isEmpty ? nil : BrainGraphModel.litSet(index, ids: selected)
        )
    }
}
