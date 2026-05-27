// LuminaVaultShareExtension/ShareExtensionCaptureClient.swift

import Foundation

struct ShareExtensionCaptureClient: Sendable {
    enum CaptureError: Error {
        case missingToken
        case invalidURL
        case badStatus(Int, Data)
    }

    private let session: URLSession
    private let baseURL: URL
    private let tokenProvider: @Sendable () -> String?

    init(
        session: URLSession = .shared,
        baseURL: URL = ShareExtensionConfig.apiBaseURL,
        tokenProvider: @escaping @Sendable () -> String? = {
            SharedSessionKeychain(accessGroup: ShareExtensionConfig.keychainAccessGroup).accessToken
        }
    ) {
        self.session = session
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
    }

    func capture(_ payload: SharePayload, note: String?, spaceID: UUID?) async throws {
        switch payload {
        case .url(let id, let url):
            try await captureURL(id: id, url: url, note: note, spaceID: spaceID)
        case .text(let id, let text):
            try await captureText(id: id, text: text, note: note, spaceID: spaceID)
        case .image(let id, let data, let contentType, let fileExtension):
            try await captureImage(
                id: id,
                data: data,
                contentType: contentType,
                fileExtension: fileExtension,
                note: note,
                spaceID: spaceID,
            )
        }
    }

    private func captureURL(id: UUID, url: String, note: String?, spaceID: UUID?) async throws {
        struct Body: Encodable {
            let url: String
            let notes: String?
            let spaceId: UUID?
        }
        try await executeJSON(
            path: "/v1/capture/safari",
            idempotencyKey: id,
            body: Body(url: url, notes: note, spaceId: spaceID),
        )
    }

    private func captureText(id: UUID, text: String, note: String?, spaceID: UUID?) async throws {
        let rendered = Self.renderSharedText(body: text, note: note)
        try await upload(
            id: id,
            path: "raw/captures/\(id.uuidString).md",
            data: Data(rendered.utf8),
            contentType: "text/markdown",
            spaceID: spaceID,
        )
        try await upsertMemory(id: id, content: text)
    }

    private func captureImage(
        id: UUID,
        data: Data,
        contentType: String,
        fileExtension: String,
        note: String?,
        spaceID: UUID?
    ) async throws {
        try await upload(
            id: id,
            path: "raw/captures/\(id.uuidString).\(fileExtension)",
            data: data,
            contentType: contentType,
            spaceID: spaceID,
        )
        try await upsertMemory(id: id, content: note?.nilIfEmpty ?? "Image capture")
    }

    private func upsertMemory(id: UUID, content: String) async throws {
        struct Body: Encodable {
            let content: String
        }
        try await executeJSON(
            path: "/v1/memory/upsert",
            idempotencyKey: id,
            body: Body(content: content),
        )
    }

    private func executeJSON<Body: Encodable>(
        path: String,
        idempotencyKey: UUID,
        body: Body
    ) async throws {
        var request = try makeRequest(path: path, idempotencyKey: idempotencyKey)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)
        _ = try await execute(request)
    }

    private func upload(
        id: UUID,
        path: String,
        data: Data,
        contentType: String,
        spaceID: UUID?
    ) async throws {
        var components = URLComponents()
        components.path = "/v1/vault/files"
        var queryItems = [URLQueryItem(name: "path", value: path)]
        if let spaceID {
            queryItems.append(URLQueryItem(name: "space_id", value: spaceID.uuidString))
        }
        components.queryItems = queryItems

        var request = try makeRequest(path: components.string ?? "/v1/vault/files", idempotencyKey: id)
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = data
        _ = try await execute(request)
    }

    private func makeRequest(path: String, idempotencyKey: UUID) throws -> URLRequest {
        guard let token = tokenProvider()?.nilIfEmpty else { throw CaptureError.missingToken }
        guard let url = URL(string: path, relativeTo: baseURL) else { throw CaptureError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(idempotencyKey.uuidString, forHTTPHeaderField: "Idempotency-Key")
        return request
    }

    private func execute(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return data }
        guard (200..<300).contains(http.statusCode) else {
            throw CaptureError.badStatus(http.statusCode, data)
        }
        return data
    }

    private static func renderSharedText(body: String, note: String?) -> String {
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedNote = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedNote, !trimmedNote.isEmpty else { return trimmedBody + "\n" }
        return "\(trimmedNote)\n\n---\n\n\(trimmedBody)\n"
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
