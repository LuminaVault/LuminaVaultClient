// LuminaVaultShareExtension/SharePayload.swift

import Foundation

enum SharePayload: Equatable, Identifiable, Sendable {
    case url(id: UUID, value: String)
    case text(id: UUID, value: String)
    case image(id: UUID, data: Data, contentType: String, fileExtension: String)

    var id: UUID {
        switch self {
        case .url(let id, _), .text(let id, _), .image(let id, _, _, _):
            return id
        }
    }

    var title: String {
        switch self {
        case .url: return "Link"
        case .text: return "Text"
        case .image: return "Image"
        }
    }

    var subtitle: String {
        switch self {
        case .url(_, let value):
            return value
        case .text(_, let value):
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.count > 96 ? String(trimmed.prefix(96)) + "..." : trimmed
        case .image(_, let data, let contentType, _):
            return "\(contentType) • \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))"
        }
    }

    static func makeURL(_ value: String, id: UUID = UUID()) -> SharePayload {
        .url(id: id, value: value)
    }

    static func makeText(_ value: String, id: UUID = UUID()) -> SharePayload {
        .text(id: id, value: value)
    }

    static func makeImage(
        data: Data,
        contentType: String,
        fileExtension: String,
        id: UUID = UUID()
    ) -> SharePayload {
        .image(id: id, data: data, contentType: contentType, fileExtension: fileExtension)
    }
}
