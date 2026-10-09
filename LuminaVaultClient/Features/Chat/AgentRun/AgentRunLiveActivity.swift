// LuminaVaultClient/LuminaVaultClient/Features/Chat/AgentRun/AgentRunLiveActivity.swift
//
// Muse Stage D — drives the agent-run Live Activity from `ChatRunFollower`.
//
// Three pieces, split so the parts worth testing are pure:
//
//   * `AgentRunActivityContent` — the state mapping (pure).
//   * `LiveActivityThrottle` — the update throttle (pure, clock passed in).
//   * `AgentRunLiveActivity` (this file) — the ActivityKit side. Local start
//     only (`pushType: nil`): no push-to-start, no push token.
//
// `ChatRunFollower` sees it through `AgentRunLiveActivityControlling`.

import ActivityKit
import Foundation
import os

nonisolated private let log = Logger(subsystem: "com.luminavault", category: "live-activity")

@MainActor
final class AgentRunLiveActivity: AgentRunLiveActivityControlling {
    /// How long before an un-updated activity reads as stale. The app is
    /// suspended soon after the user leaves, and the follower with it; past
    /// this the lock screen says so instead of claiming progress.
    static let staleAfter: TimeInterval = 20 * 60
    /// How long a finished run stays on the lock screen.
    static let lingerAfterEnd: TimeInterval = 15 * 60

    /// Activities this process is driving. Anything else at launch is left
    /// over from a process that was killed mid-run.
    private static var liveIDs: Set<String> = []

    private var activity: Activity<AgentRunAttributes>?
    private var throttle = LiveActivityThrottle()
    private var flushTask: Task<Void, Never>?
    private var ended = false

    /// The user's system-level Live Activities switch for this app.
    static var isEnabled: Bool {
        ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func start(runID: UUID, conversationID: UUID?, state: AgentRunAttributes.ContentState) {
        guard activity == nil, !ended, Self.isEnabled else { return }
        let attributes = AgentRunAttributes(
            runID: runID,
            conversationID: conversationID,
            agentName: AgentRunActivityContent.agentName
        )
        do {
            let started = try Activity.request(
                attributes: attributes,
                content: content(state),
                pushType: nil
            )
            activity = started
            Self.liveIDs.insert(started.id)
            throttle.markSent(state, at: Date.now)
            log.info("live activity started run=\(runID.uuidString, privacy: .public)")
        } catch {
            // Disabled mid-flight, too many activities, app not foreground:
            // the chat itself still works, so this is a log line, not a UI.
            log.error("live activity start failed: \(String(describing: error), privacy: .public)")
        }
    }

    func update(_ state: AgentRunAttributes.ContentState) {
        guard activity != nil, !ended else { return }
        switch throttle.offer(state, at: Date.now) {
        case .drop:
            return
        case .send:
            flushTask?.cancel()
            flushTask = nil
            push(state)
        case let .later(delay):
            guard flushTask == nil else { return }
            flushTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled, let self else { return }
                self.flushTask = nil
                if let next = self.throttle.flush(at: Date.now) { self.push(next) }
            }
        }
    }

    func end(_ state: AgentRunAttributes.ContentState, immediately: Bool) {
        guard !ended else { return }
        ended = true
        flushTask?.cancel()
        flushTask = nil
        guard let activity else { return }
        Self.liveIDs.remove(activity.id)
        let policy: ActivityUIDismissalPolicy = immediately
            ? .immediate
            : .after(Date.now.addingTimeInterval(Self.lingerAfterEnd))
        let final = ActivityContent(state: state, staleDate: nil)
        let id = activity.id
        Task { await Self.endActivity(id: id, final, dismissalPolicy: policy) }
    }

    /// Ends activities no live follower owns — left by a process that was
    /// killed or crashed mid-run, which would otherwise claim "still
    /// working" until the system times them out hours later.
    static func endOrphans() async {
        for activity in Activity<AgentRunAttributes>.activities where !liveIDs.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    private func push(_ state: AgentRunAttributes.ContentState) {
        guard let activity else { return }
        let next = content(state)
        let id = activity.id
        Task { await Self.updateActivity(id: id, next) }
    }

    // `Activity` is not Sendable, and `end` / `update` are nonisolated, so
    // calling them on the stored activity from the main actor sends it off
    // the actor. These look the activity up by id on the nonisolated side
    // instead, so it never crosses.

    nonisolated private static func endActivity(
        id: String,
        _ content: ActivityContent<AgentRunAttributes.ContentState>,
        dismissalPolicy: ActivityUIDismissalPolicy
    ) async {
        guard let activity = Activity<AgentRunAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.end(content, dismissalPolicy: dismissalPolicy)
    }

    nonisolated private static func updateActivity(
        id: String,
        _ content: ActivityContent<AgentRunAttributes.ContentState>
    ) async {
        guard let activity = Activity<AgentRunAttributes>.activities.first(where: { $0.id == id }) else { return }
        await activity.update(content)
    }

    private func content(_ state: AgentRunAttributes.ContentState) -> ActivityContent<AgentRunAttributes.ContentState> {
        ActivityContent(state: state, staleDate: Date.now.addingTimeInterval(Self.staleAfter))
    }
}
