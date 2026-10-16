// LuminaVaultClient/LuminaVaultClient/API/Resurface/ResurfaceClientProtocol.swift

import Foundation
import LuminaVaultShared

protocol ResurfaceClientProtocol: Sendable {
    /// GET /v1/me/resurface?limit= — what is worth seeing again today, best
    /// first, each with a one-line reason. Acting on an item is a memory
    /// review: `MemoryClientProtocol.review(id:action:)`.
    func resurface(limit: Int) async throws -> ResurfaceResponse
}
