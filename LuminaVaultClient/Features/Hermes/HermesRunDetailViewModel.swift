// LuminaVaultClient/LuminaVaultClient/Features/Hermes/HermesRunDetailViewModel.swift
//
// Hermes Companion Phase 1 — one run, live.
//
// The screen has three moving parts: the event trail, the streamed answer,
// and the approval prompt. All three come off one SSE connection, which the
// view owns through `.task { await vm.follow() }` so it tears down when the
// screen goes away.
//
// Resume, not replay. `cursor` is the highest `seq` applied; every connect
// passes it as `?after=`. Backgrounding the app and coming back therefore
// costs the events missed, not the whole run — which matters because a long
// tool-calling run carries hundreds of them.

import Foundation
import LuminaVaultShared
import os

private let log = Logger(subsystem: "com.luminavault", category: "hermes-runs")

@Observable
@MainActor
final class HermesRunDetailViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(HermesRunsFailure)
    }

    private(set) var state: LoadState = .loading
    private(set) var run: HermesRunDTO?
    private(set) var trail: [HermesRunTrailItem] = []
    /// Assistant text assembled from `message.delta`, which arrives a token
    /// at a time and would otherwise flood the trail with one row per token.
    private(set) var liveMessage: String = ""
    /// Highest event `seq` applied — the `?after=` resume cursor.
    private(set) var cursor: Int = 0
    /// True while the feed is connected. Drives the "live" indicator.
    private(set) var isFollowing = false
    /// Non-nil while an approval POST is in flight; carries the choice so the
    /// tapped button can show the spinner.
    private(set) var answeringChoice: HermesApprovalChoice?
    private(set) var isStopping = false
    /// Last failed action. Separate from `state` so a failed approval does
    /// not blank a screen that is otherwise fine.
    var actionError: HermesRunsFailure?

    let runID: UUID
    private let client: any HermesRunsClientProtocol
    /// Backoff walked on consecutive connect attempts that deliver nothing.
    /// Injectable so tests do not sleep through it.
    private let reconnectDelays: [Double]

    init(
        client: any HermesRunsClientProtocol,
        runID: UUID,
        reconnectDelays: [Double] = [1, 2, 5, 10]
    ) {
        self.client = client
        self.runID = runID
        self.reconnectDelays = reconnectDelays
    }

    /// Seeds from a run the caller already holds (list row, start response)
    /// so the screen opens populated instead of spinning.
    convenience init(
        client: any HermesRunsClientProtocol,
        run: HermesRunDTO,
        reconnectDelays: [Double] = [1, 2, 5, 10]
    ) {
        self.init(client: client, runID: run.id, reconnectDelays: reconnectDelays)
        self.run = run
        state = .loaded
    }

    // MARK: - Derived

    var status: HermesRunStatus { run?.status ?? .queued }
    var isTerminal: Bool { status.isTerminal }

    /// The approval to render, if the run is sitting on one. The choices are
    /// whatever the server offered — never a hardcoded list, because Hermes
    /// withholds `always` for some commands.
    var pendingApproval: HermesRunPendingApprovalDTO? {
        guard status == .waitingForApproval else { return nil }
        return run?.pendingApproval
    }

    var canStop: Bool {
        !isTerminal && !isStopping
    }

    // MARK: - Load

    func load() async {
        if run == nil { state = .loading }
        do {
            apply(try await client.get(runID))
            state = .loaded
        } catch is CancellationError {
            return
        } catch {
            let failure = HermesRunsFailure(error)
            // A refresh failure on a screen that already has content should
            // not wipe it — surface it as an action error instead.
            if run == nil {
                state = .failed(failure)
            } else {
                actionError = failure
            }
        }
    }

    // MARK: - Live feed

    /// Follows the run until it is terminal, the task is cancelled, or the
    /// reconnect budget is spent. Safe to call from `.task`.
    func follow() async {
        if run == nil {
            await load()
        }
        guard case .loaded = state else { return }

        // Only attempts that deliver nothing count against the budget. A feed
        // that is making progress may legitimately close and reopen (the
        // server closes it once a run is terminal and drained), and that must
        // not be mistaken for a broken connection.
        var deadAttempts = 0
        while !Task.isCancelled, !isTerminal {
            isFollowing = true
            var delivered = 0
            var failure: HermesRunsFailure?
            do {
                for try await event in client.events(runID, after: cursor) {
                    if Task.isCancelled { break }
                    delivered += 1
                    // Anything that changes what the screen can *do* — an
                    // approval appearing, the run ending — is re-read from
                    // the run itself rather than inferred from the event,
                    // because the run is what carries the offered choices.
                    if apply(event) {
                        await refreshQuietly()
                    }
                }
            } catch is CancellationError {
                isFollowing = false
                return
            } catch {
                let dropped = HermesRunsFailure(error)
                failure = dropped
                log.warning("hermes run feed dropped: \(String(describing: dropped), privacy: .public)")
            }
            isFollowing = false
            if Task.isCancelled { return }

            if let failure, !failure.isRetryable {
                actionError = failure
                return
            }
            // Whether the feed ended or dropped, the run itself is the
            // authority on whether there is anything left to follow.
            await refreshQuietly()
            if isTerminal { return }

            if delivered > 0 {
                deadAttempts = 0
                continue
            }
            guard deadAttempts < reconnectDelays.count else {
                // The run says it is still going but the feed keeps closing
                // empty. Say so rather than spinning a silent live indicator.
                actionError = failure ?? .upstream
                return
            }
            try? await Task.sleep(for: .seconds(reconnectDelays[deadAttempts]))
            deadAttempts += 1
        }
        isFollowing = false
    }

    // MARK: - Commands

    /// Answers the pending approval. `choice` must be one the server offered.
    func approve(_ choice: HermesApprovalChoice) async {
        guard answeringChoice == nil else { return }
        answeringChoice = choice
        actionError = nil
        defer { answeringChoice = nil }
        do {
            apply(try await client.approve(runID, choice: choice))
        } catch is CancellationError {
            return
        } catch {
            let failure = HermesRunsFailure(error)
            actionError = failure
            // "Already answered" is the common race — someone answered from
            // the notification, or from another device. Re-read so the screen
            // shows the truth rather than a stale prompt.
            if failure == .approvalNotPending {
                await refreshQuietly()
            }
        }
    }

    func stop() async {
        guard canStop else { return }
        isStopping = true
        actionError = nil
        defer { isStopping = false }
        do {
            // Hermes answers `stopping`, so the DTO may still read `running`.
            // The terminal state lands on the feed.
            apply(try await client.stop(runID))
        } catch is CancellationError {
            return
        } catch {
            actionError = HermesRunsFailure(error)
        }
    }

    func retry() async {
        actionError = nil
        await load()
    }

    // MARK: - Applying

    private func apply(_ run: HermesRunDTO) {
        self.run = run
        // The cursor advances only from events actually applied. Taking
        // `run.lastSeq` here would skip every event between what the feed has
        // delivered and what the row already knows about.
        if let summary = run.summary, !summary.isEmpty {
            // On a finished run the summary is the whole answer; mid-run it
            // only seeds a screen opened after the deltas were missed.
            if run.status.isTerminal || liveMessage.isEmpty {
                liveMessage = summary
            }
        }
    }

    /// Applies one event. Returns `true` when the run itself must be re-read
    /// because the event changed what the screen can do.
    @discardableResult
    private func apply(_ event: HermesRunEventDTO) -> Bool {
        guard event.seq > cursor else { return false }
        cursor = event.seq

        if let delta = HermesRunTrailItem.messageDelta(in: event) {
            liveMessage += delta
        } else if let item = HermesRunTrailItem(event: event) {
            trail.append(item)
        }

        switch event.event {
        case "approval.request", "approval.responded",
             "run.completed", "run.failed", "run.cancelled", "error":
            return true
        default:
            return false
        }
    }

    /// Re-reads the run without touching `state` — used on paths where the
    /// screen already has content and a blank "loading" would be a
    /// regression.
    private func refreshQuietly() async {
        guard let fresh = try? await client.get(runID) else { return }
        apply(fresh)
    }
}
