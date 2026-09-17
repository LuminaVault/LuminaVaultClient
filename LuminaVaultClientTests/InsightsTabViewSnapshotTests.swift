// LuminaVaultClient/LuminaVaultClientTests/InsightsTabViewSnapshotTests.swift
//
// The Insights tab's chrome and sections: one "Insights" title, the
// Overview/Reflect segments pinned under it, the range menu in the bar next
// to capture, and the overview itself as an inset-grouped list. The
// populated case carries every section the dashboard can show — memory
// health, usage, a recommendation, trends, models — because the bug being
// fixed was how those looked, not whether they appeared.
//
// Baselines were recorded on CI's iPhone 16 Pro / iOS 26.4 renderer via the
// `record-snapshots` workflow (`.github/workflows/ci.yml`, workflow_dispatch)
// on 2026-09-17. Re-record the same way after an intentional render change;
// a one-off re-record goes through the per-assert `record:` parameter.

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient
@testable import LuminaVaultShared

@MainActor
final class InsightsTabViewSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    // MARK: - Fixtures

    private static let vaultID = UUID(uuidString: "3D2E1F00-0000-4000-8000-00000000000C")!

    /// Fixed instants, not offsets from now: the trend charts label their x
    /// axis by month and day, so a moving window moves the render.
    private static func day(_ index: Int) -> Date {
        Date(timeIntervalSince1970: 1_756_684_800 + Double(index) * 86_400)
    }

    // Explicitly typed sub-expressions: the fully-inferred one-expression
    // form times out the Swift 6.2 type-checker ("unable to type-check in
    // reasonable time"), the same way `TrendChartCard`'s preview did.
    private static let summary = AnalyticsSummaryDTO(
        sessions: 46,
        aiRequests: 312,
        tokensIn: 486_200,
        tokensOut: 128_940,
        captures: 74,
        retrievals: 208,
        estimatedCostUsdMicros: 4_182_000
    )

    private static let daily: [AnalyticsDailyPointDTO] = (0 ..< 14).map(point(at:))

    private static func point(at index: Int) -> AnalyticsDailyPointDTO {
        let sessions: Int = 2 + index % 4
        let requests: Int = 14 + index * 2
        let tokens: Int = 28_000 + index * 3_400
        let captures: Int = 3 + index % 5
        let retrievals: Int = 9 + index % 7
        let cost = Int64(180_000 + index * 9_000)
        return AnalyticsDailyPointDTO(
            date: day(index),
            sessions: sessions,
            aiRequests: requests,
            tokens: tokens,
            captures: captures,
            retrievals: retrievals,
            estimatedCostUsdMicros: cost
        )
    }

    private static let healthComponents: [MemoryHealthComponentDTO] = [
        MemoryHealthComponentDTO(key: "freshness", title: "Freshness", score: 82, weight: 35),
        MemoryHealthComponentDTO(key: "engagement", title: "Engagement", score: 64, weight: 25),
        MemoryHealthComponentDTO(key: "organization", title: "Organization", score: 58, weight: 20),
        MemoryHealthComponentDTO(key: "review", title: "Review readiness", score: 71, weight: 20),
    ]

    private static let memoryHealth = MemoryHealthDTO(
        score: 70,
        totalMemories: 418,
        staleCount: 62,
        neverRetrievedCount: 39,
        unorganizedCount: 24,
        pendingReviewCount: 11,
        components: healthComponents
    )

    private static let recommendations: [AnalyticsRecommendationDTO] = [
        AnalyticsRecommendationDTO(
            id: "memory-review-overdue",
            title: "Review older memories",
            detail: "Eleven memories are past their review date and are dragging the score down.",
            severity: .important,
            actionTitle: "Open review queue",
            deepLink: "/memories?reviewState=pending"
        ),
    ]

    private static let overview = AnalyticsOverviewResponse(
        scope: .personal,
        vaultId: vaultID,
        range: .month,
        periodStart: day(0),
        periodEnd: day(13),
        summary: summary,
        daily: daily,
        memoryHealth: memoryHealth,
        recommendations: recommendations
    )

    private static let models: [ModelEffectivenessDTO] = [
        ModelEffectivenessDTO(
            provider: "anthropic",
            model: "claude-opus-5",
            requests: 184,
            successRate: 0.98,
            fallbackRate: 0.01,
            averageLatencyMs: 1_420,
            p95LatencyMs: 2_610,
            tokens: 402_180,
            estimatedCostUsdMicros: 3_104_000
        ),
        ModelEffectivenessDTO(
            provider: "openai",
            model: "gpt-test-mini",
            requests: 128,
            successRate: 0.91,
            fallbackRate: 0.06,
            averageLatencyMs: 780,
            p95LatencyMs: 1_340,
            tokens: 212_960,
            estimatedCostUsdMicros: 1_078_000
        ),
    ]

    /// Offsets from *now*, unlike the chart fixtures: the reflections feed
    /// prints a relative age, so a pinned instant reads "1 yr ago" and drifts
    /// to "2 yr ago" the moment the calendar turns over. The offsets stay
    /// inside the same calendar day for the same reason.
    private static func reflection(_ name: String, hoursAgo: Int) -> VaultFileDTO {
        VaultFileDTO(
            id: UUID(uuidString: "0C0C0C0C-000\(hoursAgo)-4000-8000-00000000000C")!,
            path: "reflections/\(name).md",
            contentType: "text/markdown",
            sizeBytes: 3_072,
            sha256: "deadbeef",
            spaceId: vaultID,
            createdAt: Date().addingTimeInterval(-Double(hoursAgo) * 3_600)
        )
    }

    // MARK: - Assembly

    private func makeAnalyticsViewModel() async -> AnalyticsDashboardViewModel {
        let vm = AnalyticsDashboardViewModel(
            analytics: StubUsageIntelligenceClient(overview: Self.overview, models: Self.models),
            insights: MockInsightsClient()
        )
        await vm.load()
        return vm
    }

    private func makeReflectViewModel() async -> ReflectViewModel {
        let vaultClient = MockVaultClient()
        vaultClient.listFilesResult = .success(
            VaultFileListResponse(
                files: [
                    Self.reflection("patterns-sleep-and-focus", hoursAgo: 1),
                    Self.reflection("contradictions-on-shipping", hoursAgo: 2),
                ],
                limit: 10,
                nextBefore: nil
            )
        )
        let vm = ReflectViewModel(vaultClient: vaultClient)
        await vm.refreshRecent()
        return vm
    }

    /// `captureToolbarItem()` is applied here because `MainTabView` applies it
    /// inside the same stack — the snapshot has to show both trailing items.
    private func makeView(
        section: InsightsTabView.Section,
        analytics: AnalyticsDashboardViewModel,
        reflect: ReflectViewModel
    ) -> some View {
        NavigationStack {
            InsightsTabView(
                section: section,
                analyticsViewModel: analytics,
                reflectViewModel: reflect,
                runner: ReflectionRunner(
                    skillsClient: InertSkillsClient(),
                    vaultUploadClient: InertUploadClient()
                ),
                httpClient: BaseHTTPClient(session: .shared),
                vaultClient: MockVaultClient(),
                memoryClient: InertReflectMemoryClient()
            )
            .captureToolbarItem()
        }
    }

    private func snap(_ view: some View, _ name: String, dark: Bool) {
        assertSnapshot(
            of: view
                .environment(\.lvAmbientMotionEnabled, false)
                .environment(AppState())
                .environment(\.locale, Locale(identifier: "en_US"))
                // The app resolves the palette per colour scheme through
                // `LVThemeManager`; without one the environment default is the
                // dark palette, which renders light-mode text nearly white.
                .environment(\.lvPalette, LVTheme.cyanGold.palette(for: dark ? .dark : .light))
                .preferredColorScheme(dark ? .dark : .light),
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: dark ? .dark : .light)
            ),
            // `testName` rather than `named`, so the baseline is called what
            // the case is called instead of carrying this helper's signature
            // and a misleading "dark" into every file name.
            testName: name
        )
    }

    /// The device-height render stops inside Usage, so the sections below it
    /// — Recommended, Trends, Models, Patterns — get a taller canvas instead
    /// of a scroll gesture the renderer cannot perform.
    private func snapFullLength(_ view: some View, _ name: String) {
        assertSnapshot(
            of: view
                .environment(\.lvAmbientMotionEnabled, false)
                .environment(AppState())
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.lvPalette, LVTheme.cyanGold.palette(for: .light))
                .preferredColorScheme(.light),
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .fixed(width: 390, height: 2_600),
                traits: .init(userInterfaceStyle: .light)
            ),
            // `testName` rather than `named`, so the baseline is called what
            // the case is called instead of carrying this helper's signature
            // and a misleading "dark" into every file name.
            testName: name
        )
    }

    // MARK: - Cases

    func testOverviewLoaded() async {
        let analytics = await makeAnalyticsViewModel()
        let reflect = await makeReflectViewModel()
        let view = makeView(section: .overview, analytics: analytics, reflect: reflect)
        snap(view, "insights-overview-light", dark: false)
        snap(view, "insights-overview-dark", dark: true)
    }

    func testOverviewSectionsBelowTheFold() async {
        let analytics = await makeAnalyticsViewModel()
        let reflect = await makeReflectViewModel()
        let view = makeView(section: .overview, analytics: analytics, reflect: reflect)
        snapFullLength(view, "insights-overview-full-light")
    }

    func testReflectSegment() async {
        let analytics = await makeAnalyticsViewModel()
        let reflect = await makeReflectViewModel()
        let view = makeView(section: .reflect, analytics: analytics, reflect: reflect)
        snap(view, "insights-reflect-light", dark: false)
        snap(view, "insights-reflect-dark", dark: true)
    }
}

