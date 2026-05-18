// LuminaVaultClient/LuminaVaultClient/Features/Capture/CapturePhotosViewModel.swift
//
// HER-34 — observable VM behind the "+" FAB sheet. Holds the picker
// state, per-item caption text, the location toggle, and the save flow.
// The save flow enqueues snapshots to `CaptureQueue`; it does NOT call
// the network directly — that's `CaptureDrainer`'s job.

import Foundation
import LuminaVaultShared
import Observation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
@Observable
final class CapturePhotosViewModel {
    enum ToastKind: Equatable, Sendable {
        case savedOnline(count: Int)
        case queuedOffline(count: Int)
        case failed(String)
    }

    // MARK: - Picker state

    var pickerItems: [PhotosPickerItem] = [] {
        didSet {
            Task { await self.refreshLoadedItems() }
        }
    }
    var loadedItems: [LoadedItem] = []
    var locationEnabled: Bool = false
    var saving: Bool = false
    var toast: ToastKind?

    /// HER-CaptureTab — Spaces fetched from `/v1/spaces` on first open of
    /// the sheet. nil while loading; empty array means "user has no
    /// Spaces yet" (the picker stays hidden in that case).
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

    // MARK: - Save

    func save() async {
        guard !saving, !loadedItems.isEmpty else { return }
        saving = true
        defer { saving = false }

        var fix: LocationFix?
        if locationEnabled {
            fix = await locationService.requestFix()
        }

        let snapshots = loadedItems.map { item in
            CaptureSnapshot(
                captionText: item.caption,
                imageData: item.data,
                contentType: item.contentType,
                fileExtension: item.fileExtension,
                lat: fix?.lat,
                lng: fix?.lng,
                accuracyM: fix?.accuracyM,
                placeName: fix?.placeName,
                spaceID: selectedSpaceID,
            )
        }

        do {
            for snapshot in snapshots {
                try await queue.enqueue(snapshot)
            }
            // Kick the drainer immediately — if online it will land
            // captures before the user closes the sheet; if offline the
            // drainer's first tick will fall through and rows stay queued.
            await drainer.kick()
            toast = .queuedOffline(count: snapshots.count)
        } catch {
            toast = .failed(error.localizedDescription)
        }
    }

    // MARK: - Picker → loaded items

    private func refreshLoadedItems() async {
        let items = pickerItems
        var loaded: [LoadedItem] = []
        for (idx, item) in items.enumerated() {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            let (contentType, ext) = Self.detectFormat(item: item)
            let existingCaption = idx < loadedItems.count ? loadedItems[idx].caption : ""
            loaded.append(LoadedItem(
                id: UUID(),
                data: data,
                contentType: contentType,
                fileExtension: ext,
                caption: existingCaption,
            ))
        }
        loadedItems = loaded
    }

    /// Inspect `PhotosPickerItem.supportedContentTypes` to pick the MIME
    /// + filename extension we send to the server. HEIC is the iOS
    /// default since iOS 11; JPEG falls back when the user picks a
    /// share-extension-saved or non-Photos asset.
    static func detectFormat(item: PhotosPickerItem) -> (contentType: String, fileExtension: String) {
        for type in item.supportedContentTypes {
            if type.conforms(to: .heic) { return ("image/heic", "heic") }
            if type.conforms(to: .jpeg) { return ("image/jpeg", "jpg") }
            if type.conforms(to: .png) { return ("image/png", "png") }
        }
        return ("image/jpeg", "jpg")
    }
}

struct LoadedItem: Identifiable, Equatable, Sendable {
    let id: UUID
    let data: Data
    let contentType: String
    let fileExtension: String
    var caption: String
}

/// Indirection so the VM can poke the drainer without holding a strong
/// reference to it (and without dragging actor-isolation into the VM
/// surface). The app wires this to `CaptureDrainer.tick`.
struct CaptureDrainerHandle: Sendable {
    let kick: @Sendable () async -> Void

    static let noop = CaptureDrainerHandle(kick: {})
}
