// "Show in graph": how a memory screen asks the shell to open the Brain tab on
// it. The shell injects the action; a screen shown anywhere without a shell
// (previews, the Brain's own detail sheet) has none and shows no control.

import SwiftUI

private struct LVShowInGraphKey: EnvironmentKey {
    static let defaultValue: (@MainActor (UUID) -> Void)? = nil
}

extension EnvironmentValues {
    /// Switches to the Brain tab focused on a memory.
    var lvShowInGraph: (@MainActor (UUID) -> Void)? {
        get { self[LVShowInGraphKey.self] }
        set { self[LVShowInGraphKey.self] = newValue }
    }
}

enum BrainShowInGraph {
    static let title = "Show in graph"
}

/// Wraps the shell's action so that tapping "Show in graph" closes this
/// presentation first. Put it on the root of every sheet that can show a
/// memory (or push one): each layer closes itself and calls the one below, so
/// whatever covers the Brain tab is gone when the tab changes.
private struct ClosesOnShowInGraph: ViewModifier {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.lvShowInGraph) private var showInGraph

    func body(content: Content) -> some View {
        content.environment(\.lvShowInGraph, closing)
    }

    private var closing: (@MainActor (UUID) -> Void)? {
        guard let show = showInGraph else { return nil }
        let close = dismiss
        return { @MainActor id in
            close()
            show(id)
        }
    }
}

extension View {
    func closesOnShowInGraph() -> some View {
        modifier(ClosesOnShowInGraph())
    }
}
