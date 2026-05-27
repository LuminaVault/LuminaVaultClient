// LuminaVaultShareExtension/ShareViewModel.swift
//
// Extension-side view model. Saves directly with the shared bearer token
// when possible and falls back to the App Group queue when offline or
// unauthenticated.

import Foundation
import Observation

@MainActor
@Observable
final class ShareViewModel {
    enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case queued
        case failed(String)
    }

    let payloads: [SharePayload]
    var note: String = ""
    var selectedSpaceID: UUID?
    var saveState: SaveState = .idle
    /// Loaded from the App Group on init. `nil` means the cache is
    /// missing — the picker stays hidden in that case and the share
    /// lands unfiled.
    let availableSpaces: [SharedSpaceSummary]?
    private let client: ShareExtensionCaptureClient

    init(
        payloads: [SharePayload],
        client: ShareExtensionCaptureClient = ShareExtensionCaptureClient()
    ) {
        self.payloads = payloads
        self.client = client
        let spaces = SharedAppGroup.read(
            [SharedSpaceSummary].self,
            from: SharedAppGroup.FileName.spacesCache,
        )
        self.availableSpaces = spaces
        if let lastSpaceID = SharedCapturePreferences.lastShareSpaceID,
           spaces?.contains(where: { $0.id == lastSpaceID }) == true {
            self.selectedSpaceID = lastSpaceID
        }
    }

    var canSave: Bool {
        if case .saving = saveState { return false }
        return !payloads.isEmpty
    }

    func save() async {
        guard canSave else { return }
        saveState = .saving
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = trimmedNote.isEmpty ? nil : trimmedNote
        var queuedCount = 0

        for payload in payloads {
            do {
                try await client.capture(payload, note: note, spaceID: selectedSpaceID)
            } catch {
                do {
                    try queue(payload, note: note)
                    queuedCount += 1
                } catch {
                    saveState = .failed(error.localizedDescription)
                    return
                }
            }
        }

        SharedCapturePreferences.lastShareSpaceID = selectedSpaceID
        saveState = queuedCount > 0 ? .queued : .saved
    }

    func failureMessage() -> String? {
        if case .failed(let message) = saveState {
            return message
        }
        if payloads.isEmpty {
            return "LuminaVault could not read a supported URL, text, or image attachment from this share."
        }
        return nil
    }

    private func queue(_ payload: SharePayload, note: String?) throws {
        switch payload {
        case .url(let id, let url):
            try SharedShareQueue.append(PendingShare(id: id, url: url, note: note, spaceID: selectedSpaceID))
        case .text(let id, let text):
            try SharedShareQueue.append(PendingShare(id: id, text: text, note: note, spaceID: selectedSpaceID))
        case .image(let id, let data, let contentType, let fileExtension):
            _ = try SharedShareQueue.appendImage(
                id: id,
                data: data,
                contentType: contentType,
                fileExtension: fileExtension,
                note: note,
                spaceID: selectedSpaceID,
            )
        }
    }
}
