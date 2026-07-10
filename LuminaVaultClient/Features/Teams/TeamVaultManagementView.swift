import SwiftUI

struct TeamVaultManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var viewModel: TeamSpacesViewModel

    @State private var inviteEmail = ""
    @State private var inviteRole = "viewer"
    @State private var inviteAI = false
    @State private var isInviting = false
    @State private var confirmingArchive = false

    var body: some View {
        NavigationStack {
            List {
                Section("Invite member") {
                    TextField("Email", text: $inviteEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                    Picker("Role", selection: $inviteRole) {
                        Text("Viewer").tag("viewer")
                        Text("Editor").tag("editor")
                        Text("Admin").tag("admin")
                    }
                    Toggle("AI access", isOn: $inviteAI)
                    Button("Send invitation", systemImage: "paperplane") {
                        Task {
                            isInviting = true
                            if await viewModel.invite(email: inviteEmail, role: inviteRole, canUseAI: inviteAI) {
                                inviteEmail = ""
                            }
                            isInviting = false
                        }
                    }
                    .disabled(isInviting || !inviteEmail.contains("@"))
                }

                Section("Members") {
                    ForEach(viewModel.members) { member in
                        NavigationLink(value: member) {
                            VStack(alignment: .leading) {
                                Text(member.username).font(.headline)
                                Text(member.role.capitalized + (member.canUseAI ? " · AI" : ""))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .swipeActions {
                            Button("Remove", systemImage: "person.crop.circle.badge.minus", role: .destructive) {
                                Task { await viewModel.removeMember(member) }
                            }
                        }
                    }
                }

                Section("Team lifecycle") {
                    Button("Archive team", systemImage: "archivebox", role: .destructive) {
                        confirmingArchive = true
                    }
                }

                if let error = viewModel.errorMessage {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(viewModel.selectedVault?.name ?? "Team Vault")
            .navigationDestination(for: VaultMemberSummary.self) { member in
                VaultMemberPermissionView(member: member, viewModel: viewModel)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await viewModel.loadMembers() }
            .confirmationDialog(
                "Archive this team?",
                isPresented: $confirmingArchive,
                titleVisibility: .visible
            ) {
                Button("Archive for 30 days", role: .destructive) {
                    Task {
                        if await viewModel.archiveSelectedTeam() { dismiss() }
                    }
                }
            } message: {
                Text("Writes and AI access stop immediately. The owner can restore the team for 30 days before permanent deletion.")
            }
        }
    }
}
