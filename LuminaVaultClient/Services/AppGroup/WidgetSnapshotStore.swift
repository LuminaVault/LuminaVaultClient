// LuminaVaultClient/LuminaVaultClient/Services/AppGroup/WidgetSnapshotStore.swift
//
// The App Group file the widget reads.
//
// A widget extension is a separate process with its own sandbox: it cannot
// read the host app's keychain, so it has no bearer token and cannot make an
// authenticated API call. It also gets a very short execution budget. So the
// widget never touches the network — the app writes a small snapshot here on
// capture/load, and the timeline provider reads it.
//
// This file is compiled into BOTH targets (main app + widget extension). Keep
// it dependency-free: Foundation only, no LuminaVaultShared, no API types.

import Foundation
import OSLog

private nonisolated(unsafe) let log = Logger(subsystem: "com.luminavault", category: "widget-snapshot")

/// One row rendered by the widget.
struct WidgetCaptureItem: Codable, Sendable, Identifiable, Equatable {
    let id: UUID
    let title: String
    let createdAt: Date
    /// Set when the capture carried a geo anchor.
    let placeName: String?

    init(id: UUID, title: String, createdAt: Date, placeName: String? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.placeName = placeName
    }
}

/// What the app publishes for the widget to render.
struct WidgetSnapshot: Codable, Sendable, Equatable {
    /// Newest first, already trimmed to `maxItems`.
    let items: [WidgetCaptureItem]
    /// Total memories the user has, for the count line. Not `items.count` —
    /// items is a truncated window.
    let totalCount: Int
    let updatedAt: Date

    static let empty = WidgetSnapshot(items: [], totalCount: 0, updatedAt: .distantPast)
}

enum WidgetSnapshotStore {
    /// A widget shows a handful of rows at most; writing more is wasted I/O on
    /// every capture.
    static let maxItems = 5

    static let fileName = "widgetSnapshot.json"

    private static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedAppGroup.identifier)?
            .appendingPathComponent(fileName)
    }

    /// Called by the app. Best-effort: a widget that misses an update shows
    /// slightly stale data, which is strictly better than failing a capture.
    static func write(_ snapshot: WidgetSnapshot) {
        guard let fileURL else {
            log.error("App Group container unavailable — widget snapshot not written")
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            // .atomic so the widget never reads a half-written file.
            try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            log.error("widget snapshot write failed: \(error.localizedDescription)")
        }
    }

    /// Called by the widget's timeline provider. Returns `.empty` rather than
    /// nil so the widget always has something to render.
    static func read() -> WidgetSnapshot {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else {
            return .empty
        }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(WidgetSnapshot.self, from: data)
        } catch {
            log.error("widget snapshot decode failed: \(error.localizedDescription)")
            return .empty
        }
    }

    /// Sign-out teardown. The snapshot sits in a shared container that
    /// outlives the session, so leaving one user's capture titles on the home
    /// screen would expose them to whoever signs in next — same reasoning as
    /// clearing the Spotlight index.
    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
