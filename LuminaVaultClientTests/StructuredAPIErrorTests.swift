// LuminaVaultClient/LuminaVaultClientTests/StructuredAPIErrorTests.swift
//
// `parse` used to require both `code` and `message`. Hummingbird's plain
// `HTTPError` emits only `message`, so every such failure — an unreachable
// Hermes, a rejected vault, a bad request — was flattened into the useless
// "Server error (N)." These pin the message through.

@testable import LuminaVaultClient
import XCTest

final class StructuredAPIErrorTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testParsesFullEnvelope() {
        let parsed = StructuredAPIError.parse(
            from: data(#"{"error":{"code":"byok_keys_required","message":"Add an LLM API key.","cta":["add_key"]}}"#)
        )
        XCTAssertEqual(parsed?.code, "byok_keys_required")
        XCTAssertEqual(parsed?.message, "Add an LLM API key.")
        XCTAssertEqual(parsed?.cta, ["add_key"])
    }

    /// The regression this file exists for: Hummingbird's `HTTPError`.
    func testParsesMessageWithoutCode() {
        let parsed = StructuredAPIError.parse(from: data(#"{"error":{"message":"hermes_unreachable"}}"#))
        XCTAssertEqual(parsed?.message, "hermes_unreachable")
        XCTAssertEqual(parsed?.code, "", "absent code should be empty, not a parse failure")
        XCTAssertEqual(parsed?.cta, [])
    }

    func testMessageOnlyEnvelopeReachesTheUser() {
        let error = APIError.httpError(statusCode: 502, data: data(#"{"error":{"message":"hermes_unreachable"}}"#))
        XCTAssertEqual(error.userFacingMessage, "hermes_unreachable")
        XCTAssertNotEqual(error.userFacingMessage, "Server error (502).")
    }

    func testCodeWithoutMessageIsNotUsable() {
        XCTAssertNil(StructuredAPIError.parse(from: data(#"{"error":{"code":"nope"}}"#)))
    }

    func testEmptyMessageIsRejectedSoTheStatusFallbackWins() {
        let parsed = StructuredAPIError.parse(from: data(#"{"error":{"message":""}}"#))
        XCTAssertNil(parsed, "an empty message is worse than the status line")
        let error = APIError.httpError(statusCode: 500, data: data(#"{"error":{"message":""}}"#))
        XCTAssertEqual(error.userFacingMessage, "Server error (500).")
    }

    func testNonEnvelopeBodiesStillFallBack() {
        XCTAssertNil(StructuredAPIError.parse(from: data("not json")))
        XCTAssertNil(StructuredAPIError.parse(from: data(#"{"paywall":true,"paywallId":"default"}"#)))
    }

    /// A code-less envelope must not accidentally match a recovery action.
    func testRecoveryActionsAreEmptyWithoutCode() {
        let error = APIError.httpError(statusCode: 403, data: data(#"{"error":{"message":"nope"}}"#))
        XCTAssertTrue(error.chatRecoveryActions.isEmpty)
    }

    func testLegacyByokCodeStillYieldsRecoveryActions() {
        let error = APIError.httpError(
            statusCode: 403,
            data: data(#"{"error":{"code":"byok_keys_required","message":"Add a key."}}"#)
        )
        XCTAssertEqual(error.chatRecoveryActions, [.addKey, .switchToManaged])
    }
}
