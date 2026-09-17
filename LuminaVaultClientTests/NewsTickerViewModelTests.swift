// LuminaVaultClient/LuminaVaultClientTests/NewsTickerViewModelTests.swift
//
// The breaking-news strip paints from cache, refreshes from the network and
// writes through; a 404/409 hides it; a failed refresh keeps the cached strip
// and marks it stale.

import Foundation
import LuminaVaultShared
import SwiftData
import XCTest

@testable import LuminaVaultClient

@MainActor
final class NewsTickerViewModelTests: XCTestCase {
    private final class StubClient: NewsTickerClientProtocol, @unchecked Sendable {
        var result: Result<NewsTickerResponse, Error> = .success(NewsTickerResponse(items: [], stale: false, generatedAt: .now))
        private(set) var calls = 0
        func ticker(limit _: Int) async throws -> NewsTickerResponse {
            calls += 1
            return try result.get()
        }
    }

    private func item(_ id: String) -> NewsTickerItemDTO {
        NewsTickerItemDTO(id: id, title: "Headline \(id)", url: "https://pub.example/\(id)", source: "BBC", sourceUrl: nil, publishedAt: .now)
    }

    private func makeSUT(cached: [NewsTickerItemDTO] = [], result: Result<NewsTickerResponse, Error>) throws -> (NewsTickerViewModel, StubClient, NewsTickerLocalStore) {
        let store = NewsTickerLocalStore(container: try SwiftDataStack.makeInMemory())
        if !cached.isEmpty {
            try store.replace(with: cached, stale: false, fetchedAt: .now)
        }
        let client = StubClient()
        client.result = result
        return (NewsTickerViewModel(client: client, store: store), client, store)
    }

    func testCacheFirstThenNetworkWritesThrough() throws {
        let (sut, _, store) = try makeSUT(cached: [item("old")], result: .success(NewsTickerResponse(items: [item("new")], stale: false, generatedAt: .now)))
        sut.loadFromCache()
        XCTAssertEqual(sut.items.map(\.id), ["old"])
        XCTAssertTrue(sut.isStale, "a cached strip is old until the network confirms it")

        let exp = expectation(description: "refresh")
        Task { await sut.refresh(); exp.fulfill() }
        wait(for: [exp], timeout: 2)

        XCTAssertEqual(sut.items.map(\.id), ["new"])
        XCTAssertFalse(sut.isStale)
        XCTAssertEqual(try store.load()?.items.map(\.id), ["new"])
    }

    func testNotInstalledHidesAndClearsCache() throws {
        let (sut, _, store) = try makeSUT(cached: [item("old")], result: .failure(APIError.httpError(statusCode: 404, data: Data())))
        sut.loadFromCache()
        let exp = expectation(description: "refresh")
        Task { await sut.refresh(); exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertFalse(sut.installed)
        XCTAssertTrue(sut.isHidden)
        XCTAssertNil(try store.load())
    }

    func testFailureKeepsCacheAndMarksStale() throws {
        struct Boom: Error {}
        let (sut, _, _) = try makeSUT(cached: [item("old")], result: .failure(Boom()))
        sut.loadFromCache()
        let exp = expectation(description: "refresh")
        Task { await sut.refresh(); exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(sut.items.map(\.id), ["old"])
        XCTAssertTrue(sut.isStale)
        XCTAssertFalse(sut.isHidden)
    }

    func testRefreshIfStaleSkipsRecentFetch() throws {
        let (sut, client, _) = try makeSUT(result: .success(NewsTickerResponse(items: [item("a")], stale: false, generatedAt: .now)))
        let exp = expectation(description: "refresh")
        Task {
            await sut.refresh()
            await sut.refreshIfStale(maxAge: 300)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(client.calls, 1)
    }
}