// MARK: - Stubs

/// Serves the fixture straight back. An actor because the protocol is
/// `Sendable` and the view model calls it from `async let`.
private actor StubUsageIntelligenceClient: UsageIntelligenceClientProtocol {
    private let overviewValue: AnalyticsOverviewResponse
    private let modelValues: [ModelEffectivenessDTO]

    init(overview: AnalyticsOverviewResponse, models: [ModelEffectivenessDTO]) {
        overviewValue = overview
        modelValues = models
    }

    func overview(range _: AnalyticsRange) async throws -> AnalyticsOverviewResponse { overviewValue }

    func models(range: AnalyticsRange) async throws -> ModelEffectivenessResponse {
        ModelEffectivenessResponse(range: range, models: modelValues)
    }

    func record(_: AnalyticsEventRequest) async throws {}
    func recordModelFeedback(_: ModelFeedbackRequest) async throws {}
    func updateRecommendation(_: AnalyticsRecommendationStateRequest) async throws {}
}

/// No snapshot here runs a reflection skill or saves one.
private struct InertSkillsClient: SkillsClientProtocol {
    func list() async throws -> SkillListResponse { SkillListResponse(skills: []) }

    func patch(name _: String, body _: SkillPatchRequest) async throws -> SkillDTO {
        throw APIError.unauthorized
    }

