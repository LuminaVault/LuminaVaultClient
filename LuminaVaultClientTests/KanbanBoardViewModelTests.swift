// LuminaVaultClient/LuminaVaultClientTests/KanbanBoardViewModelTests.swift
//
// Unit tests for KanbanBoardViewModel. All tests use MockKanbanClient
// so no server or database is required.

import XCTest
@testable import LuminaVaultClient
import LuminaVaultShared

@MainActor
final class KanbanBoardViewModelTests: XCTestCase {

    var mockClient: MockKanbanClient!
    var boardID: UUID!
    var sut: KanbanBoardViewModel!

    override func setUp() async throws {
        try await super.setUp()
        mockClient = MockKanbanClient()
        boardID = UUID()
        sut = KanbanBoardViewModel(boardID: boardID, client: mockClient)
    }

    override func tearDown() async throws {
        sut.stopPolling()
        try await super.tearDown()
    }

    // MARK: - Test 1: load() populates board

    func testLoadPopulatesBoard() async {
        // Arrange: board with one "Todo" column
        let columnID = UUID()
        let column = ColumnDTO.stub(id: columnID, title: "Todo")
        let board = BoardDTO.stub(id: boardID, title: "My Board", columns: [column])
        mockClient.boardResult = .success(board)

        // Act
        await sut.load()

        // Assert
        XCTAssertNotNil(sut.board)
        XCTAssertEqual(sut.board?.columns.first?.title, "Todo")
        XCTAssertFalse(sut.isLoading)
        XCTAssertNil(sut.lastError)
        XCTAssertEqual(mockClient.calls, [.board(boardID)])
    }

    // MARK: - Test 2: moveCard optimistically updates then reconciles

    func testMoveCardOptimisticallyUpdatesThenReconciles() async {
        // Arrange: board with a card in c1 and an empty c2
        let c1 = UUID()
        let c2 = UUID()
        let cardID = UUID()

        let card = CardDTO.stub(id: cardID, columnID: c1, title: "Move Me", rank: "a")
        let col1 = ColumnDTO.stub(id: c1, title: "Todo", rank: "a", cards: [card])
        let col2 = ColumnDTO.stub(id: c2, title: "Done", rank: "b", cards: [])
        let board = BoardDTO.stub(id: boardID, columns: [col1, col2])

        mockClient.boardResult = .success(board)
        await sut.load()

        // Server returns the card with updated columnID
        let movedCard = CardDTO.stub(id: cardID, columnID: c2, title: "Move Me", rank: "a")
        mockClient.moveCardResult = .success(movedCard)

        // Act
        await sut.moveCard(cardID, toColumn: c2, before: nil, after: nil)

        // Assert: card is in c2, gone from c1
        guard let updatedBoard = try? XCTUnwrap(sut.board) else {
            XCTFail("Expected board after moveCard")
            return
        }
        let c2Cards = updatedBoard.columns.first(where: { $0.id == c2 })?.cards ?? []
        let c1Cards = updatedBoard.columns.first(where: { $0.id == c1 })?.cards ?? []

        XCTAssertTrue(c2Cards.contains(where: { $0.id == cardID }), "Card should be in c2 after move")
        XCTAssertFalse(c1Cards.contains(where: { $0.id == cardID }), "Card should not remain in c1 after move")
        XCTAssertNil(sut.lastError)
    }

    // MARK: - Test 3: addCard optimistically appends

    func testAddCardOptimisticallyAppends() async {
        // Arrange: board with one empty column
        let columnID = UUID()
        let col = ColumnDTO.stub(id: columnID, title: "Backlog", rank: "a", cards: [])
        let board = BoardDTO.stub(id: boardID, columns: [col])

        mockClient.boardResult = .success(board)
        await sut.load()

        // Server returns a newly-created card
        let newCard = CardDTO.stub(id: UUID(), columnID: columnID, title: "New Task", rank: "a")
        mockClient.createCardResult = .success(newCard)

        // Act
        await sut.addCard(columnID: columnID, title: "New Task")

        // Assert: the column now contains the card
        guard let updatedBoard = try? XCTUnwrap(sut.board) else {
            XCTFail("Expected board after addCard")
            return
        }
        let cards = updatedBoard.columns.first(where: { $0.id == columnID })?.cards ?? []

        XCTAssertTrue(cards.contains(where: { $0.id == newCard.id }), "Column should contain newly added card")
        XCTAssertNil(sut.lastError)
    }
}
