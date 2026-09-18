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

    private let client: any HermesRunsClientProtocol
    /// Injectable so tests do not sleep through the backoff.
    private let reconnectDelays: [Double]

    init(
        client: any HermesRunsClientProtocol,
        runID: UUID,
        sessionID: String? = nil,
        reconnectDelays: [Double] = [1, 2, 5, 10]
    ) {
        self.client = client
        self.runID = runID
        self.sessionID = sessionID
        self.reconnectDelays = reconnectDelays
    }

    var isFinished: Bool { phase == .finished }

    /// Follows until the run is terminal, the task is cancelled, or the feed
    /// stops producing anything.
    func follow(after: Int = 0) async {
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
    }

    /// Stops the run. The run keeps its own record; this ends our interest.
    func stop() async {
        _ = try? await client.stop(runID)
        if let run = try? await client.get(runID) {
            adoptTerminal(run)
        } else {
            phase = .finished
        }
    }

    // MARK: - Reduction

    /// Exposed for tests: the same reducer the live feed uses, so a replayed
    /// sequence exercises exactly the production path.
    func apply(_ event: HermesRunEventDTO) {
        guard event.seq > cursor else { return }
        cursor = event.seq

        if let delta = HermesRunTrailItem.messageDelta(in: event) {
            answer += delta
            return
        }

        if let item = HermesRunTrailItem(event: event) {
            trail.append(item)
            switch event.event {
            case "approval.request": pendingApproval = item
            case "approval.responded": pendingApproval = nil
            default: break
            }
        }

        if Self.isTerminal(event.event) {
            pendingApproval = nil
            phase = .finished
        }
    }

    private func adoptTerminal(_ run: HermesRunDTO) {
        sessionID = run.sessionID ?? sessionID
        // On a finished run the summary is the whole answer; it also seeds a
        // follower that attached after the deltas were missed.
        if let summary = run.summary, !summary.isEmpty, answer.isEmpty || run.status.isTerminal {
            answer = summary
        }
        pendingApproval = nil
        phase = run.status == .failed ? .failed(run.error ?? "The run failed.") : .finished
    }

    static func isTerminal(_ event: String) -> Bool {
        ["run.completed", "run.failed", "run.cancelled"].contains(event) || event.hasPrefix("watcher.")
    }

    private static func describe(_ error: Error?) -> String {
        guard let error else { return "Lost contact with this run." }
        return HermesRunsFailure(error).message
    }
}
