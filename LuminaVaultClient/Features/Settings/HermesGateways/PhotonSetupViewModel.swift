// LuminaVaultClient/LuminaVaultClient/Features/Settings/HermesGateways/PhotonSetupViewModel.swift
//
// Photon iMessage setup (the free path). Uses the server-side device-code flow
// + phone bind to provision a Spectrum project and obtain an assigned iMessage
// line. The server drives the Photon Dashboard APIs and (on success) activates
// the central Node sidecar.
//
// This VM:
//   startSetup    → POST /photon/setup, then opens the SSE stream
//   submitPhone   → POST /photon/setup/{id}/phone once user enters E.164
//   (stream)      → maps HermesPhotonSetupEvent into `phase`
//   cancel / retry
//
// State is ephemeral (like WhatsApp); re-open the sheet to restart if needed.

import Foundation
import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class PhotonSetupViewModel {
    /// The setup sheet's lifecycle / UI phase.
    enum Phase: Sendable, Equatable {
        case idle
        case starting
        /// We have a device code. Show the verification URI + user code for the user
        /// to approve in their browser (on photon.codes).
        case awaitingApproval(verificationUri: String, userCode: String, expiresIn: Int)
        /// User approved; now prompt for (or submit) the phone number.
        case awaitingPhone
        /// Submitting phone + running the provisioning steps on the server.
        case provisioning
        /// Success — we have the assigned iMessage line that contacts will text.
        case done(assignedLine: String)
        case failed(String)
    }

    private(set) var phase: Phase = .idle
    /// Seeded from catalog status; flipped on successful done.
    var isPaired: Bool
    var phoneInput: String = ""
    var isSubmittingPhone = false

    private let client: any HermesGatewaysClientProtocol
    private var streamTask: Task<Void, Never>?
    private var currentSessionID: UUID?

    init(client: any HermesGatewaysClientProtocol, isPaired: Bool) {
        self.client = client
        self.isPaired = isPaired
    }

    /// Start (or restart) the Photon setup flow.
    func startSetup() async {
        streamTask?.cancel()
        phase = .starting
        currentSessionID = nil
        phoneInput = ""

        do {
            let started = try await client.startPhotonSetup()
            currentSessionID = started.sessionID
            let task = Task { await self.consume(sessionID: started.sessionID) }
            streamTask = task
            await task.value
        } catch {
            phase = .failed(Self.message(error))
        }
    }

    /// Submit the entered phone (E.164) to advance past the approval step.
    func submitPhone() async {
        guard let sessionID = currentSessionID, !phoneInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSubmittingPhone = true
        defer { isSubmittingPhone = false }

        // Basic client-side normalization hint (server validates).
        let phone = phoneInput.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            try await client.photonSetupPhone(sessionID: sessionID, phone: phone)
            // The stream will drive us into .provisioning → .done
            phase = .provisioning
        } catch {
            phase = .failed(Self.message(error))
        }
    }

    private func consume(sessionID: UUID) async {
        let stream = client.photonSetupStream(sessionID)
        do {
            for try await event in stream {
                apply(event)
                if case .done = phase { break }
                if case .failed = phase { break }
            }
            switch phase {
            case .done, .failed:
                break
            default:
                if case .awaitingApproval = phase {
                    // Approval may still be pending if stream ended early.
                } else {
                    phase = .failed("Setup ended before completion. Please try again.")
                }
            }
        } catch is CancellationError {
            // Sheet dismissed
        } catch {
            phase = .failed(Self.message(error))
        }
    }

    private func apply(_ event: HermesPhotonSetupEvent) {
        switch event {
        case let .deviceCode(verificationUri, userCode, expiresIn):
            phase = .awaitingApproval(verificationUri: verificationUri, userCode: userCode, expiresIn: expiresIn)

        case let .status(status):
            switch status {
            case .starting:
                if case .awaitingApproval = phase {} else { phase = .starting }
            case .awaitingApproval:
                // Keep the device code info; the server is still waiting for browser approval.
                break
            case .approved:
                // Move to phone prompt if we aren't already submitting or further.
                if case .awaitingApproval = phase {
                    phase = .awaitingPhone
                }
            case .provisioning:
                phase = .provisioning
            case .done:
                // The assignedLine event will carry the actual number.
                if case .provisioning = phase {
                    // Will be overwritten by assignedLine if it arrives.
                }
            case .failed:
                phase = .failed("Setup failed on the server. Please try again.")
            }

        case let .assignedLine(line):
            phase = .done(assignedLine: line)
            isPaired = true

        case let .error(message):
            phase = .failed(message)
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        if case .done = phase {} else { phase = .idle }
        currentSessionID = nil
    }

    /// For the success state, the caller (detail view) can offer a generic
    /// "Disconnect" that will go through the normal gateway delete path.
    @discardableResult
    func disconnect() async -> HermesGatewayCatalogEntry? {
        // The parent detail view owns the actual delete call.
        // We just reset local state here.
        isPaired = false
        phase = .idle
        currentSessionID = nil
        return nil
    }

    private static func message(_ error: Error) -> String {
        if case let APIError.httpError(status, _) = error {
            return "Server returned HTTP \(status)."
        }
        return error.localizedDescription
    }
}
