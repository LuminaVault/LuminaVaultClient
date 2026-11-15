// LuminaVaultClient/LuminaVaultClient/Features/Vault/VaultTrashViewModel.swift
// Backlog E3.4: drives `VaultTrashView`. A delete on any client moves the file
// to the trash for 30 days; this lists those files and restores or removes
// them. Failures surface as a clear message; nothing is queued offline.
import Foundation

@Observable
@MainActor
final class VaultTrashViewModel {
    private let vaultClient: VaultClientProtocol

    private(set) var items: [VaultTrashItem] = []
    private(set) var isLoading = false
    private(set) var hasLoaded = false
    /// Ids with a request in flight, so a double tap sends one.
    private(set) var busy: Set<UUID> = []
    var error: String?
    /// Shown once after a restore or delete, e.g. "Restored as inbox/a-restored.md".
    var notice: String?

    init(vaultClient: VaultClientProtocol) {
        self.vaultClient = vaultClient
    }

    func load() async {
        isLoading = true
        defer {
            isLoading = false
            hasLoaded = true
        }
        do {
            items = try await vaultClient.listTrash()
            error = nil
        } catch {
            self.error = Self.message(for: error, fallback: "Couldn't load the trash.")
        }
    }

    func restore(_ item: VaultTrashItem) async {
        guard busy.insert(item.id).inserted else { return }
        defer { busy.remove(item.id) }
        do {
            let file = try await vaultClient.restoreTrash(id: item.id)
            items.removeAll { $0.id == item.id }
            notice = file.path == item.path ? "Restored \(file.path)" : "Restored as \(file.path)"
        } catch let APIError.httpError(statusCode, _) where statusCode == 410 {
            items.removeAll { $0.id == item.id }
            error = "This file is no longer available."
        } catch {
            self.error = Self.message(for: error, fallback: "Couldn't restore the file.")
        }
    }

    func deleteForever(_ item: VaultTrashItem) async {
        guard busy.insert(item.id).inserted else { return }
        defer { busy.remove(item.id) }
        do {
            try await vaultClient.deleteTrashForever(id: item.id)
            items.removeAll { $0.id == item.id }
            notice = "Deleted \(item.path) for good"
        } catch {
            self.error = Self.message(for: error, fallback: "Couldn't delete the file.")
        }
    }

    private static func message(for error: Error, fallback: String) -> String {
        if let api = error as? APIError, let description = api.errorDescription { return description }
        if error is URLError { return error.localizedDescription }
        return fallback
    }
}
