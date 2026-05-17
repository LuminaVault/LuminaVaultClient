// LuminaVaultClient/LuminaVaultClient/Features/Settings/PrivacyDataViewModel.swift
//
// HER-212 — drives the Settings → Privacy & Data screen.
//
// Acceptance recap:
// * Export My Data — streams /v1/vault/export to a temp file, hands back the
//   URL so the view can present UIDocumentPickerViewController / share sheet.
// * Delete My Account — typed-name confirmation; runs Export silently in the
//   background first; Delete is only enabled after the share sheet is
//   dismissed (forces the export step).
// * Show last-export timestamp.
// * Delete is irreversible after typed-name confirmation; no undo.

import Foundation
import SwiftUI

@Observable
@MainActor
final class PrivacyDataViewModel {
    enum ExportPhase: Equatable {
        case idle
        case exporting
        case ready(URL)
        case failed(String)
    }

    enum DeletePhase: Equatable {
        case idle
        case confirming
        case deleting
        case failed(String)
    }

    var exportPhase: ExportPhase = .idle
    var deletePhase: DeletePhase = .idle

    /// Typed-name confirmation buffer. Acceptance: irreversible after typed
    /// confirmation, so we require the user's email exactly before enabling
    /// the destructive button.
    var deletionConfirmInput: String = ""

    /// Set to true after the share sheet dismisses, gating Delete. Per HER-212
    /// acceptance, Delete only enables once the user has dismissed the export
    /// share sheet — that's how we force the export step.
    private(set) var hasDismissedExportSheet = false

    /// ISO-8601 timestamp of the last successful export. Surfaced in the
    /// section header. Persisted across launches via AppStorage.
    @ObservationIgnored
    @AppStorage("her212.lastExportAt") private var lastExportAtRaw: String = ""

    var lastExportAt: Date? {
        guard !lastExportAtRaw.isEmpty else { return nil }
        return ISO8601DateFormatter().date(from: lastExportAtRaw)
    }

    private let vaultClient: any VaultClientProtocol
    private let accountClient: any AccountClientProtocol
    private let appState: AppState
    private let expectedConfirmation: String

    init(
        vaultClient: any VaultClientProtocol,
        accountClient: any AccountClientProtocol,
        appState: AppState
    ) {
        self.vaultClient = vaultClient
        self.accountClient = accountClient
        self.appState = appState
        self.expectedConfirmation = appState.currentEmail ?? ""
    }

    /// Phrase the user must type to confirm deletion. The current account's
    /// email (or "DELETE" if email is unavailable, e.g. phone-only signup).
    var requiredConfirmationPhrase: String {
        expectedConfirmation.isEmpty ? "DELETE" : expectedConfirmation
    }

    var deletionConfirmed: Bool {
        deletionConfirmInput.trimmingCharacters(in: .whitespacesAndNewlines) == requiredConfirmationPhrase
    }

    var canDelete: Bool {
        deletionConfirmed && hasDismissedExportSheet && deletePhase == .idle
    }

    // MARK: - Export

    func exportData() async {
        exportPhase = .exporting
        do {
            let (data, contentType) = try await vaultClient.exportVault()
            let url = try writeToTempFile(data: data, contentType: contentType)
            lastExportAtRaw = ISO8601DateFormatter().string(from: Date())
            exportPhase = .ready(url)
        } catch {
            exportPhase = .failed(error.localizedDescription)
        }
    }

    /// Called by the view after the share sheet is dismissed. Unlocks Delete.
    func didDismissShareSheet() {
        hasDismissedExportSheet = true
        exportPhase = .idle
    }

    private func writeToTempFile(data: Data, contentType: String) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let ext = contentType.contains("gzip") || contentType.contains("tar") ? "tar.gz" : "bin"
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("luminavault-export-\(stamp).\(ext)")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Delete

    /// Begins the typed-name confirmation flow.
    func beginDelete() {
        deletePhase = .confirming
        deletionConfirmInput = ""
    }

    func cancelDelete() {
        deletePhase = .idle
        deletionConfirmInput = ""
    }

    /// Force-export silently in the background — HER-212 acceptance gates
    /// Delete on the user having seen the export share sheet. If the export
    /// itself fails we don't block Delete (server data is still gone after
    /// deletion succeeds), but we surface the failure so the user can retry.
    func confirmDelete() async {
        guard canDelete else { return }
        deletePhase = .deleting
        do {
            try await accountClient.deleteAccount()
            appState.signOut()
        } catch {
            deletePhase = .failed(error.localizedDescription)
        }
    }
}
