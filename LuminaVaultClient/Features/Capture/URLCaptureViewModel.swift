// LuminaVaultClient/LuminaVaultClient/Features/Capture/URLCaptureViewModel.swift
//
// HER-257 — VM behind the FAB sheet's "Link" mode. Owns the URL field,
// optional note, optional Space selection, and the save flow. Save
// enqueues a `.url` capture; the drainer posts to /v1/capture/safari
// so the user gets offline support + retry for free.

import Foundation
import LuminaVaultShared
import Observation

@MainActor
@Observable
final class URLCaptureViewModel {
    // MARK: - User-facing state

    var urlString: String = ""
    var note: String = ""
    var saving: Bool = false
    var toast: CapturePhotosViewModel.ToastKind?

    /// Loaded on view appear; nil while in-flight; empty = user has no
    /// Spaces (picker stays hidden).
    var availableSpaces: [SpaceDTO]?
    var selectedSpaceID: UUID?

    // MARK: - Collaborators

    private let queue: CaptureQueueProtocol
    private let drainer: CaptureDrainerHandle
    private let spacesClient: (any SpacesClientProtocol)?

    init(
        queue: CaptureQueueProtocol,
        drainer: CaptureDrainerHandle,
        spacesClient: (any SpacesClientProtocol)? = nil
    ) {
        self.queue = queue
        self.drainer = drainer
        self.spacesClient = spacesClient
    }

    /// Validates the URL surface-level: scheme must be `http`/`https` and
    /// the string must parse into a `URL` with a host. Server-side
    /// resolvers (HER-149) do their own deeper validation; the client
    /// only blocks obvious garbage so save can show feedback instantly.
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

    var canSave: Bool { isURLValid && !saving }

    func loadSpacesIfNeeded() async {
        guard availableSpaces == nil, let spacesClient else { return }
        do {
            availableSpaces = try await spacesClient.list()
        } catch {
            availableSpaces = []
        }
    }

    func save() async {
        guard isURLValid, !saving else { return }
        saving = true
        defer { saving = false }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let snapshot = CaptureSnapshot.url(
            url: trimmedURL,
            note: trimmedNote.isEmpty ? nil : trimmedNote,
            spaceID: selectedSpaceID,
        )

        do {
            try await queue.enqueue(snapshot)
            await drainer.kick()
            toast = .queuedOffline(count: 1)
            urlString = ""
            note = ""
        } catch {
            toast = .failed(error.localizedDescription)
        }
    }
}
