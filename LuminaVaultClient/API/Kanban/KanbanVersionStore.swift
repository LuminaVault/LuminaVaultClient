import Foundation
import LuminaVaultShared

actor KanbanVersionStore {
    private var versions: [UUID: Int64] = [:]
    private var cardBoards: [UUID: UUID] = [:]

    func record(_ board: BoardDTO) {
        versions[board.id] = board.version
        for column in board.columns {
            for card in column.cards {
                cardBoards[card.id] = board.id
            }
        }
    }

    func record(boardID: UUID, version: Int64) {
        versions[boardID] = version
    }

    func version(boardID: UUID) -> Int64? {
        versions[boardID]
    }

    func boardID(cardID: UUID) -> UUID? {
        cardBoards[cardID]
    }
}
