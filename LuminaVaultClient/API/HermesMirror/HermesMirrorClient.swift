// LuminaVaultClient/LuminaVaultClient/API/HermesMirror/HermesMirrorClient.swift
//
// Mirror status + sync over `BaseHTTPClient`.

import Foundation
import LuminaVaultShared

protocol HermesMirrorClientProtocol: Sendable {
    func status() async throws -> HermesMirrorStatusDTO
    func sync(scope: [HermesMirrorSyncScope]?) async throws -> HermesMirrorStatusDTO
}

final class HermesMirrorHTTPClient: HermesMirrorClientProtocol {
    private let client: BaseHTTPClient
    init(client: BaseHTTPClient) { self.client = client }

    func status() async throws -> HermesMirrorStatusDTO {
        try await client.execute(HermesMirrorEndpoints.Status())
    }

    func sync(scope: [HermesMirrorSyncScope]? = nil) async throws -> HermesMirrorStatusDTO {
        try await client.execute(HermesMirrorEndpoints.Sync(scope: scope))
    }
}
