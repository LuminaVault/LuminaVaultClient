// LuminaVaultClient/LuminaVaultClient/Services/Capture/CaptureOutcome.swift
//
// What the drainer learned when a capture landed. The queue only says that a
// row went away; the server's answer says which memory it became, and that is
// what lets Home say "Connects to 3 memories" a moment after a save.

import Foundation
import Synchronization

/// One capture that reached the server. UI-agnostic, so it is named for what
/// it is rather than borrowing a wire DTO.
nonisolated struct CaptureOutcome: Sendable, Equatable {
    /// The queue row's id, which is also the id the composer showed.
    let localID: UUID
    /// The memory the save created or updated. Nil for links (the server
    /// enriches them later) and for older servers that do not say.
    let memoryID: UUID?
}

/// Fans each outcome out to whoever is listening right now.
///
/// The drainer is an actor and its listeners are main-actor view models that
/// come and go with their screens, so this is a lock around a dictionary of
/// continuations rather than a single `AsyncStream`: one stream has one
/// consumer, and a second `for await` would silently steal half the values.
/// Nobody listening is the normal case and costs nothing — outcomes are not
/// buffered for late subscribers, because a "connects to" banner for a save
/// made before Home was on screen would be news about the past.
nonisolated final class CaptureOutcomeBroadcaster: Sendable {
    private let continuations = Mutex<[UUID: AsyncStream<CaptureOutcome>.Continuation]>([:])

    init() {}

    /// A stream of outcomes from now on. Ends when the consuming task is
    /// cancelled, which unregisters it.
    func subscribe() -> AsyncStream<CaptureOutcome> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<CaptureOutcome>.makeStream(
            bufferingPolicy: .bufferingNewest(8)
        )
        continuation.onTermination = { [weak self] _ in
            _ = self?.continuations.withLock { $0.removeValue(forKey: id) }
        }
        continuations.withLock { $0[id] = continuation }
        return stream
    }

    func publish(_ outcome: CaptureOutcome) {
        let listeners = continuations.withLock { Array($0.values) }
        for continuation in listeners {
            continuation.yield(outcome)
        }
    }

    /// Number of live subscribers. For tests.
    var subscriberCount: Int {
        continuations.withLock { $0.count }
    }
}
