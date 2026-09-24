// LuminaVaultClient/LuminaVaultClient/Features/Chat/AgentRun/ChatRunFollower.swift
//
// Follows the Hermes agent run answering an escalated chat turn.
//
// A chat turn that asks for something to be *done* is answered by a run
// rather than the ordinary stream. The chat stream carries a pointer to the
// run and then closes; the answer and the tool trail arrive here.
//
// Why a second connection rather than folding run events into the chat
// stream: the run feed is the only one with a durable cursor. Its events are
// persisted with a monotonic `seq` and replayed from `?after=`, it keepalives,
// and it carries approvals and stop. The chat stream has neither cursor nor
// keepalive, so re-emitting run events onto it would put an unreplayable copy
// of a durable log on a connection that cannot resume — and every reconnect
// would drop or duplicate tool rows.
//
// Deliberately NOT an extraction of `HermesRunDetailViewModel`. That type
// owns a whole screen: its load state, its error surface, its stop and
// approve spinners. Chat needs a trail, an answer and a pending approval, and
// nothing else. Pulling a shared base out of a working screen to save a
// reconnect loop would put a refactor of the Agent Runs UI on the critical
// path of the chat feature. What the two genuinely share — the event-to-row
// mapping — is already shared, in `HermesRunTrailItem`.

import Foundation
import LuminaVaultShared
import os

private let log = Logger(subsystem: "com.luminavault", category: "chat-run")

@Observable
@MainActor
final class ChatRunFollower {
    enum Phase: Equatable {
        case following
        case finished
        case failed(String)
    }

    let runID: UUID
    /// The Hermes session behind the run. Artifacts are keyed by session, so
    /// this is what scopes the chat's artifact strip to this turn.
    private(set) var sessionID: String?

    private(set) var trail: [HermesRunTrailItem] = []
    /// Assistant text assembled from `message.delta`, which arrives a token
    /// at a time and would otherwise be one trail row per token.
    private(set) var answer: String = ""
    private(set) var phase: Phase = .following
    /// Highest `seq` applied — the `?after=` resume cursor and the dedupe
    /// watermark, since replay-then-live re-sends what we already hold.
    private(set) var cursor: Int = 0
    private(set) var pendingApproval: HermesRunTrailItem?
    private(set) var isAnswering = false
    /// Tools the run has invoked, for the turn receipt. Counted from
    /// `tool.started` rather than from trail rows: a start and its completion
    /// are both `.tool` rows, so counting rows would report every call twice.
    private(set) var toolCallCount = 0
    /// What the agent ran in its terminal and what it printed. Empty on a
    /// Hermes that does not stream terminal output.
    private(set) var terminal: [AgentTerminalEntry] = []
    /// At least one answer token has arrived. Stored and written once, so the
    /// chat header can tell "writing" from "working" without observing
    /// `answer`, which changes on every token.
    private(set) var hasAnswer = false

    private let client: any HermesRunsClientProtocol
    /// Injectable so tests do not sleep through the backoff.
    private let reconnectDelays: [Double]

    /// Muse Stage D — the lock-screen / Dynamic Island view of this run.
    /// Started when following begins (the turn has just become delegated),
    /// updated as the trail moves, ended when the run does. nil in tests and
    /// previews that do not care.
    private let liveActivity: (any AgentRunLiveActivityControlling)?
    /// The thread this run answers; the activity's tap target.
    let conversationID: UUID?
    /// What the user asked; the activity's title line.
    let title: String?

    init(
        client: any HermesRunsClientProtocol,
        runID: UUID,
        sessionID: String? = nil,
        conversationID: UUID? = nil,
        title: String? = nil,
        liveActivity: (any AgentRunLiveActivityControlling)? = nil,
        reconnectDelays: [Double] = [1, 2, 5, 10]
    ) {
        self.client = client
        self.runID = runID
        self.sessionID = sessionID
        self.conversationID = conversationID
        self.title = title
        self.liveActivity = liveActivity
        self.reconnectDelays = reconnectDelays
    }

    /// The run as the chat header would describe it — the same derivation,
    /// pinned to `.delegated` because that is the only phase a follower
    /// exists in.
    var museState: MuseChatState {
        MuseChatState.derive(MuseChatState.Inputs(
            phase: .delegated,
            hasFirstToken: hasAnswer,
            lastTrailItem: trail.last,
            isAwaitingApproval: pendingApproval != nil
        ))
    }

    /// What the Live Activity shows right now.
    var activityState: AgentRunAttributes.ContentState {
        if phase == .following {
            return AgentRunActivityContent.running(museState, title: title)
        }
        // A `run.failed` / `run.cancelled` event ends the feed as
        // `.finished` (the transcript settles the same way either way), but
        // the lock screen must not say "has your answer" for it.
        if phase == .finished, let terminalEvent, terminalEvent != "run.completed", !terminalEvent.hasPrefix("watcher.") {
            return AgentRunActivityContent.finished(.failed(terminalEvent), title: title)
        }
        return AgentRunActivityContent.finished(phase, title: title)
    }

    /// The terminal event that ended the feed, when one did.
    private(set) var terminalEvent: String?

    var isFinished: Bool { phase == .finished }

