// LuminaVaultClient/LuminaVaultClient/Features/Settings/Notifications/NotificationsPaneViewModel.swift
//
// HER-179 — Settings → Notifications pane. Per-category toggles backed
// by GET/PUT /v1/me/apns-categories.

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

    private let client: APNSPrefsClientProtocol

    init(client: APNSPrefsClientProtocol) {
        self.client = client
    }

    func load() async {
        state = .loading
        do {
            let prefs = try await client.get()
            apply(prefs)
            state = .loaded
        } catch {
            state = .failed(Self.message(for: error))
        }
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
