// LuminaVaultClient/LuminaVaultClient/API/Cron/HermesCronClient.swift

import Foundation

protocol HermesCronClientProtocol {
    func list() async throws -> HermesCronListDTO
    func preview(text: String) async throws -> CronSpecDTO
    func create(spec: CronSpecDTO) async throws -> HermesCronListDTO
}

struct HermesCronHTTPClient: HermesCronClientProtocol {
    let client: BaseHTTPClient

    func list() async throws -> HermesCronListDTO {
        try await client.execute(HermesCronEndpoints.List())
    }

    func preview(text: String) async throws -> CronSpecDTO {
        try await client.execute(HermesCronEndpoints.Preview(text: text))
    }

    func create(spec: CronSpecDTO) async throws -> HermesCronListDTO {
        try await client.execute(HermesCronEndpoints.Create(spec: spec))
    }
}
