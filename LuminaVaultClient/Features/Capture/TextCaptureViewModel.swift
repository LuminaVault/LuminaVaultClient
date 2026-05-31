// LuminaVaultClient/LuminaVaultClient/Features/Capture/TextCaptureViewModel.swift
//
// HER-256 — observable VM behind the FAB sheet's "Text" mode. Owns the
// body field, the geo toggle, and the save flow. Save enqueues a `.text`
// capture and kicks the drainer; the actual `POST /v1/memory/upsert`
// happens in `CaptureDrainer` so the user gets offline support for free.

import Foundation
import LuminaVaultShared
import Observation

@MainActor
@Observable
final class TextCaptureViewModel {
    // MARK: - User-facing state

    var content: String = ""
    var locationEnabled: Bool = false
    var saving: Bool = false
    /// Reuses the photo VM's enum so the eventual shared toast renderer
    /// can render both flows without a second type.
    var toast: CapturePhotosViewModel.ToastKind?

    /// HER-CaptureTab — Spaces fetched from `/v1/spaces` on first open of
    /// the sheet. nil while loading; empty array means "user has no Spaces
    /// yet" (the picker stays hidden in that case). Without this the note
    /// always filed as unfiled (spaceID nil) → invisible under every Space.
    var availableSpaces: [SpaceDTO]?
    /// User's current selection. nil = unfiled.
    var selectedSpaceID: UUID?

    // MARK: - Collaborators

    private let queue: CaptureQueueProtocol
    private let locationService: LocationServiceProtocol
    private let drainer: CaptureDrainerHandle
    private let spacesClient: (any SpacesClientProtocol)?

    init(
        queue: CaptureQueueProtocol,
        locationService: LocationServiceProtocol,
        drainer: CaptureDrainerHandle,
        spacesClient: (any SpacesClientProtocol)? = nil
    ) {
        self.queue = queue
        self.locationService = locationService
        self.drainer = drainer
        self.spacesClient = spacesClient
    }

    /// Loads available Spaces for the picker. Called from the view's
    /// `.task`. Silently no-ops on failure — the sheet still works as
    /// "unfiled capture" if the spaces fetch is unreachable.
    func loadSpacesIfNeeded() async {
        guard availableSpaces == nil, let spacesClient else { return }
        do {
            availableSpaces = try await spacesClient.list()
        } catch {
            availableSpaces = []
        }
    }

    /// Trimmed body, used by the view to drive the Save button's enabled
    /// state and by `save()` to filter whitespace-only submissions.
    var trimmedContent: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var canSave: Bool { !trimmedContent.isEmpty && !saving }

    func save() async {
        let body = trimmedContent
        guard !body.isEmpty, !saving else { return }
        saving = true
        defer { saving = false }

        var fix: LocationFix?
        if locationEnabled {
            fix = await locationService.requestFix()
        }

        let snapshot = CaptureSnapshot.text(
            body: body,
            lat: fix?.lat,
            lng: fix?.lng,
            accuracyM: fix?.accuracyM,
            placeName: fix?.placeName,
            spaceID: selectedSpaceID,
        )

        do {
            try await queue.enqueue(snapshot)
            await drainer.kick()
            toast = .queuedOffline(count: 1)
            content = ""
        } catch {
            toast = .failed(error.localizedDescription)
        }
    }
}
