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
    var useAppleOnDeviceModel: Bool
    var localFallbackEnabled: Bool
    var cloudFallbackEnabled: Bool
    var syncLocalConversations: Bool
    var connectionStatus: String?
    var isTestingConnection = false

    init(defaults: UserDefaults = .standard, keychain: KeychainService = .shared) {
        profile = HybridExecutionProfile(rawValue: defaults.string(forKey: "hybrid.profile") ?? "") ?? .balanced
        endpointKind = LocalEndpointKind(rawValue: defaults.string(forKey: "hybrid.endpointKind") ?? "") ?? .ollama
        endpointURL = defaults.string(forKey: "hybrid.endpointURL") ?? "http://127.0.0.1:11434"
        model = defaults.string(forKey: "hybrid.model") ?? "qwen3:0.6b"
        apiKey = keychain.localEndpointAPIKey ?? ""
        useAppleOnDeviceModel = defaults.bool(forKey: "hybrid.useAppleOnDeviceModel")
        localFallbackEnabled = defaults.object(forKey: "hybrid.localFallbackEnabled") as? Bool ?? true
        cloudFallbackEnabled = defaults.object(forKey: "hybrid.cloudFallbackEnabled") as? Bool ?? true
        syncLocalConversations = defaults.object(forKey: "hybrid.syncLocalConversations") as? Bool ?? true
    }

    var configuration: LocalEndpointConfiguration? {
        guard let url = URL(string: endpointURL), url.user == nil, url.password == nil,
              ["http", "https"].contains(url.scheme?.lowercased()) else { return nil }
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return nil }
        return LocalEndpointConfiguration(kind: endpointKind, baseURL: url, model: model, apiKey: apiKey.isEmpty ? nil : apiKey)
    }

    func save(defaults: UserDefaults = .standard, keychain: KeychainService = .shared) {
        defaults.set(profile.rawValue, forKey: "hybrid.profile")
        defaults.set(endpointKind.rawValue, forKey: "hybrid.endpointKind")
        defaults.set(endpointURL, forKey: "hybrid.endpointURL")
        defaults.set(model, forKey: "hybrid.model")
        keychain.localEndpointAPIKey = apiKey.isEmpty ? nil : apiKey
        defaults.set(useAppleOnDeviceModel, forKey: "hybrid.useAppleOnDeviceModel")
        defaults.set(localFallbackEnabled, forKey: "hybrid.localFallbackEnabled")
        defaults.set(cloudFallbackEnabled, forKey: "hybrid.cloudFallbackEnabled")
        defaults.set(syncLocalConversations, forKey: "hybrid.syncLocalConversations")
    }

    func loadCrossDevicePreferences(using client: any ChatExperienceClientProtocol) async {
        guard let preferences = try? await client.getHybridPreferences() else { return }
        profile = preferences.profile
        localFallbackEnabled = preferences.localFallbackEnabled
        cloudFallbackEnabled = preferences.cloudFallbackEnabled
        syncLocalConversations = preferences.syncLocalConversations
    }

    func saveCrossDevicePreferences(using client: any ChatExperienceClientProtocol) async {
        let preferences = HybridRoutingPreferencesDTO(
            profile: profile,
            localFallbackEnabled: localFallbackEnabled,
            cloudFallbackEnabled: cloudFallbackEnabled,
            syncLocalConversations: syncLocalConversations
        )
        _ = try? await client.putHybridPreferences(preferences)
    }

    func testConnection() async {
        isTestingConnection = true
        defer { isTestingConnection = false }
        let executor: (any LocalChatExecuting)?
        if useAppleOnDeviceModel {
            executor = makeAppleOnDeviceChatExecutor()
        } else {
            executor = configuration.map { LocalEndpointChatExecutor(configuration: $0) }
        }
        guard let executor else {
            connectionStatus = useAppleOnDeviceModel
                ? "Apple Intelligence is not currently available on this device."
                : "Enter a valid local endpoint URL and model."
            return
        }
        connectionStatus = await executor.isAvailable()
            ? "Connected to \(executor.displayName) (\(executor.modelID))."
            : "Could not reach the local model. Check the address, model server, and local-network permission."
    }
}
