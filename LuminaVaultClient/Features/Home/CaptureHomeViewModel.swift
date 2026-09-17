// LuminaVaultClient/LuminaVaultClient/Features/Home/CaptureHomeViewModel.swift
//
// Drives the capture-first Home tab: one composer over a feed of what you
// have recently saved.
//
// Saves go through the same queue every other capture surface uses, so the
// composer inherits offline support, retries and the review-captures path for
// free. Nothing here talks to the network directly; `CaptureDrainer` does.

import Foundation
import LuminaVaultShared
import Observation

/// A capture that is in the queue but not yet in a listing. UI-only, so it is
/// named for what it is rather than borrowing a wire DTO.
struct PendingSaveUIModel: Identifiable, Equatable, Sendable {
    let id: UUID
    let kind: PendingCaptureKind
    /// What to show as the row's title until the real file exists.
    let displayText: String
    /// Where the drainer will land this. See `predictedPath(for:)`.
    let predictedPath: String
    let createdAt: Date
    /// Set once the drainer has given up on this capture. The row stays on
    /// screen when this is non-nil — it is the only remaining trace of what the
    /// user captured, and for a voice note the audio is in the queue row and
    /// nowhere else.
    var failure: String?

    var hasFailed: Bool { failure != nil }
}

@MainActor
@Observable
final class CaptureHomeViewModel {
    // MARK: - Composer state

    var text: String = ""
    var saving: Bool = false
    var toast: CapturePhotosViewModel.ToastKind?

    /// Rows that are queued but not yet on the server, newest first.
    private(set) var pending: [PendingSaveUIModel] = []

    /// `pending` minus anything the feed is already showing.
    ///
    /// A row is dropped when its queue entry goes, but the feed may well have
    /// refetched first — and a capture appearing twice for a second reads as a
    /// duplicate save. The predicted path makes that check exact: the snapshot
    /// id is the basename the drainer uploads under, and the server keeps only
    /// the basename.
    var visiblePending: [PendingSaveUIModel] {
        let listed = Set(files.displayedFiles.map(\.path))
        return pending.filter { row in
            row.hasFailed || row.predictedPath.isEmpty || !listed.contains(row.predictedPath)
        }
    }

    /// Spaces available to file into, fetched once. nil while loading; empty
    /// means the user has none and the picker stays hidden.
    var availableSpaces: [SpaceDTO]?
    /// Where the next capture is filed. nil = unfiled, which lands in the
    /// vault root the same way the capture sheet's "Unfiled" does.
    var selectedSpaceID: UUID?

