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

    func toggle(_ category: APNSCategory, value: Bool) async {
        switch category {
        case .chat: chatEnabled = value
        case .nudge: nudgeEnabled = value
        case .digest: digestEnabled = value
        }
        let body: APNSCategoryPrefsPutRequest
        switch category {
        case .chat: body = .init(chatEnabled: value)
        case .nudge: body = .init(nudgeEnabled: value)
        case .digest: body = .init(digestEnabled: value)
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
