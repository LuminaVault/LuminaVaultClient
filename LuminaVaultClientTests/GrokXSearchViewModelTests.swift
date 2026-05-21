// LuminaVaultClient/LuminaVaultClientTests/GrokXSearchViewModelTests.swift

import XCTest
@testable import LuminaVaultClient

@MainActor
final class GrokXSearchViewModelTests: XCTestCase {
    var mockClient: MockGrokClient!
    var sut: GrokXSearchViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockClient = MockGrokClient()
        sut = GrokXSearchViewModel(client: mockClient)
    }

    func testSearchEmptyQueryIsNoop() async {
        sut.query = "   "
        await sut.search()
        XCTAssertEqual(mockClient.calls, [])
        if case .idle = sut.state {} else { XCTFail("expected idle") }
    }

    func testSearchHappyPath() async {
        sut.query = "latest swift news"
        await sut.search()
        if case .results(let response) = sut.state {
            XCTAssertEqual(response.answer, "stub x_search answer")
            XCTAssertEqual(response.citations.count, 1)
        } else {
            XCTFail("expected results, got \(sut.state)")
        }
        XCTAssertEqual(mockClient.calls, [.xSearch(query: "latest swift news")])
    }

    func testSearch402ReturnsFailureWithReconnectFlag() async {
        mockClient.xSearchResult = .failure(APIError.httpError(statusCode: 402, data: Data()))
        sut.query = "anything"
        await sut.search()
        if case let .failed(message, reconnect) = sut.state {
            XCTAssertTrue(reconnect)
            XCTAssertTrue(message.contains("Premium"))
        } else {
            XCTFail("expected failed state")
        }
    }

    func testSearch409ReturnsFailureWithReconnectFlag() async {
        mockClient.xSearchResult = .failure(APIError.httpError(statusCode: 409, data: Data()))
        sut.query = "anything"
        await sut.search()
        if case let .failed(_, reconnect) = sut.state {
            XCTAssertTrue(reconnect)
        } else {
            XCTFail("expected failed state")
        }
    }
}
