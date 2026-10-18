// LuminaVaultClient/LuminaVaultClient/Services/AppGroup/ResurfaceWidgetSnapshot.swift
//
// The App Group file behind the "Today's memory" widget.
//
// The app writes it whenever Home's resurface queue loads or changes; the
// widget's timeline provider reads it, and the widget's Soon / Later / Never
// buttons drop the item they answered. It holds the whole short queue (Home
// fetches three), not just the head, so a widget answer can move on to the
// next memory without the widget process touching the network to find one.
//
// Compiled into BOTH the app and the widget extension. Keep it Foundation
// only: no LuminaVaultShared, no API types, no WidgetKit.

import Foundation
import OSLog

private nonisolated let log = Logger(subsystem: "com.luminavault", category: "resurface-widget")

/// One memory as the widget shows it.
nonisolated struct ResurfaceWidgetItem: Codable, Sendable, Equatable, Identifiable {
    let memoryId: UUID
    /// A short excerpt of the memory, as the server sent it.
    let snippet: String
    /// Why it is back, e.g. "Saved a year ago today".
    let why: String

    var id: UUID {
        memoryId
    }

    /// Where a tap on the widget goes: `NotificationRouter` opens this as
    /// the memory sheet.
    var deepLink: URL? {
        URL(string: "luminavault://memory/\(memoryId.uuidString.lowercased())")
    }
}

nonisolated struct ResurfaceWidgetSnapshot: Codable, Sendable, Equatable {
    /// Best first. The widget shows the first one.
    let items: [ResurfaceWidgetItem]
    let updatedAt: Date

    var current: ResurfaceWidgetItem? {
        items.first
    }

    static let empty = ResurfaceWidgetSnapshot(items: [], updatedAt: .distantPast)

    func removing(memoryId: UUID) -> ResurfaceWidgetSnapshot {
        ResurfaceWidgetSnapshot(items: items.filter { $0.memoryId != memoryId }, updatedAt: Date())
    }
}

nonisolated struct ResurfaceWidgetStore: Sendable {
    /// The widget kind, shared so the app reloads the right timeline.
    static let widgetKind = "ResurfaceWidget"
    static let fileName = "resurfaceWidgetSnapshot.json"

    /// The App Group file. A test points `fileURL` somewhere temporary.
    static let shared = ResurfaceWidgetStore(
        fileURL: FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: SharedAppGroup.identifier)?
            .appendingPathComponent(fileName)
    )

    let fileURL: URL?

    /// Best-effort, like `WidgetSnapshotStore`: a widget that misses an
    /// update shows yesterday's memory, which is better than failing Home.
    func write(_ snapshot: ResurfaceWidgetSnapshot) {
        guard let fileURL else {
            log.error("App Group container unavailable — resurface snapshot not written")
            return
        }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            // .atomic so the widget never reads a half-written file.
            try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            log.error("resurface snapshot write failed: \(error.localizedDescription)")
        }
    }

    /// `.empty` when there is no file yet or it cannot be read, so the
    /// widget always has something to render.
    func read() -> ResurfaceWidgetSnapshot {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return .empty }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(ResurfaceWidgetSnapshot.self, from: data)
        } catch {
            log.error("resurface snapshot decode failed: \(error.localizedDescription)")
            return .empty
        }
    }

    /// The widget answered this one; show the next.
    func remove(memoryId: UUID) {
        let snapshot = read()
        guard snapshot.items.contains(where: { $0.memoryId == memoryId }) else { return }
        write(snapshot.removing(memoryId: memoryId))
    }

    /// Sign-out teardown: the file outlives the session and renders on the
    /// home screen, so one user's memory must not greet the next.
    func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
