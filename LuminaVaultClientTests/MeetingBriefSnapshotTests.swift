// LuminaVaultClient/LuminaVaultClientTests/MeetingBriefSnapshotTests.swift
//
// The pre-meeting brief: the sheet with its notes (time, place, people, the
// why line), the sheet for a meeting nothing has been saved about, and the
// Settings › Notifications row — off, and on with calendar sync off — light
// and dark.
//
// Baselines are recorded on CI's iPhone 16 Pro / iOS 26.4 renderer by the
// `record-snapshots` workflow (`.github/workflows/ci.yml`), never locally.

import LuminaVaultShared
import SnapshotTesting
import SwiftUI
import UIKit
import XCTest

@testable import LuminaVaultClient

@MainActor
final class MeetingBriefSnapshotTests: XCTestCase {
    override func setUp() {
        super.setUp()
        UIView.setAnimationsEnabled(false)
    }

    override func tearDown() {
        UIView.setAnimationsEnabled(true)
        super.tearDown()
    }

    private func loadedBrief(_ response: MeetingBriefResponse) async -> MeetingBriefViewModel {
        let vm = MeetingBriefViewModel(
            eventID: MeetingBriefResponse.eventID,
            client: MockMeetingBriefClient(response),
            locale: Locale(identifier: "en_US"),
            timeZone: .gmt
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

    func testMeetingBriefWithNotes() async throws {
        let vm = await loadedBrief(.fixture())
        let view = MeetingBriefSheet(viewModel: vm, memoryClient: MockMemoryClient())
        snap(view, "meeting-brief-notes-light", dark: false, layout: .device(config: .iPhone13Pro))
        snap(view, "meeting-brief-notes-dark", dark: true, layout: .device(config: .iPhone13Pro))
    }

    func testMeetingBriefEmpty() async throws {
        let vm = await loadedBrief(.fixture(memories: []))
        let view = MeetingBriefSheet(viewModel: vm, memoryClient: MockMemoryClient())
        snap(view, "meeting-brief-empty-light", dark: false, layout: .device(config: .iPhone13Pro))
        snap(view, "meeting-brief-empty-dark", dark: true, layout: .device(config: .iPhone13Pro))
    }

    private func settingsRow(isOn: Bool, readiness: CalendarSyncReadiness) -> some View {
        let dataAccess = {
            DataAccessView(vm: DataAccessViewModel(client: StubAppleConsentClient()))
        }
        return NavigationStack {
            MeetingBriefSettingsRow(isOn: .constant(isOn), readiness: readiness, dataAccess: dataAccess)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .lvBackground()
        }
        .frame(width: 390, height: 240)
    }

    func testSettingsRowOff() async throws {
        let view = settingsRow(isOn: false, readiness: .ready)
        snap(view, "meeting-brief-setting-off-light", dark: false, layout: .sizeThatFits)
        snap(view, "meeting-brief-setting-off-dark", dark: true, layout: .sizeThatFits)
    }

    func testSettingsRowNeedsCalendar() async throws {
        let view = settingsRow(isOn: true, readiness: .consentOff)
        snap(view, "meeting-brief-setting-needs-calendar-light", dark: false, layout: .sizeThatFits)
        snap(view, "meeting-brief-setting-needs-calendar-dark", dark: true, layout: .sizeThatFits)
    }
}
