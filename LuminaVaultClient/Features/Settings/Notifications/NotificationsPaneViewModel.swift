// LuminaVaultClient/LuminaVaultClient/Features/Settings/Notifications/NotificationsPaneViewModel.swift
//
// HER-179 — Settings → Notifications pane. Per-category toggles backed
// by GET/PUT /v1/me/apns-categories.
//
// The pre-meeting brief is the one opt-in among them: off unless turned on,
// and not an `APNSCategory` case in Shared, so it has its own setter. It
// only works with calendar sync on, so the pane also reads whether it is.

import Foundation
import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class NotificationsPaneViewModel {
    enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var state: LoadState = .loading
    var chatEnabled: Bool = true
    var nudgeEnabled: Bool = true
    var digestEnabled: Bool = true
    var approvalEnabled: Bool = true
    var runCompletedEnabled: Bool = true
    /// Opt-in: false until the user turns it on (and when the server is
    /// too old to say).
    var meetingBriefEnabled: Bool = false
    /// Whether the calendar syncs, which meeting briefs need.
    private(set) var calendarReadiness: CalendarSyncReadiness = .unknown

    private let client: APNSPrefsClientProtocol
    private let calendarReadinessChecker: (any CalendarSyncReadinessChecking)?

    init(client: APNSPrefsClientProtocol, calendarReadiness: (any CalendarSyncReadinessChecking)? = nil) {
        self.client = client
        self.calendarReadinessChecker = calendarReadiness
    }

    func load() async {
        state = .loading
        do {
            let prefs = try await client.get()
            apply(prefs)
            state = .loaded
        } catch {
            state = .failed(Self.message(for: error))
            return
        }
        await refreshCalendarReadiness()
    }

    /// Re-read on every appearance too: the way to fix it is a screen away
    /// (Data Access, or iOS Settings), and the pane should notice the return.
    func refreshCalendarReadiness() async {
        guard let calendarReadinessChecker else { return }
        calendarReadiness = await calendarReadinessChecker.readiness()
    }

    /// Calendar sync is known to be off, so a brief cannot go out yet.
    var meetingBriefNeedsCalendar: Bool {
        calendarReadiness == .consentOff || calendarReadiness == .systemAccessOff
    }

    /// The opt-in pre-meeting brief. Same optimistic write and rollback as
    /// `toggle`.
    func setMeetingBrief(_ value: Bool) async {
        meetingBriefEnabled = value
        await write(APNSCategoryPrefsPutRequest(meetingBriefEnabled: value))
    }

    /// Every category the server can report and write. Phase 1's `approval`
    /// and `runCompleted` joined the list once Shared 5.6.0 gave
    /// `APNSCategoryPrefs{Response,PutRequest}` fields for the M119 columns
    /// that `isCategorySuppressed` had been reading all along.
    static let editableCategories: [APNSCategory] = [.digest, .nudge, .chat, .approval, .runCompleted]

    func isEditable(_ category: APNSCategory) -> Bool {
        Self.editableCategories.contains(category)
    }

    func toggle(_ category: APNSCategory, value: Bool) async {
        let body: APNSCategoryPrefsPutRequest
        switch category {
        case .chat:
            chatEnabled = value
            body = .init(chatEnabled: value)
        case .nudge:
            nudgeEnabled = value
            body = .init(nudgeEnabled: value)
        case .digest:
            digestEnabled = value
            body = .init(digestEnabled: value)
        case .approval:
            approvalEnabled = value
            body = .init(approvalEnabled: value)
        case .runCompleted:
            runCompletedEnabled = value
            body = .init(runCompletedEnabled: value)
        }
        await write(body)
    }

    private func write(_ body: APNSCategoryPrefsPutRequest) async {
        do {
            // The response is authoritative: the put is sparse, so this is
            // also how the untouched categories stay in sync.
            apply(try await client.put(body))
        } catch {
            // The optimistic write above has to be rolled back or the switch
            // shows a setting the server never accepted.
            await load()
            state = .failed(Self.message(for: error))
        }
    }

    private func apply(_ prefs: APNSCategoryPrefsResponse) {
        chatEnabled = prefs.chatEnabled
        nudgeEnabled = prefs.nudgeEnabled
        digestEnabled = prefs.digestEnabled
        approvalEnabled = prefs.approvalEnabled
        runCompletedEnabled = prefs.runCompletedEnabled
        meetingBriefEnabled = prefs.isMeetingBriefEnabled
    }

    private static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized: return "Session expired — sign in again."
            case .networkFailure: return "Network unavailable."
            default: return "Couldn't load notification preferences."
            }
        }
        return "Couldn't load notification preferences."
    }
}
