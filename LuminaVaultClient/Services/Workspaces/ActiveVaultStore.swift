import Foundation

actor ActiveVaultStore {
    private var vaultID: UUID?

    func selectedVaultID() -> UUID? {
        vaultID
    }

    func select(_ id: UUID?, for userID: UUID?) {
        vaultID = id
        let key = persistenceKey(userID)
        if let id {
            UserDefaults.standard.set(id.uuidString, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func restore(for userID: UUID?) {
        guard let raw = UserDefaults.standard.string(forKey: persistenceKey(userID)) else {
            vaultID = nil
            return
        }
        vaultID = UUID(uuidString: raw)
    }

    private func persistenceKey(_ userID: UUID?) -> String {
        "lv.active-vault.\(userID?.uuidString ?? "anonymous")"
    }
}
