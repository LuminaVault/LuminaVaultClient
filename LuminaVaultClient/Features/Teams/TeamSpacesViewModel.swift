import Foundation

@Observable
@MainActor
final class TeamSpacesViewModel {
    private(set) var teams: [TeamSpaceSummary] = []
    private(set) var vaults: [SharedVaultSummary] = []
    private(set) var members: [VaultMemberSummary] = []
    private(set) var invitations: [TeamInvitationSummary] = []
    private(set) var selectedVaultID: UUID?
    private(set) var isLoading = false
    var errorMessage: String?

    private let client: TeamHTTPClient
    private let store: ActiveVaultStore
    private let userIDProvider: @MainActor () -> UUID?

    init(
        client: TeamHTTPClient,
        store: ActiveVaultStore,
        userIDProvider: @escaping @MainActor () -> UUID? = { nil }
    ) {
        self.client = client
        self.store = store
        self.userIDProvider = userIDProvider
    }

    var selectedVault: SharedVaultSummary? {
        vaults.first { $0.id == selectedVaultID } ?? vaults.first(where: \.isPersonal)
    }

    private enum LoadedSpaces: Sendable {
        case teams([TeamSpaceSummary])
        case vaults([SharedVaultSummary])
    }

    private enum LoadedRoster: Sendable {
        case members([VaultMemberSummary])
        case invitations([TeamInvitationSummary])
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            // A task group, not `async let`: see HomeGlanceViewModel.load().
            try await withThrowingTaskGroup(of: LoadedSpaces.self) { group in
                group.addTask { @MainActor in .teams(try await self.client.teams()) }
                group.addTask { @MainActor in .vaults(try await self.client.vaults()) }
                for try await item in group {
                    switch item {
                    case .teams(let value): teams = value
                    case .vaults(let value): vaults = value
                    }
                }
            }
            await store.restore(for: userIDProvider())
            let stored = await store.selectedVaultID()
            let chosen = vaults.contains(where: { $0.id == stored }) ? stored : vaults.first(where: \.isPersonal)?.id
            await select(chosen)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ id: UUID?) async {
        selectedVaultID = id
        await store.select(id, for: userIDProvider())
    }

    func createTeam(name: String, vaultName: String) async -> Bool {
        do {
            let team = try await client.createTeam(name: name)
            let vault = try await client.createVault(teamID: team.id, name: vaultName)
            await load()
            await select(vault.id)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func loadMembers() async {
        guard let vault = selectedVault, !vault.isPersonal, let teamID = vault.teamID else {
            members = []
            invitations = []
            return
        }
        do {
            // A task group, not `async let`: see HomeGlanceViewModel.load().
            let vaultID = vault.id
            try await withThrowingTaskGroup(of: LoadedRoster.self) { group in
                group.addTask { @MainActor in .members(try await self.client.members(vaultID: vaultID)) }
                group.addTask { @MainActor in .invitations(try await self.client.invitations(teamID: teamID)) }
                for try await item in group {
                    switch item {
                    case .members(let value): members = value
                    case .invitations(let value): invitations = value
                    }
                }
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func updateMember(_ member: VaultMemberSummary, role: String, canUseAI: Bool) async {
        guard let vault = selectedVault else { return }
        do {
            let updated = try await client.updateMember(vaultID: vault.id, userID: member.userID,
                                                        role: role, canUseAI: canUseAI)
            if let index = members.firstIndex(where: { $0.id == updated.id }) {
                members[index] = updated
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func invite(email: String, role: String, canUseAI: Bool) async -> Bool {
        guard let vault = selectedVault, let teamID = vault.teamID else { return false }
        do {
            _ = try await client.invite(teamID: teamID, email: email, vaultID: vault.id,
                                        role: role, canUseAI: canUseAI)
            invitations = try await client.invitations(teamID: teamID)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func resendInvitation(_ invitation: TeamInvitationSummary) async {
        do {
            let updated = try await client.resendInvitation(teamID: invitation.teamID, invitationID: invitation.id)
            if let index = invitations.firstIndex(where: { $0.id == updated.id }) {
                invitations[index] = updated
            }
        } catch { errorMessage = error.localizedDescription }
    }

    func revokeInvitation(_ invitation: TeamInvitationSummary) async {
        do {
            try await client.revokeInvitation(teamID: invitation.teamID, invitationID: invitation.id)
            invitations.removeAll { $0.id == invitation.id }
        } catch { errorMessage = error.localizedDescription }
    }

    func removeMember(_ member: VaultMemberSummary) async {
        guard let vault = selectedVault else { return }
        do {
            try await client.removeMember(vaultID: vault.id, userID: member.userID)
            members.removeAll { $0.id == member.id }
        } catch { errorMessage = error.localizedDescription }
    }

    func archiveSelectedTeam() async -> Bool {
        guard let teamID = selectedVault?.teamID else { return false }
        do {
            try await client.archive(teamID: teamID)
            await select(nil)
            await load()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
