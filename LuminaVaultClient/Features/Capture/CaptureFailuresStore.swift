// LuminaVaultClient/LuminaVaultClient/Features/Capture/CaptureFailuresStore.swift
//
// The captures that did not make it, wherever they were made.
//
// A capture that exhausts `CaptureDrainer.maxAttempts` flips to `.failed` and
// stops retrying. Until this existed nothing in the app read those rows —
// `PendingCaptureState.failed` was written and never looked at — so a capture
// from the sheet, the share extension or a previous session simply vanished.
// `PendingCapture`'s own doc comment has promised a "review captures" badge
// since HER-34; this is it.
//
// The Home feed handles failures of captures made *in this session, on that
// screen*. This is the app-wide backstop for everything else, including rows
// left over from a previous launch.

import Foundation
import LuminaVaultShared
import Observation

@MainActor
@Observable
final class CaptureFailuresStore {
    private(set) var rows: [CaptureRowSnapshot] = []

    var count: Int { rows.count }
    var hasFailures: Bool { !rows.isEmpty }

    private let queue: CaptureQueueProtocol?
    private let drainer: CaptureDrainerHandle

    init(queue: CaptureQueueProtocol?, drainer: CaptureDrainerHandle) {
        self.queue = queue
        self.drainer = drainer
    }

    func refresh() async {
        guard let queue else { return }
        rows = (try? await queue.failed()) ?? []
    }

    /// Put one back in the queue. The payload is still on the row, so this is a
    /// real retry rather than asking the user to remember what they captured.
    func retry(_ row: CaptureRowSnapshot) async {
        guard let queue else { return }
        try? await queue.retry(id: row.id)
        await drainer.kick()
        await refresh()
    }

    func retryAll() async {
        guard let queue else { return }
        for row in rows {
            try? await queue.retry(id: row.id)
        }
        await drainer.kick()
        await refresh()
    }

    /// Deletes the capture. The only copy, so nothing calls this on the user's
    /// behalf.
    func discard(_ row: CaptureRowSnapshot) async {
        guard let queue else { return }
        try? await queue.delete(id: row.id)
        await refresh()
    }

    /// `CaptureDrainer` has its own fileprivate version of this; duplicating
    /// the two-line check is better than widening the access of a helper this
    /// file does not own.
    static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return value
    }

    /// What to call the row in a list. A voice note has no text of its own
    /// until it has been transcribed, which by definition has not happened.
    static func title(for row: CaptureRowSnapshot) -> String {
        switch row.kind {
        case .url:
            return row.urlString.flatMap { URL(string: $0)?.host } ?? row.urlString ?? "Link"
        case .voice:
            return "Voice note"
        case .photo:
            return Self.nonEmpty(row.captionText) ?? "Photo"
        case .text, .textFile:
            return Self.nonEmpty(row.captionText) ?? "Note"
        }
    }
}
