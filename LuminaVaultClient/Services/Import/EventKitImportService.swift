// LuminaVaultClient/.../Services/Import/EventKitImportService.swift
//
// HER-105 "Feed Your Brain" (P2) — pulls Reminders + Calendar events via
// EventKit and renders each to a markdown note. PURE data layer: it produces
// `ImportableNote`s; the import UI uploads them via `VaultUploadClientProtocol`
// (path under the `imported` Space, processed=false) and then registers the
// returned vault-file ids with `POST /v1/import/files` so they flow through
// Smart Import categorize → approve → compile like links.
//
// NOTE: needs an Xcode build to verify EventKit API/availability. Targets the
// iOS 17+ full-access APIs (`requestFullAccessTo…`).

import EventKit
import Foundation

/// A vault-ready note rendered from a device source.
struct ImportableNote: Sendable {
    let fileName: String       // e.g. "reminder-call-dentist-3f9a2b1c.md"
    let markdown: String
    let contentType: String    // "text/markdown"
}

actor EventKitImportService {
    private let store = EKEventStore()

    enum ImportError: Error { case accessDenied }

    /// Fetch incomplete reminders → markdown notes. Throws `.accessDenied` if
    /// the user declines permission.
    func reminders() async throws -> [ImportableNote] {
        guard try await store.requestFullAccessToReminders() else { throw ImportError.accessDenied }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil, ending: nil, calendars: nil,
        )
        let reminders: [EKReminder] = await withCheckedContinuation { cont in
            store.fetchReminders(matching: predicate) { cont.resume(returning: $0 ?? []) }
        }
        return reminders.map { Self.note(from: $0) }
    }

    /// Fetch calendar events in a window (default: last 30 → next 90 days) →
    /// markdown notes.
    func events(daysBack: Int = 30, daysForward: Int = 90) async throws -> [ImportableNote] {
        guard try await store.requestFullAccessToEvents() else { throw ImportError.accessDenied }
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -daysBack, to: now) ?? now
        let end = Calendar.current.date(byAdding: .day, value: daysForward, to: now) ?? now
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map { Self.note(from: $0) }
    }

    // MARK: - Rendering

    private static let dateFmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f
    }()

    private static func note(from r: EKReminder) -> ImportableNote {
        let title = r.title ?? "Reminder"
        var md = "# Reminder: \(title)\n\n"
        if let due = r.dueDateComponents?.date {
            md += "Due: \(dateFmt.string(from: due))\n"
        }
        if r.priority > 0 { md += "Priority: \(r.priority)\n" }
        if let list = r.calendar?.title { md += "List: \(list)\n" }
        if let notes = r.notes, !notes.isEmpty { md += "\n\(notes)\n" }
        return ImportableNote(fileName: fileName("reminder", title), markdown: md, contentType: "text/markdown")
    }

    private static func note(from e: EKEvent) -> ImportableNote {
        let title = e.title ?? "Event"
        var md = "# Event: \(title)\n\n"
        if let start = e.startDate { md += "Start: \(dateFmt.string(from: start))\n" }
        if let end = e.endDate { md += "End: \(dateFmt.string(from: end))\n" }
        if let loc = e.location, !loc.isEmpty { md += "Location: \(loc)\n" }
        if let cal = e.calendar?.title { md += "Calendar: \(cal)\n" }
        if let notes = e.notes, !notes.isEmpty { md += "\n\(notes)\n" }
        return ImportableNote(fileName: fileName("event", title), markdown: md, contentType: "text/markdown")
    }

    private static func fileName(_ kind: String, _ title: String) -> String {
        var slug = ""
        var lastDash = false
        for ch in title.lowercased() {
            if ch.isLetter || ch.isNumber { slug.append(ch); lastDash = false }
            else if !lastDash { slug.append("-"); lastDash = true }
        }
        slug = String(slug.trimmingCharacters(in: CharacterSet(charactersIn: "-")).prefix(40))
        let suffix = UUID().uuidString.prefix(8).lowercased()
        return "\(kind)-\(slug.isEmpty ? "item" : slug)-\(suffix).md"
    }
}
