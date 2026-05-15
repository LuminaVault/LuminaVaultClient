// LuminaVaultClient/LuminaVaultClient/App/Telemetry.swift
//
// HER-219 — lightweight in-app telemetry protocol. Onboarding hooks
// (and any other feature that wants to size demand) call into this.
// Real implementation forwards to OSLog; a no-op default ships so
// every consumer can be constructed without a real sink.

import Foundation
import OSLog

protocol TelemetryProtocol: Sendable {
    /// Records an event with an arbitrary string-keyed payload. Implementations
    /// must be non-blocking — fire-and-forget; never throw.
    func track(_ event: String, properties: [String: String])
}

extension TelemetryProtocol {
    /// Convenience: no payload.
    func track(_ event: String) {
        track(event, properties: [:])
    }
}

/// Default sink: emits to OSLog under `com.luminavault / telemetry`.
/// Cheap, structured, sees logs in Console.app and `log stream`.
struct LoggerTelemetry: TelemetryProtocol {
    private let logger = Logger(subsystem: "com.luminavault", category: "telemetry")

    func track(_ event: String, properties: [String: String]) {
        if properties.isEmpty {
            logger.info("\(event, privacy: .public)")
        } else {
            let serialized = properties
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            logger.info("\(event, privacy: .public) \(serialized, privacy: .public)")
        }
    }
}

/// Drop-in for previews / tests where telemetry is irrelevant.
struct NoopTelemetry: TelemetryProtocol {
    func track(_: String, properties _: [String: String]) {}
}
