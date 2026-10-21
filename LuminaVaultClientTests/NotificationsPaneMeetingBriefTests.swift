// LuminaVaultClient/LuminaVaultClientTests/NotificationsPaneMeetingBriefTests.swift
//
// Settings › Notifications › Meeting briefs: off unless the server says it
// is on (an older server says nothing); the switch writes only
// `meetingBriefEnabled`, rolls back when the server says no; and the pane
// knows when calendar sync is off, which the brief needs.

import EventKit
import Foundation
import LuminaVaultShared
import XCTest

@testable import LuminaVaultClient

@MainActor
final class NotificationsPaneMeetingBriefTests: XCTestCase {
    private struct Boom: Error {}

    func testOffByDefaultWhenTheServerDoesNotSay() async {
        let vm = NotificationsPaneViewModel(client: MockAPNSPrefsClient(meetingBriefEnabled: nil))
        XCTAssertFalse(vm.meetingBriefEnabled)
        await vm.load()
        XCTAssertFalse(vm.meetingBriefEnabled)
        XCTAssertEqual(vm.state, .loaded)
    }

    func testReadsTheServersChoice() async {
        let vm = NotificationsPaneViewModel(client: MockAPNSPrefsClient(meetingBriefEnabled: true))
        await vm.load()
        XCTAssertTrue(vm.meetingBriefEnabled)
    }

    func testTheSwitchWritesOnlyTheMeetingBrief() async throws {
        let client = MockAPNSPrefsClient()
        let vm = NotificationsPaneViewModel(client: client)
        await vm.load()

        await vm.setMeetingBrief(true)

        let put = try XCTUnwrap(client.puts.last)
        XCTAssertEqual(put.meetingBriefEnabled, true)
        XCTAssertNil(put.chatEnabled)
        XCTAssertNil(put.digestEnabled)
        XCTAssertTrue(vm.meetingBriefEnabled)
        let body = try JSONEncoder().encode(put)
        XCTAssertEqual(String(bytes: body, encoding: .utf8), #"{"meetingBriefEnabled":true}"#)
    }

    func testAFailedWriteRollsBack() async {
        let client = MockAPNSPrefsClient(meetingBriefEnabled: false)
        client.putError = Boom()
        let vm = NotificationsPaneViewModel(client: client)
        await vm.load()

        await vm.setMeetingBrief(true)

        XCTAssertFalse(vm.meetingBriefEnabled)
        XCTAssertEqual(vm.state, .failed("Couldn't load notification preferences."))
    }

    func testKnowsWhenCalendarSyncIsOff() async {
        let off = NotificationsPaneViewModel(
            client: MockAPNSPrefsClient(),
            calendarReadiness: StubCalendarSyncReadiness(value: .consentOff)
        )
        XCTAssertEqual(off.calendarReadiness, .unknown)
        await off.load()
        XCTAssertEqual(off.calendarReadiness, .consentOff)
        XCTAssertTrue(off.meetingBriefNeedsCalendar)

        let ready = NotificationsPaneViewModel(
            client: MockAPNSPrefsClient(),
            calendarReadiness: StubCalendarSyncReadiness(value: .ready)
        )
        await ready.load()
        XCTAssertFalse(ready.meetingBriefNeedsCalendar)

        // Nothing to check with: say nothing rather than guess.
        let unchecked = NotificationsPaneViewModel(client: MockAPNSPrefsClient())
        await unchecked.load()
        XCTAssertEqual(unchecked.calendarReadiness, .unknown)
        XCTAssertFalse(unchecked.meetingBriefNeedsCalendar)
    }

    func testTheConsentComesFirst() async {
        let off = LiveCalendarSyncReadiness(consentClient: StubAppleConsentClient(consents: [
            AppleConsentDTO(domain: .calendar, allowed: false),
            AppleConsentDTO(domain: .reminders, allowed: true),
        ]))
        let readinessOff = await off.readiness()
        XCTAssertEqual(readinessOff, .consentOff)

        let missing = LiveCalendarSyncReadiness(consentClient: StubAppleConsentClient())
        let readinessMissing = await missing.readiness()
        XCTAssertEqual(readinessMissing, .consentOff)

        let unreachable = LiveCalendarSyncReadiness(consentClient: StubAppleConsentClient(fails: true))
        let readinessUnknown = await unreachable.readiness()
        XCTAssertEqual(readinessUnknown, .unknown)
    }

    func testSystemCalendarPermissionMapping() {
        XCTAssertEqual(LiveCalendarSyncReadiness.readiness(for: .fullAccess), .ready)
        // The sync asks as soon as it starts.
        XCTAssertEqual(LiveCalendarSyncReadiness.readiness(for: .notDetermined), .ready)
        XCTAssertEqual(LiveCalendarSyncReadiness.readiness(for: .denied), .systemAccessOff)
        XCTAssertEqual(LiveCalendarSyncReadiness.readiness(for: .restricted), .systemAccessOff)
        XCTAssertEqual(LiveCalendarSyncReadiness.readiness(for: .writeOnly), .systemAccessOff)
    }
}
