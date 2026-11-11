// A hand-driven stand-in for `Task.sleep`: sleepers wait until the test
// advances virtual time past their deadline. Cancelling a sleeper throws
// `CancellationError`, as the real one does. Nothing here sleeps in real time.

import Foundation
import Synchronization

final class TestSleeper: Sendable {
    private struct Waiter {
        var id: Int
        var deadline: Duration
        var continuation: CheckedContinuation<Void, Error>
    }

    private struct State {
        var now: Duration = .zero
        var nextID = 0
        var registrations = 0
        var waiters: [Waiter] = []
        var registrationWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    }

    private let state = Mutex(State())

    /// Sleepers started so far, cancelled ones included.
    var registrations: Int { state.withLock { $0.registrations } }
    /// Sleepers still waiting.
    var activeCount: Int { state.withLock { $0.waiters.count } }

    /// Pass as the store's `sleep`.
    var sleep: @Sendable (Duration) async throws -> Void {
        { [self] duration in try await sleepFor(duration) }
    }

    private func sleepFor(_ duration: Duration) async throws {
        let id = state.withLock { s -> Int in s.nextID += 1; return s.nextID }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                enum Action { case wait([CheckedContinuation<Void, Never>]), cancel }
                let action = state.withLock { s -> Action in
                    s.registrations += 1
                    let ready = s.registrationWaiters.filter { $0.count <= s.registrations }
                    s.registrationWaiters.removeAll { $0.count <= s.registrations }
                    s.waiters.append(Waiter(id: id, deadline: s.now + duration, continuation: continuation))
                    return .wait(ready.map(\.continuation))
                }
                if case .wait(let ready) = action { for r in ready { r.resume() } }
            }
        } onCancel: {
            let waiter = state.withLock { s -> Waiter? in
                guard let i = s.waiters.firstIndex(where: { $0.id == id }) else { return nil }
                return s.waiters.remove(at: i)
            }
            waiter?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Returns once at least `count` sleepers have started.
    func waitForRegistrations(_ count: Int) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let ready = state.withLock { s -> Bool in
                if s.registrations >= count { return true }
                s.registrationWaiters.append((count, continuation))
                return false
            }
            if ready { continuation.resume() }
        }
    }

    /// Moves virtual time forward and wakes every sleeper whose deadline passed.
    func advance(by duration: Duration) {
        let due = state.withLock { s -> [Waiter] in
            s.now += duration
            let due = s.waiters.filter { $0.deadline <= s.now }
            s.waiters.removeAll { $0.deadline <= s.now }
            return due
        }
        for waiter in due { waiter.continuation.resume() }
    }
}
