import Foundation
@testable import LuminaVaultClient
import LuminaVaultShared
import Testing

@MainActor
@Suite("Marketplace plugin details")
struct MarketplacePluginDetailViewModelTests {
    @Test("Uninstall clears the installation and permission grants")
    func uninstallClearsState() async {
        let client = MarketplacePluginsClientStub()
        let install = Self.install()
        let model = MarketplacePluginDetailViewModel(
            plugin: Self.plugin(), install: install, client: client, onChange: {}
        )

        await model.uninstallPlugin()

        #expect(model.install == nil)
        #expect(model.selectedPermissions.isEmpty)
        #expect(await client.uninstalledIDs == [install.id])
    }

    @Test("A verified install can submit and prepend a rating")
    func ratingIsSubmitted() async {
        let client = MarketplacePluginsClientStub()
        let model = MarketplacePluginDetailViewModel(
            plugin: Self.plugin(), install: Self.install(), client: client, onChange: {}
        )
        model.rating = 4
        model.reviewBody = "Useful and focused."

        await model.submitRating()

        #expect(model.reviews.first?.rating == 4)
        #expect(model.reviewBody.isEmpty)
        #expect(await client.lastRating?.rating == 4)
    }

    private static func plugin() -> MarketplacePluginDTO {
        MarketplacePluginDTO(
            slug: "safe-tool", name: "Safe Tool", summary: "A test tool", description: "Test",
            category: .skill,
            publisher: MarketplacePublisherDTO(
                id: UUID(), handle: "publisher", displayName: "Publisher", verified: true
            ),
            latestVersion: MarketplaceVersionDTO(
                id: UUID(), version: "1.0.0", status: .approved, runtimeKind: .wasm,
                permissions: [.memoryRead], tools: [.init(name: "run", description: "Run")]
            )
        )
    }

    private static func install() -> PluginInstallDTO {
        PluginInstallDTO(
            id: UUID(), pluginSlug: "safe-tool", status: .enabled, hasConfig: false,
            grantedPermissions: [.memoryRead]
        )
    }
}

private actor MarketplacePluginsClientStub: PluginsClientProtocol {
    var uninstalledIDs: [UUID] = []
    var lastRating: MarketplaceRatingRequest?

    func catalog(category _: PluginCategory?) async throws -> PluginCatalogListResponse {
        .init(items: [])
    }

    func featuredPlugins() async throws -> PluginCatalogListResponse {
        .init(items: [])
    }

    func premiumPlugins() async throws -> PluginCatalogListResponse {
        .init(items: [])
    }

    func hermesSkills() async throws -> PluginCatalogListResponse {
        .init(items: [])
    }

    func installHermesSkill(id _: String) async throws -> PluginCatalogListResponse {
        .init(items: [])
    }

    func uninstallHermesSkill(name _: String) async throws -> PluginCatalogListResponse {
        .init(items: [])
    }

    func installs() async throws -> PluginInstallsListResponse {
        .init(items: [])
    }

    func install(_: InstallPluginRequest) async throws -> PluginInstallDTO {
        throw TestError.unexpected
    }

    func update(_: UUID, _: UpdatePluginInstallRequest) async throws -> PluginInstallDTO {
        throw TestError.unexpected
    }

    func uninstall(_ id: UUID) async throws {
        uninstalledIDs.append(id)
    }

    func sync(_: UUID) async throws -> PluginSyncResponse {
        throw TestError.unexpected
    }

    func marketplace(query _: String?, category _: PluginCategory?) async throws -> MarketplaceListResponse {
        .init(items: [])
    }

    func marketplaceDetail(slug _: String) async throws -> MarketplacePluginDTO {
        throw TestError.unexpected
    }

    func marketplaceReviews(slug _: String) async throws -> MarketplaceReviewsResponse {
        .init(items: [])
    }

    func installMarketplace(slug _: String, request _: MarketplaceInstallRequest) async throws -> PluginInstallDTO {
        throw TestError.unexpected
    }

    func rateMarketplace(slug _: String, request: MarketplaceRatingRequest) async throws -> MarketplaceReviewDTO {
        lastRating = request
        return MarketplaceReviewDTO(
            id: UUID(), rating: request.rating, body: request.body,
            authorUsername: "tester", verifiedInstall: true
        )
    }
}

private enum TestError: Error {
    case unexpected
}
