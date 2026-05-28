// LuminaVaultClient/LuminaVaultClient/Features/Reflect/ReflectViewModel.swift
//
// HER-194 — feeds the Reflect tab's recent-reflections list. The
// per-run state machine lives on `ReflectionRunner`; this VM owns the
// list state only so the runner can be recreated cheaply per modal
// without losing the feed.

import Foundation
import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class ReflectViewModel {
    enum FeedState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    var feedState: FeedState = .loading
    var recentFiles: [VaultFileDTO] = []

    private let vaultClient: VaultClientProtocol

    init(vaultClient: VaultClientProtocol) {
        self.vaultClient = vaultClient
    }

    func refreshRecent() async {
        feedState = .loading
        do {
            // HER-194 — server `prefix=` param doesn't exist yet; use `q=`
            // substring match against the `reflections/` folder prefix.
            // Follow-up server ticket can tighten this.
            let response = try await vaultClient.listFiles(
                spaceSlug: nil,
                q: "reflections/",
                before: nil,
                after: nil,
                limit: 10,
            )
            recentFiles = response.files.sorted {
                ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
            feedState = .loaded
        } catch {
            feedState = .failed(Self.message(for: error))
        }
    }

    private static func message(for error: Error) -> String {
        if let api = error as? APIError {
            switch api {
            case .unauthorized: return "Session expired — sign in again."
            case .networkFailure: return "Network unavailable."
            default: return "Couldn't load recent reflections."
            }
        }
        return "Couldn't load recent reflections."
    }
}