    /// Follows until the run is terminal, the task is cancelled, or the feed
    /// stops producing anything.
    func follow(after: Int = 0) async {
        liveActivity?.start(runID: runID, conversationID: conversationID, state: activityState)
        await followFeed(after: after)
        // Every exit — terminal event, terminal status on re-read, dead feed,
        // cancellation — ends the activity. A cancelled follow means the user
        // left the turn (new chat, another thread): nothing is tracking the
        // run any more, so it leaves the lock screen now rather than
        // claiming progress it cannot see.
        if phase == .following {
            liveActivity?.end(AgentRunActivityContent.finished(.following, title: title), immediately: true)
        } else {
            liveActivity?.end(activityState, immediately: false)
        }
    }

    private func followFeed(after: Int) async {
        cursor = max(cursor, after)

        // Only attempts that deliver nothing count against the budget. A feed
        // that is making progress may legitimately close and reopen — the
        // server closes it once a run is terminal and drained — and that must
        // not be mistaken for a broken connection.
        var deadAttempts = 0
        while !Task.isCancelled, phase == .following {
            var delivered = 0
            var dropped: Error?
            do {
                for try await event in client.events(runID, after: cursor) {
                    if Task.isCancelled { break }
                    delivered += 1
                    apply(event)
                    if phase != .following { return }
                }
            } catch is CancellationError {
                return
            } catch {
                dropped = error
                log.warning("chat run feed dropped: \(String(describing: error), privacy: .public)")
            }
            if Task.isCancelled { return }

            // The run itself is the authority on whether anything is left to
            // follow: the feed can end without the terminal event reaching us.
            if let run = try? await client.get(runID) {
                sessionID = run.sessionID ?? sessionID
                if run.status.isTerminal {
                    adoptTerminal(run)
                    return
                }
            }

            if delivered > 0 {
                deadAttempts = 0
            } else {
                deadAttempts += 1
                // The cap covers a feed that closes cleanly without ever
                // sending a terminal event as well as one that errors.
                // Counting only errors would spin here forever, replaying the
                // same frames, every one at or below the cursor.
                guard deadAttempts <= reconnectDelays.count else {
                    phase = .failed(Self.describe(dropped))
                    return
                }
                let delay = reconnectDelays[min(deadAttempts - 1, reconnectDelays.count - 1)]
                try? await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// Answers a tool waiting on the user.
    func respond(_ choice: HermesApprovalChoice) async {
        guard !isAnswering else { return }
        isAnswering = true
        defer { isAnswering = false }
        _ = try? await client.approve(runID, choice: choice)
        pendingApproval = nil
        publishActivity()
    }

    /// Stops the run. The run keeps its own record; this ends our interest.
    func stop() async {
        _ = try? await client.stop(runID)
        if let run = try? await client.get(runID) {
            adoptTerminal(run)
        } else {
            phase = .finished
        }
        // `stopDelegatedRun` cancels the follow task first, which may already
        // have ended the activity as "stopped"; `end` is idempotent.
        liveActivity?.end(activityState, immediately: false)
    }

    // MARK: - Reduction

    /// Exposed for tests: the same reducer the live feed uses, so a replayed
    /// sequence exercises exactly the production path.
    func apply(_ event: HermesRunEventDTO) {
        guard event.seq > cursor else { return }
        cursor = event.seq
        defer { publishActivity() }

        if event.event == "tool.started" {
            toolCallCount += 1
        }

        if let next = AgentTerminalTranscript.apply(event, to: terminal) {
            terminal = next
        }

        if let delta = HermesRunTrailItem.messageDelta(in: event) {
            answer += delta
            if !hasAnswer, !delta.isEmpty { hasAnswer = true }
            return
        }

        if var item = HermesRunTrailItem(event: event) {
            // A progress row that does not name its tool is still that tool
            // running: keep its label, so the header does not drop "is
            // searching the web" on every progress tick.
            if item.toolLabel == nil, Self.progressEvents.contains(event.event) {
                item.toolLabel = trail.last?.toolLabel
            }
            trail.append(item)
            switch event.event {
            case "approval.request": pendingApproval = item
            case "approval.responded": pendingApproval = nil
            default: break
            }
        }

        if Self.isTerminal(event.event) {
            terminalEvent = event.event
            pendingApproval = nil
            phase = .finished
        }
    }

    /// Offers the current state to the activity. The controller drops
    /// repeats and throttles the rest, so this is safe to call per event.
    private func publishActivity() {
        guard phase == .following else { return }
        liveActivity?.update(activityState)
    }

    private func adoptTerminal(_ run: HermesRunDTO) {
        sessionID = run.sessionID ?? sessionID
        // On a finished run the summary is the whole answer; it also seeds a
        // follower that attached after the deltas were missed.
        if let summary = run.summary, !summary.isEmpty, answer.isEmpty || run.status.isTerminal {
            answer = summary
            hasAnswer = true
        }
        pendingApproval = nil
        phase = run.status == .failed ? .failed(run.error ?? "The run failed.") : .finished
    }

    private static let progressEvents: Set<String> = [
        "tool.progress", "hermes.tool.progress", "reasoning.available",
    ]

    static func isTerminal(_ event: String) -> Bool {
        ["run.completed", "run.failed", "run.cancelled"].contains(event) || event.hasPrefix("watcher.")
    }

    private static func describe(_ error: Error?) -> String {
        guard let error else { return "Lost contact with this run." }
        return HermesRunsFailure(error).message
    }
}
