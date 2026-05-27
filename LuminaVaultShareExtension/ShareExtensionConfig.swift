// LuminaVaultShareExtension/ShareExtensionConfig.swift

import Foundation

enum ShareExtensionConfig {
    static var apiBaseURL: URL {
        URL(string: infoString("API_BASE_URL") ?? "https://api.luminavault.com")!
    }

    static var keychainAccessGroup: String? {
        infoString("KEYCHAIN_ACCESS_GROUP")
    }

    private static func infoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String,
              !value.isEmpty,
              !value.hasPrefix("$("),
              !value.hasPrefix("REPLACE_WITH_") else { return nil }
        return value
    }
}
