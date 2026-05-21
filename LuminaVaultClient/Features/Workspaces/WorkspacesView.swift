// LuminaVaultClient/LuminaVaultClient/Features/Workspaces/WorkspacesView.swift
//
// HER-249 — Workspaces evolves Spaces into the OS-level context container
// (sessions / tasks / skills / files bound to a single workspace). v1
// ships the nav re-skin only; the actual binding lives in follow-up
// tickets. This view wraps SpacesListView and exposes a workspace-aware
// header so downstream surfaces can filter by active workspace later.

import LuminaVaultShared
import SwiftUI

struct WorkspacesView: View {
    let vm: SpacesViewModel
    let vaultClient: any VaultClientProtocol
    let memoryClient: any MemoryQueryClientProtocol

    var body: some View {
        SpacesListView(vm: vm, vaultClient: vaultClient, memoryClient: memoryClient)
            .navigationTitle("Workspaces")
    }
}
