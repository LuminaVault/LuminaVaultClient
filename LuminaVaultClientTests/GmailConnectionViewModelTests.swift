// LuminaVaultClient/LuminaVaultClientTests/GmailConnectionViewModelTests.swift
//
// Muse Stage C — the Gmail row in Linked Accounts: status (incl. a grant
// Google has rejected), the connect handoff, cancel, decline, and disconnect.
// The OAuth handoff is injected, so no browser opens.
//
// Async on purpose: synchronous @MainActor XCTest methods crash this host.

@testable import LuminaVaultClient
import LuminaVaultShared
import XCTest

@MainActor
final class GmailConnectionViewModelTests: XCTestCase {
    private static let disconnected = GmailStatusResponse(connected: false, needsReauth: false)
    private static let connected = GmailStatusResponse(
        connected: true, needsReauth: false, accountEmail: "me@example.com", calendarConnected: true
    )

    // MARK: - Status

    func testLoadDisconnectedOffersConnect() async {
        let client = StubGmailClient(statuses: [Self.disconnected])
        let vm = GmailConnectionViewModel(client: client, handoff: { _ in XCTFail("no handoff on load") })

        await vm.load()

        XCTAssertEqual(vm.state, .ready(Self.disconnected))
        XCTAssertFalse(vm.isConnected)
        XCTAssertEqual(vm.statusText, "Not connected")
        XCTAssertEqual(vm.connectLabel, "Connect Gmail")
    }

    func testLoadConnectedHasNoConnectAction() async {
        let vm = GmailConnectionViewModel(client: StubGmailClient(statuses: [Self.connected]))

        await vm.load()

        XCTAssertTrue(vm.isConnected)
        XCTAssertEqual(vm.statusText, "Connected")
        XCTAssertNil(vm.connectLabel)
        XCTAssertEqual(vm.disconnectMessage, "Hermie stops reading your inbox. Google Calendar stays connected.")
    }

    func testNeedsReauthOffersReconnect() async {
        let stale = GmailStatusResponse(connected: true, needsReauth: true, accountEmail: "me@example.com")
        let vm = GmailConnectionViewModel(client: StubGmailClient(statuses: [stale]))

        await vm.load()

        XCTAssertFalse(vm.isConnected)
        XCTAssertTrue(vm.needsReauth)
        XCTAssertEqual(vm.statusText, "Reconnect needed")
        XCTAssertEqual(vm.connectLabel, "Reconnect Gmail")
        XCTAssertEqual(vm.disconnectMessage, "Revokes Hermie's access to your Gmail. You can reconnect any time.")
    }

    func testLoadFailureIsShown() async {
        let vm = GmailConnectionViewModel(client: StubGmailClient(statuses: [], statusError: APIError.unauthorized))

        await vm.load()

        guard case .failed = vm.state else { return XCTFail("expected failed, got \(vm.state)") }
    }

    // MARK: - Connect

    func testConnectRunsHandoffWithServerURLThenReloads() async {
        let client = StubGmailClient(statuses: [Self.disconnected, Self.connected])
        let opened = OpenedURLs()
        let vm = GmailConnectionViewModel(client: client, handoff: { url in opened.urls.append(url) })
        await vm.load()

        await vm.connect()

        XCTAssertEqual(opened.urls, [URL(string: "https://accounts.google.com/o/oauth2/auth?scope=gmail.readonly")!])
        XCTAssertEqual(vm.state, .ready(Self.connected))
        XCTAssertNil(vm.lastError)
        XCTAssertFalse(vm.isWorking)
        let connects = await client.connectCalls
        XCTAssertEqual(connects, 1)
    }

    func testCancelledHandoffIsSilent() async {
        let client = StubGmailClient(statuses: [Self.disconnected])
        let vm = GmailConnectionViewModel(client: client, handoff: { _ in throw CalendarConnectError.cancelled })
        await vm.load()

        await vm.connect()

        XCTAssertNil(vm.lastError)
        XCTAssertEqual(vm.state, .ready(Self.disconnected))
    }

    func testDeclinedHandoffShowsReason() async {
        let client = StubGmailClient(statuses: [Self.disconnected])
        let vm = GmailConnectionViewModel(
            client: client,
            handoff: { _ in throw CalendarConnectError.declined("access_denied") }
        )
        await vm.load()

        await vm.connect()

        XCTAssertEqual(vm.lastError, "Google declined the connection (access_denied).")
        XCTAssertEqual(vm.state, .ready(Self.disconnected))
    }

    // MARK: - Disconnect

    func testDisconnectCallsServerAndReloads() async {
        let client = StubGmailClient(statuses: [Self.connected, Self.disconnected])
        let vm = GmailConnectionViewModel(client: client)
        await vm.load()

        await vm.disconnect()

        let disconnects = await client.disconnectCalls
        XCTAssertEqual(disconnects, 1)
        XCTAssertEqual(vm.state, .ready(Self.disconnected))
        XCTAssertNil(vm.lastError)
    }

    func testDisconnectFailureKeepsStatusAndShowsError() async {
        let client = StubGmailClient(statuses: [Self.connected], disconnectError: APIError.unauthorized)
        let vm = GmailConnectionViewModel(client: client)
        await vm.load()

        await vm.disconnect()

        XCTAssertEqual(vm.state, .ready(Self.connected))
        XCTAssertNotNil(vm.lastError)
    }

    func testPrivacyLine() async {
        XCTAssertEqual(
            GmailConnectionViewModel.privacyLine,
            "Hermie reads sender, subject and a snippet; never message bodies."
        )
    }
}

// MARK: - Stubs

@MainActor
private final class OpenedURLs {
    var urls: [URL] = []
}

private actor StubGmailClient: GmailClientProtocol {
    /// Returned in order; the last one repeats.
    private var statuses: [GmailStatusResponse]
    private let statusError: Error?
    private let disconnectError: Error?
    private(set) var connectCalls = 0
    private(set) var disconnectCalls = 0

    init(statuses: [GmailStatusResponse], statusError: Error? = nil, disconnectError: Error? = nil) {
        self.statuses = statuses
        self.statusError = statusError
        self.disconnectError = disconnectError
    }

    func status() async throws -> GmailStatusResponse {
        if let statusError { throw statusError }
        return statuses.count > 1 ? statuses.removeFirst() : statuses[0]
    }

    func connect() async throws -> CalendarConnectStartResponse {
        connectCalls += 1
        return CalendarConnectStartResponse(authorizeURL: "https://accounts.google.com/o/oauth2/auth?scope=gmail.readonly")
    }

    func disconnect() async throws {
        disconnectCalls += 1
        if let disconnectError { throw disconnectError }
    }
}
