// LuminaVaultClient/LuminaVaultClient/Services/KeychainService.swift
import Foundation
import Security

final class KeychainService: Sendable {
    static let shared = KeychainService()

    private let service: String

    init(service: String = "com.luminavault.client") {
        self.service = service
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

    func clearAll() {
        ["accessToken", "refreshToken", "biometricsEnabled"].forEach { write(key: $0, value: nil) }
    }

    private func write(key: String, value: String?) {
        let account = "\(service).\(key)"
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        SecItemDelete(query as CFDictionary)
        guard let value else { return }
        query[kSecValueData] = Data(value.utf8)
        query[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(query as CFDictionary, nil)
    }

    private func read(key: String) -> String? {
        let account = "\(service).\(key)"
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
