// LuminaVaultClient/LuminaVaultClient/Features/Chat/AgentRun/AgentRunAttributes.swift
//
// Muse Stage D — the Live Activity for a chat turn that escalated to a Hermes
// agent run ("Hermie is still working — you can leave").
//
// This file is compiled into BOTH targets (main app + widget extension; see
// the "Exceptions for LuminaVaultClient folder in LuminaVaultWidgetsExtension"
// set in the project). ActivityKit matches an activity to its widget by this
// type, so there must be exactly one definition. Keep it dependency-free:
// Foundation + ActivityKit only, no LuminaVaultShared, no app types.
//
// UI-only view state, not a DTO: the app starts and updates the activity
// locally. There is no push-to-start and no push token.

import ActivityKit
import Foundation

nonisolated struct AgentRunAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable, Sendable {
        nonisolated enum Stage: String, Codable, Hashable, Sendable {
            /// The run is working. The avatar ring animates.
            case working
            /// Blocked on the user answering an approval prompt.
            case waiting
            /// The answer is in the thread.
            case done
            /// The run failed or was stopped.
            case failed
        }

        /// What the user asked, clamped to one short line.
        var title: String
        /// The Muse status line after the agent's name, e.g. "is searching
        /// the web" — the same copy as the chat header (`MuseChatState`).
        var status: String
        /// The running tool's verb phrase, when one is known.
        var toolLabel: String?
        var stage: Stage
    }

    let runID: UUID
    /// The thread the run answers. Tapping the activity opens it.
    let conversationID: UUID?
    /// "Hermie".
    let agentName: String

    /// `luminavault://chat/<id>` — the same URL a proactive chat push
    /// carries, routed by `NotificationRouter.deepLink(from:)`.
    var deepLink: URL? {
        conversationID.flatMap { URL(string: "luminavault://chat/\($0.uuidString)") }
    }
}
