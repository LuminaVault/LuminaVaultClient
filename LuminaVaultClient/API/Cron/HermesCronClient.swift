// LuminaVaultClient/LuminaVaultClient/API/Cron/HermesCronClient.swift

import Foundation

protocol HermesCronClientProtocol {
    func list() async throws -> HermesCronListDTO
}

struct HermesCronHTTPClient: HermesCronClientProtocol {
    let client: BaseHTTPClient

    func list() async throws -> HermesCronListDTO {
        try await client.execute(HermesCronEndpoints.List())
    }
}
