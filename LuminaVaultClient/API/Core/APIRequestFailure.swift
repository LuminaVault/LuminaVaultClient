// LuminaVaultClient/LuminaVaultClient/API/Core/APIRequestFailure.swift
//
// One failed request, as handed to `BaseHTTPClient.onRequestFailure`.
//
// Before this existed a failing call left one `.debug` log line (method,
// path, status) and nothing else: the server's message and the coding path
// of a decode failure were read once to build a banner string and dropped.
// The `pinnedMemoryIDs` 400 shipped to TestFlight with no trace anywhere
// off-device. This is the single seam the app wires to Sentry/PostHog.
//
// `detail` never carries a request body, an auth header, or user content —
// only the server's `error.message` or a coding path.
import Foundation

struct APIRequestFailure: Equatable, Sendable {
    enum Kind: String, Sendable {
        /// Non-2xx status. `detail` is the server's `error.message` when the
        /// body carried the standard envelope, otherwise empty.
        case httpStatus = "http_status"
        /// 2xx whose body did not decode. `detail` names the coding path.
        case decoding
    }

    static let detailLimit = 200

    let kind: Kind
    let method: String
    let path: String
    let statusCode: Int?
    let detail: String

    init(kind: Kind, method: String, path: String, statusCode: Int?, detail: String) {
        self.kind = kind
        self.method = method
        self.path = path
        self.statusCode = statusCode
        self.detail = String(detail.prefix(Self.detailLimit))
    }

    static func httpStatus(method: String, path: String, statusCode: Int, data: Data) -> APIRequestFailure {
        APIRequestFailure(
            kind: .httpStatus,
            method: method,
            path: path,
            statusCode: statusCode,
            detail: StructuredAPIError.parse(from: data)?.message ?? ""
        )
    }

    static func decoding(method: String, path: String, statusCode: Int?, error: any Error) -> APIRequestFailure {
        APIRequestFailure(
            kind: .decoding,
            method: method,
            path: path,
            statusCode: statusCode,
            detail: (error as? DecodingError)?.lvSummary ?? String(describing: error)
        )
    }
}

extension DecodingError {
    /// Short, log-safe description of where decoding gave up:
    /// "missing `pinnedMemoryIDs`", "type mismatch at `events[0].recordedAt`".
    var lvSummary: String {
        switch self {
        case .keyNotFound(let key, let context):
            return "missing `\(Self.render(context.codingPath + [key]))`"
        case .valueNotFound(_, let context):
            return "null at `\(Self.render(context.codingPath))`"
        case .typeMismatch(_, let context):
            return "type mismatch at `\(Self.render(context.codingPath))`"
        case .dataCorrupted(let context):
            let path = Self.render(context.codingPath)
            return path.isEmpty ? "corrupted data" : "corrupted data at `\(path)`"
        @unknown default:
            return "undecodable response"
        }
    }

    private static func render(_ keys: [any CodingKey]) -> String {
        var out = ""
        for key in keys {
            if let index = key.intValue {
                out += "[\(index)]"
            } else {
                out += out.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
        return out
    }
}
