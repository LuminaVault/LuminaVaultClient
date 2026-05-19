import Foundation
import SwiftData

/// HER-39 — single SwiftData `ModelContainer` shared across the app. The
/// container lives on `AppState` for the lifetime of the process; tests
/// build an in-memory container via `makeInMemory()` so unit tests don't
/// touch the simulator's Documents directory.
enum SwiftDataStack {
    /// Production container. Persists to the default SQLite file under
    /// `Documents/default.store`. Fails loudly at launch if the container
    /// cannot be constructed — there is no graceful degradation for a
    /// missing local store; the app needs it to function offline.
    @MainActor
    static func makePersistent() -> ModelContainer {
        do {
            return try ModelContainer(
                for: LocalVaultFile.self, SyncOperation.self, SyncLogEntry.self
            )
        } catch {
            fatalError("HER-39: failed to construct SwiftData ModelContainer: \(error)")
        }
    }

    /// In-memory container for tests. Same schema; nothing hits disk.
    @MainActor
    static func makeInMemory() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(
            for: LocalVaultFile.self, SyncOperation.self, SyncLogEntry.self,
            configurations: config
        )
    }
}
