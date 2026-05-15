// LuminaVaultClient/LuminaVaultClientTests/Mocks/MockTelemetry.swift
//
// HER-219 — recording fake for telemetry assertions. Stores every event
// in order so tests can assert exact sequences.

@testable import LuminaVaultClient
import Foundation

final class MockTelemetry: TelemetryProtocol, @unchecked Sendable {
    struct RecordedEvent: Equatable {
        let name: String
        let properties: [String: String]
    }

    private let lock = NSLock()
    private var _events: [RecordedEvent] = []

    var events: [RecordedEvent] {
        lock.lock(); defer { lock.unlock() }
        return _events
    }

    var eventNames: [String] { events.map(\.name) }

    func track(_ event: String, properties: [String: String]) {
        lock.lock(); defer { lock.unlock() }
        _events.append(RecordedEvent(name: event, properties: properties))
    }
}
