// LuminaVaultClient/LuminaVaultClient/Features/Settings/Connections/ConnectionsHubViewModel.swift
import Foundation

@Observable
@MainActor
final class ConnectionsHubViewModel {
    var connections: [ConnectionSummaryDTO] = []
    var events: [ConnectionDiagnosticEventDTO] = []
    var isLoading = false
    var isTesting = false
    var errorMessage: String?
    var checkedAt: Date?

    private let client: any ConnectionsClientProtocol

    init(client: any ConnectionsClientProtocol) {
        self.client = client
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let summary = try await client.summary()
            connections = summary.connections
            checkedAt = summary.checkedAt
            events = try await client.events(limit: 20).events
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func testAll() async {
        isTesting = true
        errorMessage = nil
        defer { isTesting = false }

        do {
            _ = try await client.testAll()
            await load()
        } catch {
            errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