    func runs(name _: String, limit _: Int?) async throws -> SkillRunsResponse {
        SkillRunsResponse(runs: [], sparkline: [], nextCursor: nil)
    }

    func run(name _: String, request _: SkillRunRequest) async throws -> SkillRunResponse {
        throw APIError.unauthorized
    }
}

private struct InertUploadClient: VaultUploadClientProtocol {
    func uploadAsset(
        data _: Data,
        contentType _: String,
        relativePath _: String,
        spaceID _: UUID?
    ) async throws -> VaultUploadResponse {
        throw APIError.unauthorized
    }
}

/// Reading is the vault's job and no snapshot here opens the reader.
private struct InertReflectMemoryClient: MemoryClientProtocol {
    func upsert(_: MemoryUpsertRequest) async throws -> MemoryUpsertResponse {
        throw APIError.unauthorized
    }

    func get(id _: UUID) async throws -> MemoryDTO {
        throw APIError.unauthorized
    }

    func patch(id _: UUID, _: MemoryPatchRequest) async throws -> MemoryDTO {
        throw APIError.unauthorized
    }

    func list(limit _: Int, offset _: Int) async throws -> MemoryListResponse {
        throw APIError.unauthorized
    }

    func search(_: MemorySearchRequest) async throws -> MemorySearchResponse {
        throw APIError.unauthorized
    }

    func delete(id _: UUID) async throws {
        throw APIError.unauthorized
    }
}
