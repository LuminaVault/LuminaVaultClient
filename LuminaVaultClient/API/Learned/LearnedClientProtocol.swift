// LuminaVaultClient/LuminaVaultClient/API/Learned/LearnedClientProtocol.swift

import Foundation
import LuminaVaultShared

protocol LearnedClientProtocol: Sendable {
    /// GET /v1/me/learned?since= — unconfirmed SOUL changes and new
    /// preference / decision memories. `since` nil is the server's default
    /// window, the last seven days. Answering an item is not this client's
    /// job: memories go through `MemoryClientProtocol.patch(id:_:)` and SOUL
    /// changes through `SelfImprovementClientProtocol.decide(changeID:approve:)`.
    func learned(since: Date?) async throws -> LearnedDigestResponse
}
