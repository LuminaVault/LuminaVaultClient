// LuminaVaultClient/LuminaVaultClientTests/InsightsListViewSnapshotTests.swift
//
// HER-263 — image snapshots for the OS Shell Insights list. Populated
// dark + light + empty dark variants.

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient
@testable import LuminaVaultShared

@MainActor
final class InsightsListViewSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)
        isRecording = false
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    private final class StubInsightsClient: InsightsClientProtocol, @unchecked Sendable {
        let result: Result<InsightListResponse, Error>
        init(result: Result<InsightListResponse, Error>) { self.result = result }
        func list(section: InsightSection?, limit: Int?) async throws -> InsightListResponse {
            try result.get()
        }
    }

    private static func stubInsight(
        headline: String,
        summary: String,
        section: InsightSection,
        daysAgo: Int
    ) -> InsightDTO {
        InsightDTO(
            id: UUID(),
            headline: headline,
            summary: summary,
            section: section,
            createdAt: Date(timeIntervalSinceNow: TimeInterval(-daysAgo * 86_400))
        )
    }

    private func makeView(populated: Bool) -> some View {
        let canned: [InsightDTO] = populated ? [
            Self.stubInsight(
                headline: "You write more on Tuesdays",
                summary: "Average 4.2 captures vs 1.7 across the rest of the week.",
                section: .patterns,
                daysAgo: 0
            ),
            Self.stubInsight(
                headline: "Three notes link to deep work",
                summary: "Cluster forming around focus + flow state notes.",
                section: .connections,
                daysAgo: 1
            ),
            Self.stubInsight(
                headline: "Note conflicts with last week's stance",
                summary: "You wrote about caffeine helping focus; this week you flipped to caffeine hurting sleep.",
                section: .contradictions,
                daysAgo: 2
            ),
        ] : []
        let client = StubInsightsClient(result: .success(InsightListResponse(insights: canned)))
        let vm = InsightsListViewModel(client: client)
        vm.insights = canned
        vm.state = .loaded
        return NavigationStack {
            InsightsListView(vm: vm)
        }
        .transaction { $0.disablesAnimations = true }
    }

    func testInsightsPopulatedDarkMode() {
        let view = makeView(populated: true).preferredColorScheme(.dark)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: .dark)
            ),
            named: "iPhone16Pro-populated-dark"
        )
    }

    func testInsightsPopulatedLightMode() {
        let view = makeView(populated: true).preferredColorScheme(.light)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: .light)
            ),
            named: "iPhone16Pro-populated-light"
        )
    }

    func testInsightsEmptyDarkMode() {
        let view = makeView(populated: false).preferredColorScheme(.dark)
        assertSnapshot(
            of: view,
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: .device(config: .iPhone13Pro),
                traits: .init(userInterfaceStyle: .dark)
            ),
            named: "iPhone16Pro-empty-dark"
        )
    }
}
