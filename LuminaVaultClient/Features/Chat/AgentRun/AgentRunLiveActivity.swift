// LuminaVaultClient/LuminaVaultClient/Features/Chat/AgentRun/AgentRunLiveActivity.swift
//
// Muse Stage D — drives the agent-run Live Activity from `ChatRunFollower`.
//
// Three pieces, split so the parts worth testing are pure:
//
//   * `AgentRunActivityContent` — `MuseChatState` + the user's prompt →
//     `AgentRunAttributes.ContentState`. The status copy is the chat header's
//     own (`MuseChatState.status`), so the lock screen never says something
//     the thread does not.
//   * `LiveActivityThrottle` — coalesces trail churn. A run can emit a
//     progress row several times a second; the lock screen needs a fraction
//     of that, and ActivityKit budgets updates.
//   * `AgentRunLiveActivity` — the ActivityKit side. Local start only
//     (`pushType: nil`): no push-to-start, no push token.

import ActivityKit
import Foundation
import os

private let log = Logger(subsystem: "com.luminavault", category: "live-activity")

// MARK: - Controller seam

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

// MARK: - State mapping

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

// MARK: - Throttle

/// Decides when a new content state goes out. Pure: the clock is passed in.
struct LiveActivityThrottle {
    enum Decision: Equatable {
        /// Send now.
        case send
        /// Hold it and send after this many seconds, unless a newer state
        /// replaces it first (the newest pending state always wins).
        case later(TimeInterval)
        /// Identical to what is already on screen (or already pending).
        case drop
    }

    let minimumInterval: TimeInterval
    private(set) var lastSent: AgentRunAttributes.ContentState?
    private(set) var lastSentAt: Date?
    private(set) var pending: AgentRunAttributes.ContentState?

    init(minimumInterval: TimeInterval = 1.5) {
        self.minimumInterval = minimumInterval
    }

    mutating func offer(_ state: AgentRunAttributes.ContentState, at now: Date) -> Decision {
        if state == lastSent {
            // A newer pending state was superseded by one equal to what is
            // showing: nothing needs to go out.
            pending = nil
            return .drop
        }
        if state == pending { return .drop }
        guard let lastSentAt else {
            markSent(state, at: now)
            return .send
        }
        let elapsed = now.timeIntervalSince(lastSentAt)
        if elapsed >= minimumInterval {
            markSent(state, at: now)
            return .send
        }
        pending = state
        return .later(minimumInterval - elapsed)
    }

    /// The deferred send fired. Returns the state to send, if still wanted.
    mutating func flush(at now: Date) -> AgentRunAttributes.ContentState? {
        guard let pending else { return nil }
        markSent(pending, at: now)
        return pending
    }

    mutating func markSent(_ state: AgentRunAttributes.ContentState, at now: Date) {
        lastSent = state
        lastSentAt = now
        pending = nil
    }
}

// MARK: - ActivityKit

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
            throttle.markSent(state, at: Date())
            log.info("live activity started run=\(runID.uuidString, privacy: .public)")
        } catch {
            // Disabled mid-flight, too many activities, app not foreground:
            // the chat itself still works, so this is a log line, not a UI.
            log.error("live activity start failed: \(String(describing: error), privacy: .public)")
        }
    }

    func update(_ state: AgentRunAttributes.ContentState) {
        guard activity != nil, !ended else { return }
        switch throttle.offer(state, at: Date()) {
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
                if let next = self.throttle.flush(at: Date()) { self.push(next) }
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
            : .after(Date().addingTimeInterval(Self.lingerAfterEnd))
        let final = ActivityContent(state: state, staleDate: nil)
        Task { await activity.end(final, dismissalPolicy: policy) }
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
        Task { await activity.update(next) }
    }

    private func content(_ state: AgentRunAttributes.ContentState) -> ActivityContent<AgentRunAttributes.ContentState> {
        ActivityContent(state: state, staleDate: Date().addingTimeInterval(Self.staleAfter))
    }
}
