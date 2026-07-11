import Foundation
import LuminaVaultShared

actor LocalMemorySyncService {
    private let client: any MemoryClientProtocol
    private let cache: EncryptedLocalMemoryCache
    private let defaults: UserDefaults
    private let cursorKey = "hybrid.localMemoryCursor"

    init(client: any MemoryClientProtocol, cache: EncryptedLocalMemoryCache, defaults: UserDefaults = .standard) {
        self.client = client
        self.cache = cache
        self.defaults = defaults
    }

    func synchronize() async {
        do {
            let response = try await client.localSync(cursor: defaults.string(forKey: cursorKey), limit: 500)
            try await cache.merge(response)
            if let cursor = response.nextCursor {
                defaults.set(cursor, forKey: cursorKey)
            }
        } catch {
            // The encrypted cache remains available when the server is offline.
        }
    }

    func context(for query: String, limit: Int = 5) async -> [LocalMemorySyncItemDTO] {
        (try? await cache.search(query, limit: limit)) ?? []
    }
}
