// LuminaVaultClient/LuminaVaultClient/Features/Chat/AgentRun/AgentRunLiveActivityControlling.swift

import Foundation

/// What `ChatRunFollower` needs from a Live Activity. One instance per run.
@MainActor
protocol AgentRunLiveActivityControlling: AnyObject {
    func start(runID: UUID, conversationID: UUID?, state: AgentRunAttributes.ContentState)
    func update(_ state: AgentRunAttributes.ContentState)
    /// `immediately` removes it from the lock screen now (the user left the
    /// thread, so nothing is being tracked any more); otherwise the final
    /// state lingers briefly so the user sees the run finished.
    func end(_ state: AgentRunAttributes.ContentState, immediately: Bool)
}
