// LuminaVaultClient/LuminaVaultClient/API/Vault/VaultUploadHTTPClient.swift
//
// HER-34 — `POST /v1/vault/files` with raw bytes body. The path of the
// uploaded file is carried in the `?path=` query param; the bytes are
// in the request body; the `Content-Type` header tells the server which
// allowlist entry to validate against.

import Foundation
import LuminaVaultShared

final class VaultUploadHTTPClient: VaultUploadClientProtocol {
    private let client: BaseHTTPClient

    init(client: BaseHTTPClient) { self.client = client }

    func uploadAsset(
        data: Data,
        contentType: String,
        relativePath: String,
        spaceID: UUID?
    ) async throws -> VaultUploadResponse {
        try await uploadAsset(data: data, contentType: contentType, relativePath: relativePath, spaceID: spaceID, processed: false)
    }

    func uploadAsset(
        data: Data,
        contentType: String,
        relativePath: String,
        spaceID: UUID?,
        processed: Bool
    ) async throws -> VaultUploadResponse {
        var comps = URLComponents()
        comps.path = "/v1/vault/files"
        var items: [URLQueryItem] = [URLQueryItem(name: "path", value: relativePath)]
        if let spaceID {
            items.append(URLQueryItem(name: "space_id", value: spaceID.uuidString))
        }
        if processed {
            items.append(URLQueryItem(name: "processed", value: "true"))
        }
        comps.queryItems = items
        let uri = comps.string ?? "/v1/vault/files"

        let raw = try await client.uploadBytes(
            path: uri,
            method: .post,
            body: data,
            contentType: contentType,
        )
        return try JSONDecoder.hvDefault.decode(VaultUploadResponse.self, from: raw)
    }
}
