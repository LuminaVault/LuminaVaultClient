import SwiftUI

struct TeamVaultSwitcher: View {
    @Bindable var viewModel: TeamSpacesViewModel
    let onSelectionChanged: () async -> Void

    @State private var showingCreateTeam = false
    @State private var showingManagement = false

    var body: some View {
        HStack {
            Menu {
                ForEach(viewModel.vaults) { vault in
                    Button {
                        Task {
                            await viewModel.select(vault.id)
                            await onSelectionChanged()
                        }
                    } label: {
                        Label(vault.name, systemImage: vault.isPersonal ? "person.crop.circle" : "person.3")
                    }
                }
                Divider()
                Button("Create Team", systemImage: "person.3.sequence") {
                    showingCreateTeam = true
                }
            } label: {
                Label(viewModel.selectedVault?.name ?? "Personal Vault",
                      systemImage: viewModel.selectedVault?.isPersonal == false ? "person.3.fill" : "person.crop.circle")
                    .font(.headline)
            }
            .accessibilityHint("Choose a personal or team vault")

            Spacer()

            if let vault = viewModel.selectedVault, !vault.isPersonal {
                Text(vault.role.capitalized)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
                if vault.canUseAI {
                    Image(systemName: "sparkles")
                        .accessibilityLabel("AI access enabled")
                }
                if vault.canAdmin {
                    Button("Manage Team Vault", systemImage: "person.3") {
                        showingManagement = true
                    }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .padding(.horizontal)
        .frame(minHeight: 44)
        .sheet(isPresented: $showingCreateTeam) {
            CreateTeamSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingManagement) {
            TeamVaultManagementView(viewModel: viewModel)
        }
    }
}
