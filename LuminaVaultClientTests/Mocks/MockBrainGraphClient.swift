// Scripted BrainGraphClientProtocol fake. Records every request and answers
// from a queue of results; the last queued result repeats once the queue is
// down to one.
//
// For the store's request rules it can also answer "once" (consumed in order,
// ahead of the repeating queue) and hold a response until the test releases
// it. A held response can behave like URLSession (throws `CancellationError`
// when the awaiting task is cancelled) or like a transport that does not
// notice, which is what the "late response is ignored" case needs.

@testable import LuminaVaultClient
import Foundation
import LuminaVaultShared
import Synchronization

/// One response the test releases by hand.
final class HeldBrainResponse: Sendable {
    private struct State {
        var continuation: CheckedContinuation<BrainGraphResponse, Error>?
        var released: Result<BrainGraphResponse, Error>?
        var cancelled = false
    }

    private let state = Mutex(State())
    private let honoursCancellation: Bool

    init(honoursCancellation: Bool) {
        self.honoursCancellation = honoursCancellation
    }

    /// True once the task awaiting this response was cancelled.
    var wasCancelled: Bool { state.withLock { $0.cancelled } }

    func release(_ response: BrainGraphResponse) { finish(.success(response)) }
    func release(throwing error: Error) { finish(.failure(error)) }

    private func finish(_ result: Result<BrainGraphResponse, Error>) {
        let continuation = state.withLock { s -> CheckedContinuation<BrainGraphResponse, Error>? in
            s.released = result
            defer { s.continuation = nil }
            return s.continuation
        }
        continuation?.resume(with: result)
    }

    fileprivate func wait() async throws -> BrainGraphResponse {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                enum Action { case wait, resume(Result<BrainGraphResponse, Error>), cancel }
                let action = state.withLock { s -> Action in
                    if let released = s.released { return .resume(released) }
                    if s.cancelled, honoursCancellation { return .cancel }
                    s.continuation = continuation
                    return .wait
                }
                switch action {
                case .wait: break
                case .resume(let result): continuation.resume(with: result)
                case .cancel: continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            let continuation = state.withLock { s -> CheckedContinuation<BrainGraphResponse, Error>? in
                s.cancelled = true
                guard honoursCancellation else { return nil }
                defer { s.continuation = nil }
                return s.continuation
            }
            continuation?.resume(throwing: CancellationError())
        }
    }
}

actor MockBrainGraphClient: BrainGraphClientProtocol {
    private enum Once {
        case result(Result<BrainGraphResponse, Error>)
        case held(HeldBrainResponse)
    }

    private var results: [Result<BrainGraphResponse, Error>]
    private var once: [Once] = []
    private var callWaiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []
    private(set) var requests: [BrainGraphRequest] = []

    init(results: [Result<BrainGraphResponse, Error>] = []) {
        self.results = results
    }

    var callCount: Int { requests.count }
    var lastRequest: BrainGraphRequest? { requests.last }

    func enqueue(_ result: Result<BrainGraphResponse, Error>) { results.append(result) }

    /// Answers exactly one call, before anything from `enqueue`.
    func enqueueOnce(_ result: Result<BrainGraphResponse, Error>) { once.append(.result(result)) }

    /// The next call waits until the test releases the returned response.
    func enqueueHeld(honoursCancellation: Bool = true) -> HeldBrainResponse {
        let held = HeldBrainResponse(honoursCancellation: honoursCancellation)
        once.append(.held(held))
        return held
    }

    /// Returns once at least `count` requests have reached the client.
    func waitForCalls(_ count: Int) async {
        if requests.count >= count { return }
        await withCheckedContinuation { callWaiters.append((count, $0)) }
    }

    func fetchGraph(_ request: BrainGraphRequest) async throws -> BrainGraphResponse {
        requests.append(request)
        let ready = callWaiters.filter { $0.count <= requests.count }
        callWaiters.removeAll { $0.count <= requests.count }
        for waiter in ready { waiter.continuation.resume() }

        if !once.isEmpty {
            switch once.removeFirst() {
            case .result(let result): return try result.get()
            case .held(let held): return try await held.wait()
            }
        }
        guard let next = results.first else {
            throw MockBrainGraphError.noResultQueued
        }
        if results.count > 1 { results.removeFirst() }
        return try next.get()
    }
}

enum MockBrainGraphError: Error { case noResultQueued }

/// The app's real error values for the statuses the store tells apart.
extension MockBrainGraphClient {
    static func httpError(_ status: Int) -> APIError {
        .httpError(statusCode: status, data: Data())
    }

    static func rateLimited(retryAfter: TimeInterval? = nil) -> APIError {
        .rateLimited(retryAfter: retryAfter)
    }
}
