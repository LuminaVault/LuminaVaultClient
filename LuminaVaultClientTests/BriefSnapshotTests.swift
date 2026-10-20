// LuminaVaultClient/LuminaVaultClientTests/BriefSnapshotTests.swift
//
// The daily brief: the sheet with its cards (Open loops showing Done / Drop,
// a 👍 already chosen, the end note), the sheet on a day without a brief,
// Home's "Your brief" row, and the full Open loops list — light and dark.
//
// Baselines are recorded on CI's iPhone 16 Pro / iOS 26.4 renderer by the
// `record-snapshots` workflow (`.github/workflows/ci.yml`), never locally.

import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient
@testable import LuminaVaultShared

@MainActor
final class BriefSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    private func loadedBrief(_ brief: BriefDTO?) async -> BriefViewModel {
        let vm = BriefViewModel(
            client: MockBriefClient(brief),
            commitmentsClient: MockCommitmentsClient(),
            now: { CommitmentDTO.fixtureNow },
            locale: Locale(identifier: "en_US")
        )
        await vm.load()
        return vm
    }

    private func snap(_ view: some View, _ name: String, dark: Bool, layout: SwiftUISnapshotLayout) {
        assertSnapshot(
            of: view
                .environment(\.lvAmbientMotionEnabled, false)
                .environment(AppState())
                .environment(\.locale, Locale(identifier: "en_US"))
                .environment(\.timeZone, .gmt)
                .environment(\.lvPalette, LVTheme.cyanGold.palette(for: dark ? .dark : .light))
                .preferredColorScheme(dark ? .dark : .light),
            as: .image(
                precision: 0.98,
                perceptualPrecision: 0.96,
                layout: layout,
                traits: .init(userInterfaceStyle: dark ? .dark : .light)
            ),
            testName: name
        )
    }

    func testBriefWithCards() async throws {
        let vm = await loadedBrief(.fixture())
        // One reaction already in, so the chosen state is in the picture.
        if let weather = vm.cards.first(where: { $0.id == "weather" }) {
            await vm.react(.up, to: weather)
        }
        let view = BriefView(viewModel: vm, memoryClient: MockMemoryClient(), now: { CommitmentDTO.fixtureNow })
        snap(view, "brief-cards-light", dark: false, layout: .device(config: .iPhone13Pro))
        snap(view, "brief-cards-dark", dark: true, layout: .device(config: .iPhone13Pro))
    }

    func testBriefEmpty() async throws {
        let vm = await loadedBrief(nil)
        let view = BriefView(viewModel: vm, memoryClient: MockMemoryClient(), now: { CommitmentDTO.fixtureNow })
        snap(view, "brief-empty-light", dark: false, layout: .device(config: .iPhone13Pro))
        snap(view, "brief-empty-dark", dark: true, layout: .device(config: .iPhone13Pro))
    }

    func testHomeRow() async throws {
        let view = List {
            Section("Today") {
                BriefHomeRow(count: 4, onOpen: {})
            }
        }
        .frame(width: 390, height: 160)
        snap(view, "brief-home-row-light", dark: false, layout: .sizeThatFits)
        snap(view, "brief-home-row-dark", dark: true, layout: .sizeThatFits)
    }

    func testCommitmentsListOpen() async throws {
        let vm = CommitmentsListViewModel(client: MockCommitmentsClient())
        await vm.load()
        let view = NavigationStack {
            CommitmentsListView(viewModel: vm, now: { CommitmentDTO.fixtureNow })
        }
        snap(view, "commitments-open-light", dark: false, layout: .device(config: .iPhone13Pro))
        snap(view, "commitments-open-dark", dark: true, layout: .device(config: .iPhone13Pro))
    }

    func testCommitmentsListDone() async throws {
        let client = MockCommitmentsClient()
        client.results[.done] = .success(CommitmentsResponse(items: [
            .fixture(text: "Book the dentist", state: .done, doneAt: Date(timeIntervalSince1970: 1_792_324_800)),
            .fixture(text: "Send the invoice to Rui", state: .done, doneAt: Date(timeIntervalSince1970: 1_792_065_600)),
        ]))
        let vm = CommitmentsListViewModel(client: client, segment: .done)
        await vm.load()
        let view = NavigationStack {
            CommitmentsListView(viewModel: vm, now: { CommitmentDTO.fixtureNow })
        }
        snap(view, "commitments-done-light", dark: false, layout: .device(config: .iPhone13Pro))
        snap(view, "commitments-done-dark", dark: true, layout: .device(config: .iPhone13Pro))
    }
}
