import Foundation
import LuminaVaultShared
import Observation

@Observable
@MainActor
final class HybridExecutionSettingsStore {
    var profile: HybridExecutionProfile
    var endpointKind: LocalEndpointKind
    var endpointURL: String
    var model: String
    var apiKey: String

    init(defaults: UserDefaults = .standard, keychain: KeychainService = .shared) {
        profile = HybridExecutionProfile(rawValue: defaults.string(forKey: "hybrid.profile") ?? "") ?? .quality
        endpointKind = LocalEndpointKind(rawValue: defaults.string(forKey: "hybrid.endpointKind") ?? "") ?? .ollama
        endpointURL = defaults.string(forKey: "hybrid.endpointURL") ?? "http://127.0.0.1:11434"
        model = defaults.string(forKey: "hybrid.model") ?? "qwen3:0.6b"
        apiKey = keychain.localEndpointAPIKey ?? ""
    }

    var configuration: LocalEndpointConfiguration? {
        guard let url = URL(string: endpointURL), url.user == nil, url.password == nil,
              ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        return LocalEndpointConfiguration(kind: endpointKind, baseURL: url, model: model, apiKey: apiKey.isEmpty ? nil : apiKey)
    }

    func save(defaults: UserDefaults = .standard, keychain: KeychainService = .shared) {
        defaults.set(profile.rawValue, forKey: "hybrid.profile")
        defaults.set(endpointKind.rawValue, forKey: "hybrid.endpointKind")
        defaults.set(endpointURL, forKey: "hybrid.endpointURL")
        defaults.set(model, forKey: "hybrid.model")
        keychain.localEndpointAPIKey = apiKey.isEmpty ? nil : apiKey
    }
}
