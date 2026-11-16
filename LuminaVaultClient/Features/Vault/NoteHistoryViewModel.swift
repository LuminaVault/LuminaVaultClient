// LuminaVaultClient/LuminaVaultClient/Features/Vault/NoteHistoryViewModel.swift
// Backlog E4.5: drives `NoteHistoryView`. Lists a note's saved versions, loads
// one to read, and restores it. A restore sends `If-Match` of the version the
// reader shows, so it never replaces an edit made on another device since;
// the server keeps the restore as a new version, so nothing is lost.
import Foundation

@Observable
@MainActor
final class NoteHistoryViewModel {
    private let vaultClient: VaultClientProtocol
    let path: String
    /// sha256 of the bytes the reader shows; nil when it couldn't read them.
    private let currentSHA: String?

    private(set) var versions: [VaultHistoryVersion] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    var error: String?

    private(set) var versionText: String?
    private(set) var versionIsBinary = false
    private(set) var isLoadingVersion = false
    private(set) var isRestoring = false
    /// Set when the note changed elsewhere since the reader loaded it.
    var showConflict = false

    init(vaultClient: VaultClientProtocol, path: String, currentSHA: String?) {
        self.vaultClient = vaultClient
        self.path = path
        self.currentSHA = currentSHA
    }

    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            versions = try await vaultClient.history(path: path)
            error = nil
        } catch {
            self.error = Self.message(for: error, fallback: "Couldn't load the history.")
        }
    }

    func loadVersion(_ version: VaultHistoryVersion) async {
        versionText = nil
        versionIsBinary = false
        guard !version.deleted else { return }
        isLoadingVersion = true
        defer { isLoadingVersion = false }
        do {
            let (data, contentType) = try await vaultClient.readVersion(sha: version.sha, path: path)
            let isText = contentType.hasPrefix("text/") || contentType.contains("markdown")
                || contentType == "application/json"
            if isText, let text = String(data: data, encoding: .utf8) {
                versionText = text
            } else {
                versionIsBinary = true
            }
            error = nil
        } catch {
            self.error = Self.message(for: error, fallback: "Couldn't load this version.")
        }
    }

    /// Returns the restored file, or nil when it failed or conflicted.
    func restore(_ version: VaultHistoryVersion) async -> VaultFileDTO? {
        guard !version.deleted, !isRestoring else { return nil }
        isRestoring = true
        defer { isRestoring = false }
        do {
            let file = try await vaultClient.restoreVersion(
                sha: version.sha, path: path, ifMatch: NoteVersion.ifMatch(currentSHA)
            )
            error = nil
            return file
        } catch where NoteVersion.isConflict(error) {
            showConflict = true
        } catch {
            self.error = Self.message(for: error, fallback: "Couldn't restore this version.")
        }
        return nil
    }

    private static func message(for error: Error, fallback: String) -> String {
        if let api = error as? APIError, let description = api.errorDescription {
            return description
        }
        if error is URLError {
            return error.localizedDescription
        }
        return fallback
    }
}
