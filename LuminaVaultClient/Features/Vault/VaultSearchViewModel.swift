// LuminaVaultClient/LuminaVaultClient/Features/Vault/VaultSearchViewModel.swift
// HER-105: drives the universal top search bar on the Spaces tab.
// Combines two parallel calls: `/v1/query` (synthesised answer + hits
// across memories + vault) and `/v1/vault/files?q=` (filename trigram).
// Both run concurrently; results stream into the view as each call
// returns.
import Foundation
import SwiftUI
import PostHog

@Observable
@MainActor
final class VaultSearchViewModel {
    private let memoryClient: MemoryQueryClientProtocol
    private let vaultClient: VaultClientProtocol

    var query: String = ""
    var memoryHits: [QueryHitDTO] = []
    var memorySummary: String?
    var fileHits: [VaultFileDTO] = []
    var isLoading = false
    var error: String?

    private var inflightTask: Task<Void, Never>?

    init(memoryClient: MemoryQueryClientProtocol, vaultClient: VaultClientProtocol) {
        self.memoryClient = memoryClient
        self.vaultClient = vaultClient
    }

    func run() async {
        inflightTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            memoryHits = []
            memorySummary = nil
            fileHits = []
            return
        }
        isLoading = true
        error = nil
        defer { isLoading = false }

        let task = Task { @MainActor in
            async let memoryResult = try? memoryClient.query(text: trimmed, limit: 20)
            async let fileResult = try? vaultClient.listFiles(
                spaceSlug: nil, q: trimmed, before: nil, after: nil, limit: 30,
            )
            let memory = await memoryResult
            let files = await fileResult
            guard !Task.isCancelled else { return }
            self.memoryHits = memory?.hits ?? []
            self.memorySummary = memory?.summary
            self.fileHits = files?.files ?? []
            // PostHog: capture search with result counts
            PostHogSDK.shared.capture("vault_search_performed", properties: [
                "memory_hits": (memory?.hits ?? []).count,
                "file_hits": (files?.files ?? []).count,
            ])
        }
        inflightTask = task
        await task.value
    }

    func clear() {
        query = ""
        memoryHits = []
        memorySummary = nil
        fileHits = []
        error = nil
        inflightTask?.cancel()
    }
}
