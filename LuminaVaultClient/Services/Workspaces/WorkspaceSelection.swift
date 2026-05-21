// LuminaVaultClient/LuminaVaultClient/Services/Workspaces/WorkspaceSelection.swift
//
// HER-261 — shared @Observable holding the active Workspace (= Space)
// ID. Persisted to UserDefaults so the choice survives launches. Each
// OS-Shell surface that should scope by workspace observes this and
// passes the value as `?workspace=` to the server.

import Foundation
import SwiftUI

@Observable
@MainActor
final class WorkspaceSelection {
    /// `nil` = All workspaces (the "global" view).
    var activeWorkspaceID: UUID? {
        didSet { persist() }
    }

    private let key = "lv.workspace.activeID"

    init() {
        if let raw = UserDefaults.standard.string(forKey: key),
           let uuid = UUID(uuidString: raw) {
            activeWorkspaceID = uuid
        } else {
            activeWorkspaceID = nil
        }
    }

    private func persist() {
        if let id = activeWorkspaceID {
            UserDefaults.standard.set(id.uuidString, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }
}
