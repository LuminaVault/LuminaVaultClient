import Foundation

@Observable
@MainActor
final class TeamSpacesViewModel {
    private(set) var teams: [TeamSpaceSummary] = []
    private(set) var vaults: [SharedVaultSummary] = []
    private(set) var members: [VaultMemberSummary] = []
    private(set) var selectedVaultID: UUID?
    private(set) var isLoading = false
    var errorMessage: String?

    private let client: TeamHTTPClient
    private let store: ActiveVaultStore

    init(client: TeamHTTPClient, store: ActiveVaultStore) {
        self.client = client
        self.store = store
    }

    var selectedVault: SharedVaultSummary? {
        vaults.first { $0.id == selectedVaultID } ?? vaults.first(where: \.isPersonal)
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let loadedTeams = client.teams()
            async let loadedVaults = client.vaults()
            teams = try await loadedTeams
            vaults = try await loadedVaults
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
        await store.select(id, for: nil)
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
        guard let vault = selectedVault, !vault.isPersonal else { members = []; return }
        do { members = try await client.members(vaultID: vault.id) }
        catch { errorMessage = error.localizedDescription }
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
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
