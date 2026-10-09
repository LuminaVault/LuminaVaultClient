// LuminaVaultClient/LuminaVaultClient/Features/Chat/AgentRun/AgentRunActivityContent.swift
//
// `MuseChatState` + the user's prompt → `AgentRunAttributes.ContentState`.
// The status copy is the chat header's own (`MuseChatState.status`), so the
// lock screen never says something the thread does not.

import Foundation

enum AgentRunActivityContent {
    static let agentName = "Hermie"
    static let titleMaxLength = 60
    static let fallbackTitle = "Working on your request"
    /// Copy for the final states. "hit a snag" is the header's own; the
    /// header has no "done" line (it celebrates, then says "Ready"), so the
    /// activity says where the answer is.
    static let doneStatus = "has your answer"
    static let stoppedStatus = "stopped"

    /// A running run.
    static func running(_ muse: MuseChatState, title: String?) -> AgentRunAttributes.ContentState {
        let toolLabel: String? = if case let .tool(label) = muse { label } else { nil }
        let stage: AgentRunAttributes.ContentState.Stage = muse == .awaitingApproval ? .waiting : .working
        return .init(title: clampTitle(title), status: muse.status, toolLabel: toolLabel, stage: stage)
    }

    /// A run that has ended, from the follower's terminal phase.
    static func finished(_ phase: ChatRunFollower.Phase, title: String?) -> AgentRunAttributes.ContentState {
        switch phase {
        case .finished:
            .init(title: clampTitle(title), status: doneStatus, toolLabel: nil, stage: .done)
        case .failed:
            .init(title: clampTitle(title), status: MuseChatState.failed.status, toolLabel: nil, stage: .failed)
        case .following:
            // Stopped following before the run ended (cancelled).
            .init(title: clampTitle(title), status: stoppedStatus, toolLabel: nil, stage: .failed)
        }
    }

    /// First line of the prompt, whitespace-collapsed, ≤ `titleMaxLength`.
    static func clampTitle(_ raw: String?) -> String {
        let firstLine = (raw ?? "")
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init) ?? ""
        let collapsed = firstLine
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return fallbackTitle }
        guard collapsed.count > titleMaxLength else { return collapsed }
        return String(collapsed.prefix(titleMaxLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
