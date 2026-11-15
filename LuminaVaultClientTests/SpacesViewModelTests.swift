// LuminaVaultClient/LuminaVaultClientTests/SpacesViewModelTests.swift
// HER-35 — covers load/create/update/delete on SpacesViewModel + the
// category filter / search query derived state.

@testable import LuminaVaultClient
import Foundation
import XCTest

@MainActor
final class SpacesViewModelTests: XCTestCase {
    func testLoadPopulatesSpaces() async {
        let mock = MockSpacesClient()
        let ai = SpaceDTO.stub(name: "AI", slug: "ai", category: "ai")
        let work = SpaceDTO.stub(name: "Work", slug: "work", category: "work")
        mock.listResult = .success([ai, work])
        let sut = SpacesViewModel(spacesClient: mock)

        await sut.load()

        XCTAssertEqual(sut.spaces.count, 2)
        XCTAssertEqual(sut.categories, [allCategoriesSlug, "ai", "work"])
    }

    func testCategoryFilterRestrictsVisibleSpaces() async {
        let mock = MockSpacesClient()
        let ai = SpaceDTO.stub(name: "AI", slug: "ai", category: "ai")
        let work = SpaceDTO.stub(name: "Work", slug: "work", category: "work")
        mock.listResult = .success([ai, work])
        let sut = SpacesViewModel(spacesClient: mock)
        await sut.load()

        sut.selectedCategory = "ai"
        XCTAssertEqual(sut.visibleSpaces.map(\.slug), ["ai"])

        sut.selectedCategory = allCategoriesSlug
        XCTAssertEqual(Set(sut.visibleSpaces.map(\.slug)), ["ai", "work"])
    }

    func testSearchQueryFiltersByName() async {
        let mock = MockSpacesClient()
        mock.listResult = .success([
            SpaceDTO.stub(name: "AI", slug: "ai"),
            SpaceDTO.stub(name: "Reading", slug: "reading", category: "ideas"),
        ])
        let sut = SpacesViewModel(spacesClient: mock)
        await sut.load()

        sut.searchQuery = "read"
        XCTAssertEqual(sut.visibleSpaces.map(\.slug), ["reading"])
    }

    func testCreateOptimisticallyAppendsAndSortsByName() async {
        let mock = MockSpacesClient()
        mock.listResult = .success([SpaceDTO.stub(name: "Work", slug: "work")])
        let sut = SpacesViewModel(spacesClient: mock)
        await sut.load()

        await sut.create(CreateSpaceRequest(name: "AI", slug: "ai-extra", description: nil, color: nil, icon: nil, category: "ai"))

        XCTAssertEqual(sut.spaces.map(\.name), ["AI", "Work"])
        XCTAssertNil(sut.error)
    }

    func testFailedCreateReturnsTheServerMessageAndKeepsTheList() async {
        let mock = MockSpacesClient()
        mock.listResult = .success([SpaceDTO.stub(name: "Health", slug: "health")])
        let body = Data(#"{"error":{"message":"slug already used in this vault"}}"#.utf8)
        mock.createResult = .failure(APIError.httpError(statusCode: 409, data: body))
        let sut = SpacesViewModel(spacesClient: mock)
        await sut.load()

        let message = await sut.create(CreateSpaceRequest(
            name: "Health", slug: "", description: nil, color: nil, icon: nil, category: nil
        ))

        XCTAssertEqual(message, "slug already used in this vault", "the form shows the server's reason")
        XCTAssertEqual(sut.spaces.map(\.slug), ["health"], "nothing was added")
        XCTAssertNil(sut.error, "the form reports this, not the list banner")
    }

    func testSuccessfulCreateReturnsNil() async {
        let sut = SpacesViewModel(spacesClient: MockSpacesClient())

        let message = await sut.create(CreateSpaceRequest(
            name: "Health", slug: "", description: nil, color: nil, icon: "heart.fill", category: nil
        ))

        XCTAssertNil(message)
        XCTAssertEqual(sut.spaces.map(\.name), ["Health"])
    }

    func testFailedUpdateReturnsAMessageAndLeavesTheSpaceAlone() async {
        let mock = MockSpacesClient()
        let space = SpaceDTO.stub(name: "AI", slug: "ai")
        mock.listResult = .success([space])
        mock.updateResult = .failure(APIError.httpError(statusCode: 500, data: Data()))
        let sut = SpacesViewModel(spacesClient: mock)
        await sut.load()

        let message = await sut.update(id: space.id, UpdateSpaceRequest(name: "Renamed"))

        XCTAssertNotNil(message)
        XCTAssertEqual(sut.spaces.map(\.name), ["AI"])
        XCTAssertNil(sut.error)
    }

    func testDeleteRollsBackOnError() async {
        let mock = MockSpacesClient()
        let space = SpaceDTO.stub(name: "AI", slug: "ai")
        mock.listResult = .success([space])
        mock.deleteError = APIError.httpError(statusCode: 500, data: Data())
        let sut = SpacesViewModel(spacesClient: mock)
        await sut.load()

        await sut.delete(id: space.id)

        XCTAssertEqual(sut.spaces.map(\.id), [space.id], "optimistic removal should roll back on error")
        XCTAssertNotNil(sut.error)
    }
}
