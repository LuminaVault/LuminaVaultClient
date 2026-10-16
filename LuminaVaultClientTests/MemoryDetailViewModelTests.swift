// LuminaVaultClient/LuminaVaultClientTests/MemoryDetailViewModelTests.swift
//
// A memory opened by id: from a link, a recap highlight, or a "Connects to"
// row. Only the memory itself decides whether the screen loads; what it
// connects to and where it came from are extras that fail quietly.

import Foundation
import LuminaVaultShared
import XCTest

@testable import LuminaVaultClient

@MainActor
final class MemoryDetailViewModelTests: XCTestCase {
    private let memoryID = UUID()

    private func memory(_ content: String = "We ship on Tuesdays") -> MemoryDTO {
        MemoryDTO(id: memoryID, content: content, tags: ["process"], createdAt: .now, reviewState: "approved")
    }

    func testLoadShowsTheMemoryAndWhatItConnectsTo() async {
        let client = MockMemoryClient()
        client.getResult = .success(memory())
        let other = RelatedMemoryDTO.fixture()
        client.relatedResult = .success(MemoryRelatedResponse(
            memoryId: memoryID,
            // The server should never list a memory as related to itself;
            // if it does, the screen must not link to the page it is on.
            items: [other, .fixture(id: memoryID)]
        ))
        let sut = MemoryDetailViewModel(memoryID: memoryID, client: client)

        await sut.load()

        XCTAssertEqual(sut.memory?.content, "We ship on Tuesdays")
        XCTAssertEqual(sut.related, .loaded([other]))
        XCTAssertEqual(client.getCalls, [memoryID])
        XCTAssertEqual(client.relatedCalls.first?.limit, MemoryDetailViewModel.relatedLimit)
    }

    func testAMissingMemorySaysItIsGone() async {
        let client = MockMemoryClient()
        client.getResult = .failure(APIError.httpError(statusCode: 404, data: Data()))
        let sut = MemoryDetailViewModel(memoryID: memoryID, client: client)

        await sut.load()

        XCTAssertEqual(sut.state, .failed("This memory no longer exists."))
    }

    func testAFailedRelatedLookupStillShowsTheMemory() async {
        let client = MockMemoryClient()
        client.getResult = .success(memory())
        let sut = MemoryDetailViewModel(memoryID: memoryID, client: client)

        await sut.load()

        XCTAssertNotNil(sut.memory)
        XCTAssertEqual(sut.related, .failed)
        XCTAssertTrue(sut.provenanceFailed, "the source section goes away instead of spinning")
    }

    func testDeleteReportsSuccess() async {
        let client = MockMemoryClient()
        client.getResult = .success(memory())
        let sut = MemoryDetailViewModel(memoryID: memoryID, client: client)
        await sut.load()

        let deleted = await sut.delete()

        XCTAssertTrue(deleted)
        XCTAssertEqual(client.deleteCalls, [memoryID])
        XCTAssertNil(sut.actionError)
    }

    func testAFailedDeleteKeepsTheScreenAndSaysSo() async {
        let client = MockMemoryClient()
        client.getResult = .success(memory())
        client.deleteError = APIError.httpError(statusCode: 500, data: Data())
        let sut = MemoryDetailViewModel(memoryID: memoryID, client: client)
        await sut.load()

        let deleted = await sut.delete()

        XCTAssertFalse(deleted)
        XCTAssertEqual(sut.actionError, "Couldn't delete this memory.")
        XCTAssertNotNil(sut.memory)
    }

    func testReloadPicksUpAnEdit() async {
        let client = MockMemoryClient()
        client.getResult = .success(memory())
        let sut = MemoryDetailViewModel(memoryID: memoryID, client: client)
        await sut.load()

        client.getResult = .success(memory("We ship on Wednesdays"))
        await sut.reload()

        XCTAssertEqual(sut.memory?.content, "We ship on Wednesdays")
        XCTAssertEqual(client.relatedCalls.count, 1, "an edit does not refetch what it connects to")
    }
}
