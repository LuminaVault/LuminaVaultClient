// LuminaVaultClient/LuminaVaultClient/Services/AppGroup/SharedAppGroup.swift
//
// HER-258 — shared on-disk container that both the main app and the
// Share Extension can read/write. The extension cannot read the main
// app's keychain or sandboxed Documents folder; the App Group is the
// only sanctioned cross-target shared store.
//
// Layout (under the App Group container root):
//   pendingShares.json       — array of `PendingShare` queued by the extension
//   pendingShareAssets/      — sidecar files for queued image attachments
//   spacesCache.json         — snapshot of the user's Spaces, written by the
//                              main app so the extension's picker is populated
//
// The directory itself is provisioned by iOS the first time either
// target reads the App Group container URL.

import Foundation
import OSLog

private nonisolated(unsafe) let log = Logger(subsystem: "com.luminavault", category: "shared-app-group")

enum SharedAppGroup {
    /// Identifier of the App Group entitlement. Both `LuminaVaultClient`
    /// and `LuminaVaultShareExtension` must list this in their
    /// entitlements file (`com.apple.security.application-groups`).
    static let identifier = "group.com.lumina.fernando"

    enum FileName {
        static let pendingShares = "pendingShares.json"
        static let spacesCache = "spacesCache.json"
    }

    enum DirectoryName {
        static let pendingShareAssets = "pendingShareAssets"
    }

    enum AccessError: Error {
        case containerUnavailable
    }

    /// Root URL of the shared container. `nil` when the App Group
    /// entitlement is missing or not provisioned on the device — callers
    /// must treat this as a soft failure (extension simply won't queue).
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static func fileURL(named name: String) -> URL? {
        containerURL?.appendingPathComponent(name)
    }

    static func directoryURL(named name: String) -> URL? {
        containerURL?.appendingPathComponent(name, isDirectory: true)
    }

    /// Read a `Codable` payload from the App Group container. Returns
    /// `nil` for: missing file, missing container, decode failure (the
    /// extension can't recover from a corrupted file, so we log + drop).
    static func read<T: Decodable>(_ type: T.Type, from file: String) -> T? {
        guard let url = fileURL(named: file) else { return nil }
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            log.error("AppGroup read decode failed for \(file): \(error.localizedDescription)")
            return nil
        }
    }

    /// Atomic write to the App Group container. Uses `.atomic` so a
    /// crash mid-write never leaves a half-written JSON for the other
    /// target to read.
    static func write<T: Encodable>(_ value: T, to file: String) throws {
        guard let url = fileURL(named: file) else { throw AccessError.containerUnavailable }
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    /// Delete a file from the App Group container. No-op when the file
    /// doesn't exist; surfaces any other FileManager failure to the
    /// caller (the launch drain logs + carries on).
    static func delete(file: String) throws {
        guard let url = fileURL(named: file) else { throw AccessError.containerUnavailable }
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        try fm.removeItem(at: url)
    }

    // ISO-8601 dates on the wire so the cache survives clock-format
    // drift between extension and host process.
    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted]
        return e
    }()
}
