// LuminaVaultClient/LuminaVaultClient/Features/Vault/NoteVersion.swift
// Backlog E5.4: conflict-safe note saves. The reader remembers the sha256 of
// the bytes it loaded and sends it as `If-Match`; the server answers 412 when
// another device saved in between, instead of silently overwriting it.
import CryptoKit
import Foundation

enum NoteVersion {
    /// Lowercase hex sha256, the form the server stores and compares.
    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// The `If-Match` value for a loaded version (a quoted entity tag).
    static func ifMatch(_ sha: String?) -> String? {
        sha.map { "\"\($0)\"" }
    }

    /// True for the server's "the note changed since you opened it" answer.
    static func isConflict(_ error: Error) -> Bool {
        if case let APIError.httpError(statusCode, _) = error { return statusCode == 412 }
        return false
    }
}
