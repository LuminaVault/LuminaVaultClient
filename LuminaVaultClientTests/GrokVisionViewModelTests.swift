// LuminaVaultClient/LuminaVaultClientTests/GrokVisionViewModelTests.swift

import XCTest
@testable import LuminaVaultClient

@MainActor
final class GrokVisionViewModelTests: XCTestCase {
    var mockClient: MockGrokClient!
    var sut: GrokVisionViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockClient = MockGrokClient()
        sut = GrokVisionViewModel(client: mockClient)
    }

    func testAnalyseRequiresNonEmptyURLAndPrompt() async {
        sut.imageURL = ""
        sut.prompt = "describe"
        await sut.analyse()
        XCTAssertEqual(mockClient.calls, [])

        sut.imageURL = "https://example.com/image.png"
        sut.prompt = "   "
        await sut.analyse()
        XCTAssertEqual(mockClient.calls, [])
    }

    func testAnalyseHappyPath() async {
        sut.imageURL = "https://example.com/image.png"
        sut.prompt = "describe"
        await sut.analyse()
        if case let .answered(response) = sut.state {
            XCTAssertEqual(response.answer, "stub vision")
        } else {
            XCTFail("expected answered state")
        }
        XCTAssertEqual(
            mockClient.calls,
            [.vision(prompt: "describe", imageURLs: ["https://example.com/image.png"])],
        )
    }

    func testAnalyse400SurfacesRejection() async {
        mockClient.visionResult = .failure(APIError.httpError(statusCode: 400, body: nil))
        sut.imageURL = "bad-url"
        sut.prompt = "describe"
        await sut.analyse()
        if case let .failed(message) = sut.state {
            XCTAssertTrue(message.contains("rejected"))
        } else {
            XCTFail("expected failed state")
        }
    }
}
