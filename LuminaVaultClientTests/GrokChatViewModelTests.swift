// LuminaVaultClient/LuminaVaultClientTests/GrokChatViewModelTests.swift

import XCTest
@testable import LuminaVaultClient

@MainActor
final class GrokChatViewModelTests: XCTestCase {
    var mockClient: MockGrokClient!
    var sut: GrokChatViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockClient = MockGrokClient()
        sut = GrokChatViewModel(client: mockClient)
    }

    func testEmptyPromptIsNoop() async {
        sut.prompt = ""
        await sut.ask()
        XCTAssertEqual(mockClient.calls, [])
    }

    func testHappyPath() async {
        sut.prompt = "Hello Grok"
        await sut.ask()
        if case let .answered(response) = sut.state {
            XCTAssertEqual(response.answer, "stub answer")
            XCTAssertEqual(response.model, "grok-4.3")
        } else {
            XCTFail("expected answered state")
        }
        if case .chat(let req) = mockClient.calls.first {
            XCTAssertEqual(req.messages.first?.content, "Hello Grok")
        } else {
            XCTFail("expected chat call")
        }
    }

    func test402FailsWithPremiumPrompt() async {
        mockClient.chatResult = .failure(APIError.httpError(statusCode: 402, data: Data()))
        sut.prompt = "anything"
        await sut.ask()
        if case let .failed(message) = sut.state {
            XCTAssertTrue(message.contains("Premium"))
        } else {
            XCTFail("expected failed state")
        }
    }
}
