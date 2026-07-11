import Foundation
import LuminaVaultShared

@Observable
@MainActor
final class MarketplacePluginDetailViewModel {
    enum State: Equatable {
        case idle
        case working
        case installed
        case error(String)
    }

    let plugin: MarketplacePluginDTO
    var install: PluginInstallDTO?
    var selectedPermissions: Set<PluginPermission> = []
    var values: [String: String]
    var reviews: [MarketplaceReviewDTO] = []
    var state: State = .idle

    private let client: any PluginsClientProtocol
    private let onChange: () async -> Void

    init(plugin: MarketplacePluginDTO, install: PluginInstallDTO?, client: any PluginsClientProtocol, onChange: @escaping () async -> Void) {
        self.plugin = plugin
        self.install = install
        self.client = client
        self.onChange = onChange
        values = Dictionary(uniqueKeysWithValues: plugin.configFields.map { ($0.key, "") })
        selectedPermissions = Set(install?.grantedPermissions ?? [])
    }

    var hasAllPermissions: Bool {
        Set(plugin.latestVersion.permissions) == selectedPermissions
    }

    func toggle(_ permission: PluginPermission) {
        if selectedPermissions.contains(permission) {
            selectedPermissions.remove(permission)
        } else {
            selectedPermissions.insert(permission)
        }
    }

    func loadReviews() async {
        reviews = (try? await client.marketplaceReviews(slug: plugin.slug).items) ?? []
    }

    func installPlugin() async {
        guard hasAllPermissions else {
            state = .error("Review and approve every requested permission.")
            return
        }
        for field in plugin.configFields where field.isRequired {
            guard let value = values[field.key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
                state = .error("Missing \(field.label).")
                return
            }
        }
        state = .working
        do {
            install = try await client.installMarketplace(
                slug: plugin.slug,
                request: MarketplaceInstallRequest(
                    versionId: plugin.latestVersion.id,
                    grantedPermissions: plugin.latestVersion.permissions.filter(selectedPermissions.contains),
                    config: values
                )
            )
            state = .installed
            await onChange()
        } catch {
            state = .error((error as? APIError)?.errorDescription ?? error.localizedDescription)
        }
    }
}
