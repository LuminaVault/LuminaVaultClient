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
