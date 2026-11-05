// LuminaVaultClient/LuminaVaultClientTests/QuickAssistant/QuickAssistantActionViewsTests.swift
//
// What a confirm card shows and allows, decided from the model's state. The
// buttons stay live until a result or a request in flight: the client never
// decides a card has expired, because a wrong device clock must not kill a valid
// one. The server's `.expired` answer is what the card shows.
@testable import LuminaVaultClient
import LuminaVaultShared
import XCTest

@MainActor
final class QuickAssistantActionViewsTests: XCTestCase {
    private func ask(expiresAt: Date? = nil, summary: String = "Add to Calendar: Dentist") -> AssistantActionDTO {
        AssistantActionDTO(id: UUID(), kind: .needsConfirm, summary: summary, expiresAt: expiresAt)
    }

    /// Kept for the test's length: a session dropped at once crashes the host on teardown.
    private var sessions: [QuickAssistantSession] = []

    private func model(actions: any AssistantActionsClientProtocol) -> QuickAssistantModel {
        let session = QuickAssistantFixture.session(actions: actions)
        sessions.append(session)
        return session.model
    }

    func testFreshCardIsAskingAndEnabled() {
        let action = ask()
        let state = QuickAssistantConfirmState.of(action, in: model(actions: RecordingActions()))
        XCTAssertEqual(state, .ask(error: nil))
        XCTAssertTrue(state.buttonsEnabled)
    }

    func testPastExpiryStillEnabled() {
        let action = ask(expiresAt: Date(timeIntervalSinceNow: -3_600))
        let state = QuickAssistantConfirmState.of(action, in: model(actions: RecordingActions()))
        XCTAssertTrue(state.buttonsEnabled, "ruling 44: only the server decides a card has expired")
    }

    func testEveryStatusFinishesTheCardWithTheServersMessage() async {
        for status in AssistantActionStatusDTO.allCases {
            let actions = RecordingActions()
            actions.result = .success(.init(status: status, message: "server says \(status.rawValue)"))
            let model = model(actions: actions)
            let action = ask()
            await model.confirm(action)
            let state = QuickAssistantConfirmState.of(action, in: model)
            XCTAssertEqual(state, .finished(.init(status: status, message: "server says \(status.rawValue)")))
            XCTAssertFalse(state.buttonsEnabled, "\(status) is a result: no second tap")
        }
    }

    func testNetworkErrorKeepsTheCardActionableWithTheError() async {
        let actions = RecordingActions()
        actions.result = .failure(APIError.networkFailure(URLError(.notConnectedToInternet)))
        let model = model(actions: actions)
        let action = ask()
        await model.confirm(action)
        let state = QuickAssistantConfirmState.of(action, in: model)
        guard case let .ask(error) = state else { return XCTFail("expected asking, got \(state)") }
        XCTAssertNotNil(error)
        XCTAssertTrue(state.buttonsEnabled)
    }

    func testResolvingDisablesButtons() async {
        let actions = GatedActions()
        let model = model(actions: actions)
        let action = ask()
        let tap = Task { await model.confirm(action) }
        for _ in 0 ..< 400 where !model.resolving.contains(action.id) { try? await Task.sleep(for: .milliseconds(5)) }
        let state = QuickAssistantConfirmState.of(action, in: model)
        XCTAssertEqual(state, .resolving)
        XCTAssertFalse(state.buttonsEnabled)
        actions.release()
        await tap.value
    }

    func testOnlyForgetSummariesAreDestructive() {
        XCTAssertTrue(ask(summary: "Forget this memory: \u{201C}window seats\u{201D}").isDestructive)
        XCTAssertFalse(ask(summary: "Add to Calendar: Forget this memory").isDestructive)
        XCTAssertFalse(ask().isDestructive)
    }
}

/// Holds a confirm open until released, to observe the in-flight state.
final class GatedActions: AssistantActionsClientProtocol, @unchecked Sendable {
    // @unchecked: `continuation` is set by the one in-flight call and read by `release`
    // on the main actor after the test saw the call begin.
    private let lock = NSLock()
    private var continuation: CheckedContinuation<AssistantActionResolutionDTO, any Error>?
    private var released = false

    func release() {
        lock.lock()
        released = true
        let held = continuation
        continuation = nil
        lock.unlock()
        held?.resume(returning: .init(status: .confirmed, message: "Done."))
    }

    func confirm(_: UUID) async throws -> AssistantActionResolutionDTO {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            if released {
                lock.unlock()
                continuation.resume(returning: .init(status: .confirmed, message: "Done."))
            } else {
                self.continuation = continuation
                lock.unlock()
            }
        }
    }

    func cancel(_ id: UUID) async throws -> AssistantActionResolutionDTO { try await confirm(id) }
}
