// LuminaVaultClient/LuminaVaultClient/Services/Notifications/NoteReminderScheduler.swift
//
// HER-Notes — local reminders for smart-todo notes. A note with `isTodo`,
// a `dueAt`, and not yet `done` schedules a local notification at its due
// time (keyed by the note's vault-file id). Editing reschedules; completing
// or deleting cancels. Local-only (UNCalendarNotificationTrigger) — no server
// push needed since the due time is known on-device.

import Foundation
import UserNotifications

/// Serialises reminder scheduling so concurrent saves on different notes can't
/// race the notification center. Keyed by the note's vault-file UUID.
actor NoteReminderScheduler {
    static let shared = NoteReminderScheduler()
    private init() {}

    private func requestID(_ noteID: UUID) -> String { "note-due-\(noteID.uuidString)" }

    /// Cancels any existing reminder for the note, then schedules a fresh one
    /// when the note is an open todo with a future due date. No-op (cancel
    /// only) when the todo is done, undated, or the due time has passed.
    func reschedule(noteID: UUID, title: String, dueAt: Date?, done: Bool) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [requestID(noteID)])

        guard let dueAt, !done, dueAt > Date() else { return }

        // Best-effort permission. If the user declined, `add` silently fails.
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        }

        let content = UNMutableNotificationContent()
        content.title = "Todo due"
        content.body = title
        content.sound = .default

        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: dueAt,
        )
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let req = UNNotificationRequest(
            identifier: requestID(noteID), content: content, trigger: trigger,
        )
        try? await center.add(req)
    }

    /// Cancels a note's pending reminder (on completion or delete).
    func cancel(noteID: UUID) async {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [requestID(noteID)])
    }
}
