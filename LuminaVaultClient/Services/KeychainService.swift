// LuminaVaultClient/LuminaVaultClient/Services/KeychainService.swift
import Foundation
import Security

final class KeychainService: Sendable {
    static let shared = KeychainService()

    private let service: String
    private let accessGroup: String?
    private let inMemoryStore: InMemoryKeychainStore?

    init(
        service: String = "com.luminavault.client",
        accessGroup: String? = nil,
        inMemory: Bool = false
    ) {
        self.service = service
        self.accessGroup = accessGroup?.isEmpty == false ? accessGroup : nil
        self.inMemoryStore = inMemory ? InMemoryKeychainStore() : nil
    }

    var accessToken: String? {
        get { read(key: "accessToken") }
        set { write(key: "accessToken", value: newValue) }
    }
    var refreshToken: String? {
        get { read(key: "refreshToken") }
        set { write(key: "refreshToken", value: newValue) }
    }
    var biometricsEnabled: Bool {
        get { read(key: "biometricsEnabled") == "1" }
        set { write(key: "biometricsEnabled", value: newValue ? "1" : nil) }
    }

    // HER-330: server admin token (`admin.token`) for the owner-only
    // /v1/system/hermes update routes, sent as the `X-Admin-Token` header.
    // Stored here (not @AppStorage) because it is a shared secret.
    var hermesAdminToken: String? {
        get { read(key: "hermesAdminToken") }
        set { write(key: "hermesAdminToken", value: newValue) }
    }

    // HER-209: persist Apple's `user` identifier so we can poll
    // `ASAuthorizationAppleIDProvider.getCredentialState(forUserID:)` on
    // launch/foreground and sign out on `.revoked`.
    var appleUserId: String? {
        get { read(key: "appleUserId") }
        set { write(key: "appleUserId", value: newValue) }
    }

    // Apple returns `fullName` only on the FIRST sign-up. Stash the JSON-
    // encoded `PersonNameComponents` so subsequent sign-ins don't drop the
    // user's display name.
    var appleFullName: PersonNameComponents? {
        get {
            guard let raw = read(key: "appleFullName"),
                  let data = raw.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(PersonNameComponents.self, from: data) else {
                return nil
            }
            return decoded
        }
        set {
            guard let newValue,
                  let data = try? JSONEncoder().encode(newValue),
                  let string = String(data: data, encoding: .utf8) else {
                write(key: "appleFullName", value: nil)
                return
            }
            write(key: "appleFullName", value: string)
        }
    }

    func clearAll() {
        [
            "accessToken",
            "refreshToken",
            "biometricsEnabled",
            "appleUserId",
            "appleFullName",
        ].forEach { write(key: $0, value: nil) }
    }

    private func write(key: String, value: String?) {
        if let inMemoryStore {
            inMemoryStore.write(key: key, value: value)
            return
        }

        let account = "\(service).\(key)"
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        SecItemDelete(query as CFDictionary)
        guard let value else { return }
        query[kSecValueData] = Data(value.utf8)
        query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private func read(key: String) -> String? {
        if let inMemoryStore {
            return inMemoryStore.read(key: key)
        }

        let account = "\(service).\(key)"
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        if let accessGroup {
            query[kSecAttrAccessGroup] = accessGroup
        }
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// Test-only backing store for simulator environments where unsigned unit-test
// bundles cannot write to Security.framework keychain items.
private final class InMemoryKeychainStore: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: String] = [:]

    func write(key: String, value: String?) {
        lock.lock()
        defer { lock.unlock() }
        values[key] = value
    }

    func read(key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return values[key]
    }
}
