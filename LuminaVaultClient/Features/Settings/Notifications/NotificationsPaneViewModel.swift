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

    private let client: APNSPrefsClientProtocol

    init(client: APNSPrefsClientProtocol) {
        self.client = client
    }

    func load() async {
        state = .loading
        do {
            let prefs = try await client.get()
            chatEnabled = prefs.chatEnabled
            nudgeEnabled = prefs.nudgeEnabled
            digestEnabled = prefs.digestEnabled
            state = .loaded
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    /// Phase 1 added `approval` and `runCompleted` to `APNSCategory`, and
    /// server migration M119 added the columns that
    /// `APNSNotificationService.isCategorySuppressed` already reads. What is
    /// missing is the contract in between: `APNSCategoryPrefsResponse` and
    /// `APNSCategoryPrefsPutRequest` (LuminaVaultShared) carry no field for
    /// either category, so `GET/PUT /v1/me/apns-categories` can neither
    /// report nor change them. Until that contract ships, the pane shows the
    /// two Hermes-run categories as the always-on state the server actually
    /// applies, rather than a switch that silently does nothing.
    static let editableCategories: [APNSCategory] = [.digest, .nudge, .chat]

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
        case .approval, .runCompleted:
            // Not writable over the current contract — see above. Returning
            // rather than sending a body the server would ignore keeps the
            // UI honest about what actually changed.
            return
        }
        do {
            let prefs = try await client.put(body)
            chatEnabled = prefs.chatEnabled
            nudgeEnabled = prefs.nudgeEnabled
            digestEnabled = prefs.digestEnabled
        } catch {
            state = .failed(Self.message(for: error))
        }
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
