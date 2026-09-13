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
    /// Where the drainer will land this. See `predictedPath(for:spaceSlug:)`.
    let predictedPath: String
    let createdAt: Date
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
            row.predictedPath.isEmpty || !listed.contains(row.predictedPath)
        }
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
    /// same gate as `CaptureFAB`.
    private let queue: CaptureQueueProtocol?
    private let drainer: CaptureDrainerHandle

    init(
        queue: CaptureQueueProtocol?,
        drainer: CaptureDrainerHandle,
        vaultClient: VaultClientProtocol
    ) {
        self.queue = queue
        self.drainer = drainer
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
        let snapshot = link.map { CaptureSnapshot.url(id: id, url: $0.absoluteString) }
            ?? CaptureSnapshot.text(id: id, body: body)

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
                    predictedPath: Self.predictedPath(for: snapshot),
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

    /// A `.url` row's path is chosen by the server (it embeds the host and a
    /// uuid), so only text rows can be predicted. An unpredictable row still
    /// shows as pending; it just cannot be matched by path, and is cleared
    /// when the queue drains instead.
    private static func predictedPath(for snapshot: CaptureSnapshot) -> String {
        guard snapshot.kind == .text || snapshot.kind == .voice else { return "" }
        return "inbox/\(snapshot.id.uuidString).md"
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

    private func enqueueVoice(_ audio: Data) async {
        guard let queue else { return }
        let id = UUID()
        let snapshot = CaptureSnapshot.voice(id: id, audio: audio)
        do {
            try await queue.enqueue(snapshot)
            pending.insert(
                PendingSaveUIModel(
                    id: id,
                    kind: .voice,
                    displayText: "Voice note",
                    predictedPath: Self.predictedPath(for: snapshot),
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
        await dropDrainedRows()
    }

    /// Waits for the drainer to work through what was just enqueued, then
    /// refreshes. Bounded: if the device is offline the rows simply stay
    /// queued, which is what the offline-first queue exists to express.
    private func settlePending() async {
        for delay in [0.4, 1.0, 2.5] {
            try? await Task.sleep(for: .seconds(delay))
            let cleared = await dropDrainedRows()
            if cleared { await files.load() }
            if pending.isEmpty { return }
        }
    }

    /// Drops pending rows whose queue entry is gone — which means the drainer
    /// posted them. Returns whether anything was dropped.
    @discardableResult
    private func dropDrainedRows() async -> Bool {
        guard let queue, let rows = try? await queue.pending() else { return false }
        let stillQueued = Set(rows.map(\.id))
        let before = pending.count
        pending.removeAll { !stillQueued.contains($0.id) }
        return pending.count != before
    }
}
