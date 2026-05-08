// HermesVaultClient/HermesVaultClient/API/Core/APIError.swift
import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case encodingFailed(Error)
    case networkFailure(Error)
    case httpError(statusCode: Int, data: Data)
    case decodingFailed(Error)
    case unauthorized

    var errorDescription: String? {
        switch self {
        case .invalidURL:              return "Invalid server URL."
        case .encodingFailed:          return "Failed to encode request."
        case .networkFailure(let e):   return e.localizedDescription
        case .httpError(let code, _):  return "Server error (\(code))."
        case .decodingFailed:          return "Unexpected server response."
        case .unauthorized:            return "Session expired. Please sign in again."
        }
    }
}
