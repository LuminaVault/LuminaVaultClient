import LuminaVaultShared

/// The agent-connection wire types live in LuminaVaultShared. This file used to
/// hold local copies, which fell behind the server (no personal-data grant, no
/// access) — only the display name stays here, because it is UI.
extension AgentClientKind {
    var label: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .hermes: "Hermes"
        case .other: "Other MCP client"
        }
    }
}
