import SwiftUI

struct VaultMemberPermissionView: View {
    let member: VaultMemberSummary
    let viewModel: TeamSpacesViewModel

    @State private var role: String
    @State private var canUseAI: Bool

    init(member: VaultMemberSummary, viewModel: TeamSpacesViewModel) {
        self.member = member
        self.viewModel = viewModel
        _role = State(initialValue: member.role)
        _canUseAI = State(initialValue: member.canUseAI)
    }

    var body: some View {
        Form {
            Section(member.username) {
                Picker("Role", selection: $role) {
                    Text("Viewer").tag("viewer")
                    Text("Editor").tag("editor")
                    Text("Admin").tag("admin")
                }
                Toggle("AI access", isOn: $canUseAI)
            }
            Section {
                Button("Save permissions") {
                    Task { await viewModel.updateMember(member, role: role, canUseAI: canUseAI) }
                }
            }
        }
        .navigationTitle("Permissions")
    }
}
