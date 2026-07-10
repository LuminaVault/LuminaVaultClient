import Foundation
import LuminaVaultShared

struct ParallelChatOutput: Identifiable, Equatable {
    let id: UUID
    let participantID: UUID?
    let role: String
    let route: RouterModelRouteDTO?
    let stage: ParallelOutputStageDTO
    let round: Int
    var content: String
    var status: ParallelExecutionStatusDTO
}

struct ParallelChatExecution: Identifiable, Equatable {
    let id: UUID
    let strategy: ParallelStrategyDTO
    var status: ParallelExecutionStatusDTO
    var outputs: [ParallelChatOutput] = []

    var perspectives: [ParallelChatOutput] {
        outputs.filter { $0.stage != .synthesis }
    }
}
