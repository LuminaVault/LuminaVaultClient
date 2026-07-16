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
    @State private var teamViewModel: TeamSpacesViewModel
    let vm: SpacesViewModel
    let vaultClient: any VaultClientProtocol
    let memoryClient: any MemoryQueryClientProtocol
    let memoryDetailClient: any MemoryClientProtocol
    let uploadClient: any VaultUploadClientProtocol

    init(vm: SpacesViewModel, vaultClient: any VaultClientProtocol,
         memoryClient: any MemoryQueryClientProtocol, memoryDetailClient: any MemoryClientProtocol,
         uploadClient: any VaultUploadClientProtocol, teamClient: TeamHTTPClient,
         activeVaultStore: ActiveVaultStore,
         currentUserIDProvider: @escaping @MainActor () -> UUID?)
    {
        self.vm = vm
        self.vaultClient = vaultClient
        self.memoryClient = memoryClient
        self.memoryDetailClient = memoryDetailClient
        self.uploadClient = uploadClient
        _teamViewModel = State(initialValue: TeamSpacesViewModel(
            client: teamClient,
            store: activeVaultStore,
            userIDProvider: currentUserIDProvider
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            TeamVaultSwitcher(viewModel: teamViewModel) {
                await vm.load()
            }
            Divider()
            SpacesListView(
                vm: vm,
                vaultClient: vaultClient,
                memoryClient: memoryClient,
                memoryDetailClient: memoryDetailClient,
                uploadClient: uploadClient
            )
        }
        .task { await teamViewModel.load() }
        .navigationTitle("Team Spaces")
    }
}
