// LuminaVaultClient/LuminaVaultClient/Features/Settings/Hermes/HermesMirrorCardViewModel.swift
//
// What actually came across from the user's Hermes.
//
// Before this, iOS had no caller for `mirror/status` or `mirror/sync` at all:
// a user could link their Hermes, see a green "Connected" badge, and have no
// way to learn that nothing had been imported — or to ask for a sync. The
// counts are the whole point of the mirror, and they were invisible.

import Foundation
import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class HermesMirrorCardViewModel {
    enum State: Equatable {
        case loading
        case loaded(HermesMirrorStatusDTO)
        case failed(String)
    }

    var state: State = .loading
    var isSyncing = false
    /// Set after a manual sync so the card can say what changed rather than
    /// silently re-rendering the same numbers.
    var lastSyncMessage: String?

    private let client: any HermesMirrorClientProtocol

    init(client: any HermesMirrorClientProtocol) {
        self.client = client
    }

    func load() async {
        if case .loaded = state {} else { state = .loading }
        do {
            state = .loaded(try await client.status())
        } catch {
            state = .failed(Self.message(for: error))
        }
    }

    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        let before = currentStatus
        do {
            let after = try await client.sync(scope: nil)
            state = .loaded(after)
            lastSyncMessage = Self.summary(before: before, after: after)
        } catch {
            lastSyncMessage = nil
            state = .failed(Self.message(for: error))
        }
    }

    var currentStatus: HermesMirrorStatusDTO? {
        if case let .loaded(status) = state { return status }
        return nil
    }

    /// A sync that changes nothing is the symptom this card exists to expose,
    /// so say so plainly instead of leaving the user to compare numbers.
    static func summary(before: HermesMirrorStatusDTO?, after: HermesMirrorStatusDTO) -> String {
        let skills = after.skillsCount - (before?.skillsCount ?? 0)
        let jobs = after.jobsCount - (before?.jobsCount ?? 0)
        if after.skillsCount == 0, after.jobsCount == 0 {
            return "Nothing came across. Check that the gateway URL and key are right."
        }
        if skills == 0, jobs == 0 {
            return "Already up to date."
        }
        var parts: [String] = []
        if skills != 0 { parts.append("\(skills > 0 ? "+" : "")\(skills) skills") }
        if jobs != 0 { parts.append("\(jobs > 0 ? "+" : "")\(jobs) jobs") }
        return parts.joined(separator: ", ")
    }

    static func message(for error: Error) -> String {
        if let apiError = error as? APIError {
            switch apiError {
            case .unauthorized: return "Session expired — sign in again."
            case .networkFailure, .tlsPinningFailed: return "You're offline."
            default: return apiError.userFacingMessage
            }
        }
        return "Couldn't read the mirror status."
    }
}

extension HermesMirrorStatusDTO {
    /// Whether anything at all has been mirrored. `lastStatus == .ok` with
    /// zero counts is the exact shape of a Hermes that was linked but never
    /// actually read, so the card must not treat "ok" as "fine".
    var hasMirroredAnything: Bool {
        skillsCount > 0 || jobsCount > 0 || vaultFilesCount > 0 || sessionsImported > 0
    }

    var vaultSummary: String {
        switch vaultState {
        case .absent: "No vault found"
        case .detected: vaultPath ?? "Found"
        case .created: "Created by LuminaVault"
        case .imported: "\(vaultFilesCount) files imported"
        }
    }
}
