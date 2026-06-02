// LuminaVaultClient/LuminaVaultClient/Features/Settings/HermesGateways/WhatsAppPairingViewModel.swift
//
// WhatsApp QR pairing — drives the dedicated pairing sheet. WhatsApp is the one
// Hermes gateway with no enterable credential: it pairs via Baileys, so the
// server runs `hermes whatsapp` in the tenant container and streams the
// terminal QR + status over SSE. This view model:
//   startPairing  → POST /whatsapp/pair, then opens the SSE stream
//   (stream)      → maps HermesWhatsAppPairEvent into `phase`
//   unlink        → DELETE /whatsapp/session
//
// State is ephemeral; if the stream drops the user just re-opens the sheet and
// pairs again. Mirrors NousAccountViewModel's ConnectPhase shape.

import Foundation
import LuminaVaultShared

@Observable
@MainActor
final class WhatsAppPairingViewModel {
    /// The pairing sheet's lifecycle.
    enum Phase: Sendable, Equatable {
        case idle
        /// POST in flight; container spinning up, no QR yet.
        case starting
        /// A QR is live and waiting to be scanned. `art` is the Unicode
        /// terminal block-art, rendered monospaced. `refreshing` flags that the
        /// previous code expired and Hermes is minting a new one.
        case awaitingScan(art: String, refreshing: Bool)
        /// Phone scanned the QR; Hermes is establishing the session.
        case linking
        /// Device linked, session persisted.
        case linked
        /// Pairing failed.
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// True once the tenant has a persisted WhatsApp session (drives the unlink
    /// affordance + the "Connected" resting state). Seeded from the catalog
    /// entry's status and flipped on link/unlink.
    var isPaired: Bool
    var isUnlinking = false

    private let client: any HermesGatewaysClientProtocol
    private var streamTask: Task<Void, Never>?

    init(client: any HermesGatewaysClientProtocol, isPaired: Bool) {
        self.client = client
        self.isPaired = isPaired
    }

    /// Begin a pairing session and consume the QR/status stream. Safe to call
    /// again to restart after a failure.
    func startPairing() async {
        streamTask?.cancel()
        phase = .starting
        do {
            let started = try await client.startWhatsAppPair()
            let task = Task { await self.consume(sessionID: started.sessionID) }
            streamTask = task
            await task.value
        } catch {
            phase = .failed(Self.message(error))
        }
    }

    /// Drive the SSE stream until a terminal event or the stream ends.
    private func consume(sessionID: UUID) async {
        let stream = client.whatsAppPairStream(sessionID)
        do {
            for try await event in stream {
                apply(event)
                if case .linked = phase { break }
                if case .failed = phase { break }
            }
            // Stream ended without a terminal event (e.g. process exited). If we
            // never reached a terminal state, surface a retryable failure.
            switch phase {
            case .linked, .failed:
                break
            default:
                phase = .failed("Pairing ended before linking. Please try again.")
            }
        } catch is CancellationError {
            // Sheet dismissed — leave phase as-is.
        } catch {
            phase = .failed(Self.message(error))
        }
    }

    private func apply(_ event: HermesWhatsAppPairEvent) {
        switch event {
        case let .qr(art):
            phase = .awaitingScan(art: art, refreshing: false)
        case let .status(status):
            switch status {
            case .starting:
                if case .awaitingScan = phase {} else { phase = .starting }
            case .awaitingScan:
                // Keep any QR we already have; just clear the refreshing flag.
                if case let .awaitingScan(art, _) = phase {
                    phase = .awaitingScan(art: art, refreshing: false)
                }
            case .linking:
                phase = .linking
            case .linked:
                phase = .linked
                isPaired = true
            case .expired:
                // Mark the current QR stale until the fresh one arrives.
                if case let .awaitingScan(art, _) = phase {
                    phase = .awaitingScan(art: art, refreshing: true)
                }
            case .failed:
                phase = .failed("Pairing failed. Please try again.")
            }
        case .linked:
            phase = .linked
            isPaired = true
        case let .error(message):
            phase = .failed(message)
        }
    }

    /// Abandon an in-flight pairing (sheet dismissed). Cancels the SSE task so
    /// the server reaps the subprocess via its stream-termination hook.
    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        if case .linked = phase {} else { phase = .idle }
    }

    /// Unlink WhatsApp: deletes the persisted session server-side and restarts
    /// the container. Returns the refreshed catalog entry so the caller can
    /// update the row badge.
    @discardableResult
    func unlink() async -> HermesGatewayCatalogEntry? {
        isUnlinking = true
        defer { isUnlinking = false }
        do {
            let entry = try await client.unlinkWhatsApp()
            isPaired = entry.status == .verified
            phase = .idle
            return entry
        } catch {
            phase = .failed(Self.message(error))
            return nil
        }
    }

    private static func message(_ error: Error) -> String {
        if case let APIError.httpError(status, _) = error {
            return "Server returned HTTP \(status)."
        }
        return error.localizedDescription
    }
}
