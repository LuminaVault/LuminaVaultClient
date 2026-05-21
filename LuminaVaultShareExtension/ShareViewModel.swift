// LuminaVaultShareExtension/ShareViewModel.swift
//
// HER-258 — extension-side view model. Mirrors `URLCaptureViewModel`'s
// shape but talks to the App Group queue (`SharedShareQueue.append`)
// instead of the live `CaptureQueue`. Spaces come from the App Group
// cache (`SharedSpacesCache`) that the main app keeps in sync.

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ShareViewModel {
    enum SaveState: Equatable {
        case idle
        case saving
        case saved
        case failed(String)
    }

    var urlString: String
    var note: String = ""
    var selectedSpaceID: UUID?
    var saveState: SaveState = .idle
    /// Loaded from the App Group on init. `nil` means the cache is
    /// missing — the picker stays hidden in that case and the share
    /// lands unfiled.
    let availableSpaces: [SharedSpaceSummary]?

    init(initialURL: String) {
        self.urlString = initialURL
        // Read directly via SharedAppGroup to keep the extension target
        // independent of `SharedSpacesCache` (which imports
        // `LuminaVaultShared` for the writer signature).
        self.availableSpaces = SharedAppGroup.read(
            [SharedSpaceSummary].self,
            from: SharedAppGroup.FileName.spacesCache,
        )
    }

    var trimmedURL: String {
        urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isURLValid: Bool {
        let t = trimmedURL
        guard !t.isEmpty,
              let parsed = URL(string: t),
              let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              parsed.host?.isEmpty == false
        else { return false }
        return true
    }

    var canSave: Bool {
        if case .saving = saveState { return false }
        return isURLValid
    }

    /// Persist a `PendingShare` to the App Group. The host app's
    /// `CaptureCoordinator` will replay it into the live capture queue
    /// the next time it cold-starts (or the next time `applicationWillEnterForeground`
    /// triggers the coordinator restart, depending on how the host wires it up).
    func save() {
        guard isURLValid, saveState != .saving else { return }
        saveState = .saving
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let share = PendingShare(
            url: trimmedURL,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            spaceID: selectedSpaceID,
        )
        do {
            try SharedShareQueue.append(share)
            saveState = .saved
        } catch {
            saveState = .failed(error.localizedDescription)
        }
    }
}
