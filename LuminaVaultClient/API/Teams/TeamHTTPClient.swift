import Foundation

struct TeamHTTPClient: Sendable {
    let client: BaseHTTPClient

    func teams() async throws -> [TeamSpaceSummary] {
        try await client.execute(TeamEndpoints.ListTeams())
    }

    func vaults() async throws -> [SharedVaultSummary] {
        try await client.execute(TeamEndpoints.ListVaults())
    }

    func createTeam(name: String) async throws -> TeamSpaceSummary {
        try await client.execute(TeamEndpoints.CreateTeam(name: name))
    }

    func createVault(teamID: UUID, name: String) async throws -> SharedVaultSummary {
        try await client.execute(TeamEndpoints.CreateVault(teamID: teamID, name: name))
    }

    func members(vaultID: UUID) async throws -> [VaultMemberSummary] {
        try await client.execute(TeamEndpoints.Members(vaultID: vaultID))
    }

    func updateMember(vaultID: UUID, userID: UUID, role: String, canUseAI: Bool) async throws -> VaultMemberSummary {
        try await client.execute(TeamEndpoints.UpdateMember(vaultID: vaultID, userID: userID,
                                                            role: role, canUseAI: canUseAI))
    }

    func invite(teamID: UUID, email: String, vaultID: UUID, role: String, canUseAI: Bool) async throws -> TeamInvitationSummary {
        try await client.execute(TeamEndpoints.Invite(teamID: teamID, email: email,
                                                      vaultGrants: [vaultID.uuidString: .init(role: role, canUseAI: canUseAI)]))
    }

    func activity(vaultID: UUID) async throws -> [VaultActivitySummary] {
        try await client.execute(TeamEndpoints.Activity(vaultID: vaultID))
    }
}
