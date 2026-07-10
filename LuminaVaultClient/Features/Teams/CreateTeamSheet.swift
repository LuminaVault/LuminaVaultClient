import SwiftUI

struct CreateTeamSheet: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: TeamSpacesViewModel

    @State private var teamName = ""
    @State private var vaultName = "Shared Knowledge"
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Team") {
                    TextField("Team name", text: $teamName)
                        .textContentType(.organizationName)
                }
                Section("First shared vault") {
                    TextField("Vault name", text: $vaultName)
                }
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(.red)
                }
            }
            .navigationTitle("Create Team")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            isSubmitting = true
                            if await viewModel.createTeam(name: teamName, vaultName: vaultName) {
                                dismiss()
                            }
                            isSubmitting = false
                        }
                    }
                    .disabled(isSubmitting || teamName.trimmingCharacters(in: .whitespacesAndNewlines).count < 2)
                }
            }
        }
    }
}