    /// The name of a Space, for a feed row that knows only its id. Nil while
    /// the Spaces list is still loading and for the vault root.
    func spaceName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return availableSpaces?.first(where: { $0.id == id })?.name
    }

    /// Recording state, so the composer can show a mic that is visibly live.
    let recorder = VoiceRecorder()
    var isRecording: Bool { recorder.isRecording }

    /// The recent-saves feed. `spaceSlug: nil` lists every Space, which is what
    /// makes this a record of what you have been saving rather than a folder.
    let files: VaultFilesViewModel

    // MARK: - Collaborators

    /// Nil until `appState.vaultInitialized`. The composer disables its save
    /// button in that window rather than accepting a capture it cannot store —
    /// same gate every other capture control uses.
    private let queue: CaptureQueueProtocol?
    private let drainer: CaptureDrainerHandle
    private let spacesClient: (any SpacesClientProtocol)?

    init(
        queue: CaptureQueueProtocol?,
        drainer: CaptureDrainerHandle,
        vaultClient: VaultClientProtocol,
        spacesClient: (any SpacesClientProtocol)? = nil
    ) {
        self.queue = queue
        self.drainer = drainer
        self.spacesClient = spacesClient
        self.files = VaultFilesViewModel(vaultClient: vaultClient, spaceSlug: nil)

        // Reaching the two-minute cap finishes a note; it does not discard one.
        recorder.onCapReached = { [weak self] audio in
            guard let self else { return }
            Task { await self.enqueueVoice(audio) }
        }
    }

    // MARK: - What the composer understood

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A field holding nothing but a URL is a link. Anything else is a note,
    /// even when it contains a URL: "read this <url> before Friday" is a
    /// thought about a link, and filing it as a bare bookmark would throw the
    /// thought away. Matches the web composer's `detectSoleUrl`.
    var detectedLink: URL? {
        let tokens = trimmedText.split(whereSeparator: \.isWhitespace)
        guard tokens.count == 1, let url = URL(string: String(tokens[0])) else { return nil }
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return nil
        }
        guard url.host?.isEmpty == false else { return nil }
        return url
    }

    var canSave: Bool { !trimmedText.isEmpty && !saving && queue != nil }

    // MARK: - Saving

    func submit() async {
        guard canSave, let queue else { return }
        let body = trimmedText
        saving = true
        defer { saving = false }

        let id = UUID()
        let link = detectedLink
        let snapshot = link.map {
            CaptureSnapshot.url(id: id, url: $0.absoluteString, spaceID: selectedSpaceID)
        } ?? CaptureSnapshot.text(id: id, body: body, spaceID: selectedSpaceID)

        do {
            try await queue.enqueue(snapshot)
            // The snapshot's id is the basename the drainer uploads under, and
            // the server keeps only the basename, so the eventual path is known
            // before the request is made. That makes reconciliation exact
            // rather than a guess at which new row is ours.
            pending.insert(
                PendingSaveUIModel(
                    id: id,
                    kind: snapshot.kind,
                    displayText: link?.host ?? body,
                    predictedPath: predictedPath(for: snapshot),
                    createdAt: snapshot.createdAt
                ),
                at: 0
            )
            text = ""
            await drainer.kick()
            toast = .queuedOffline(count: 1)
            await settlePending()
        } catch {
            // The text stays in the box. Losing what someone just typed is
            // worse than making them press the button again.
            toast = .failed(error.localizedDescription)
        }
    }

    /// Where the drainer's upload will land.
    ///
    /// `VaultController.upload` keeps only the basename and files it under the
    /// Space's slug — or `inbox` when unfiled — so the path is known before the
    /// request is made. A `.url` row's path is chosen by the server (it embeds
    /// the host and a uuid) and cannot be predicted; such a row still shows as
    /// pending, it just clears on the queue draining rather than by path.
    private func predictedPath(for snapshot: CaptureSnapshot) -> String {
        guard snapshot.kind == .text || snapshot.kind == .voice else { return "" }
        return "\(spaceFolder(for: snapshot.spaceID))/\(snapshot.id.uuidString).md"
    }

    /// Mirrors the server's choice of folder. An id with no matching Space
    /// falls back to `inbox`, which is what the server does too.
    private func spaceFolder(for spaceID: UUID?) -> String {
        guard let spaceID,
              let slug = availableSpaces?.first(where: { $0.id == spaceID })?.slug,
              !slug.isEmpty
        else { return "inbox" }
        return slug
    }

    // MARK: - Voice

    /// Starts recording, or stops and saves what was recorded.
    ///
    /// The audio is queued rather than transcribed here, so a note can be
    /// spoken with no signal and transcribed whenever the device next has one.
    func toggleRecording() async {
        if recorder.isRecording {
            guard let audio = recorder.stop() else {
                toast = .failed("That recording was empty.")
                return
            }
            await enqueueVoice(audio)
        } else {
            do {
                try await recorder.start()
            } catch {
                toast = .failed(error.localizedDescription)
            }
        }
    }

    func cancelRecording() {
        recorder.discard()
    }

    /// Not private so a test can enqueue audio without driving real recording
    /// hardware. `toggleRecording` is the only production caller.
    func enqueueVoice(_ audio: Data) async {
        guard let queue else { return }
        let id = UUID()
        let snapshot = CaptureSnapshot.voice(id: id, audio: audio, spaceID: selectedSpaceID)
        do {
            try await queue.enqueue(snapshot)
            pending.insert(
                PendingSaveUIModel(
                    id: id,
                    kind: .voice,
                    displayText: "Voice note",
                    predictedPath: predictedPath(for: snapshot),
                    createdAt: snapshot.createdAt
                ),
                at: 0
            )
            await drainer.kick()
            toast = .queuedOffline(count: 1)
            await settlePending()
        } catch {
            toast = .failed(error.localizedDescription)
        }
    }

    // MARK: - Feed

    func loadFeed() async {
        await files.load()
        await reconcileWithQueue()
    }

    /// Fetched once per session. A failure leaves the picker hidden rather than
    /// blocking capture — filing is a convenience, capturing is the point.
    func loadSpacesIfNeeded() async {
        guard availableSpaces == nil, let spacesClient else { return }
        do {
            availableSpaces = try await spacesClient.list()
        } catch {
            availableSpaces = []
        }
    }

    /// Waits for the drainer to work through what was just enqueued, then
    /// refreshes. Bounded: if the device is offline the rows simply stay
    /// queued, which is what the offline-first queue exists to express.
    private func settlePending() async {
        for delay in [0.4, 1.0, 2.5] {
            try? await Task.sleep(for: .seconds(delay))
            let cleared = await reconcileWithQueue()
            if cleared { await files.load() }
            if pending.allSatisfy(\.hasFailed) { return }
        }
    }

    /// Reconciles the on-screen rows with the queue.
    ///
    /// A row leaving `pending()` does **not** mean it was saved: `pending()`
    /// filters on state, so a capture that exhausted its retries and flipped to
    /// `.failed` leaves it too. Treating that as success is how a capture
    /// disappears silently — the row vanishes and no file is ever written. So
    /// failed rows are looked up explicitly and kept on screen.
    ///
    /// Returns whether anything reached a terminal state.
    @discardableResult
    private func reconcileWithQueue() async -> Bool {
        guard let queue else { return false }
        guard let queued = try? await queue.pending() else { return false }
        let failedRows = (try? await queue.failed()) ?? []

        let stillQueued = Set(queued.map(\.id))
        let failures = Dictionary(
            failedRows.map { ($0.id, $0.lastError ?? "Couldn't save this.") },
            uniquingKeysWith: { first, _ in first }
        )

        var settled = false
        pending = pending.compactMap { row in
            if stillQueued.contains(row.id) { return row }
            if let reason = failures[row.id] {
                settled = true
                guard !row.hasFailed else { return row }
                var marked = row
                marked.failure = reason
                return marked
            }
            // Gone from both: the drainer deleted it, which it only does after
            // the capture is stored.
            settled = true
            return nil
        }
        return settled
    }

    /// Put a failed capture back in the queue. The audio or text is still in
    /// the row, so this is a real retry rather than asking the user to redo it.
    func retry(_ row: PendingSaveUIModel) async {
        guard let queue else { return }
        do {
            try await queue.retry(id: row.id)
            if let index = pending.firstIndex(where: { $0.id == row.id }) {
                pending[index].failure = nil
            }
            await drainer.kick()
            await settlePending()
        } catch {
            toast = .failed(error.localizedDescription)
        }
    }

    /// Give up on a failed capture and delete it. Explicit, because this throws
    /// away the only copy.
    func discard(_ row: PendingSaveUIModel) async {
        guard let queue else { return }
        try? await queue.delete(id: row.id)
        pending.removeAll { $0.id == row.id }
    }
}
