import Foundation

enum TeamEndpoints {
    struct ListTeams: Endpoint {
        typealias Response = [TeamSpaceSummary]
        let path = "/v1/teams"
        let method = HTTPMethod.get
    }

    struct CreateTeam: Endpoint {
        typealias Response = TeamSpaceSummary
        let name: String
        let path = "/v1/teams"
        let method = HTTPMethod.post
        var body: (any Encodable)? {
            Body(name: name)
        }

        private struct Body: Encodable { let name: String }
    }

    struct ListVaults: Endpoint {
        typealias Response = [SharedVaultSummary]
        let path = "/v1/vaults"
        let method = HTTPMethod.get
    }

    struct CreateVault: Endpoint {
        typealias Response = SharedVaultSummary
        let teamID: UUID
        let name: String
        var path: String {
            "/v1/teams/\(teamID)/vaults"
        }

        let method = HTTPMethod.post
        var body: (any Encodable)? {
            Body(name: name)
        }

        private struct Body: Encodable { let name: String }
    }

    struct Members: Endpoint {
        typealias Response = [VaultMemberSummary]
        let vaultID: UUID
        var path: String {
            "/v1/vaults/\(vaultID)/members"
        }

        let method = HTTPMethod.get
    }

    struct UpdateMember: Endpoint {
        typealias Response = VaultMemberSummary
        let vaultID: UUID
        let userID: UUID
        let role: String
        let canUseAI: Bool
        var path: String {
            "/v1/vaults/\(vaultID)/members/\(userID)"
        }

        let method = HTTPMethod.put
        var body: (any Encodable)? {
            Body(role: role, canUseAI: canUseAI)
        }

        private struct Body: Encodable { let role: String; let canUseAI: Bool }
    }

    struct Invite: Endpoint {
        typealias Response = TeamInvitationSummary
        let teamID: UUID
        let email: String
        let vaultGrants: [String: TeamInviteGrant]
        var path: String {
            "/v1/teams/\(teamID)/invitations"
        }

        let method = HTTPMethod.post
        var body: (any Encodable)? {
            Body(email: email, vaultGrants: vaultGrants)
        }

        private struct Body: Encodable {
            let email: String
            let vaultGrants: [String: TeamInviteGrant]
        }
    }

    struct Activity: Endpoint {
        typealias Response = [VaultActivitySummary]
        let vaultID: UUID
        var path: String {
            "/v1/vaults/\(vaultID)/activity"
        }

        let method = HTTPMethod.get
    }
}
