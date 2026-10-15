import LuminaVaultShared

/// Plain-language labels for what a memory is and who saved it.
///
/// The server records provenance as enums and free-form provider/model
/// strings. People need "Saved by Claude Code (work laptop)", not
/// `model · Create`. The web app uses the same wording
/// (`src/lib/memories/memory-provenance.ts`); keep the two in step.
enum MemoryProvenanceText {
    /// One line saying who made this change, and through what.
    static func describe(_ contribution: MemoryContributionDTO) -> String {
        let verb = contribution.operation == .create ? "Saved" : "Edited"
        if let agent = agentLabel(contribution) {
            return "\(verb) by \(agent)"
        }
        if contribution.actor == .user {
            switch contribution.source {
            case .vault: return "\(verb) by you in a note"
            case .link: return "\(verb) by you from a link"
            case .import: return "\(verb) by you in an import"
            case .chat: return "\(verb) by you from a chat"
            default: return "\(verb) by you"
            }
        }
        switch contribution.source {
        case .knowledgeCompile: return "\(verb) by Lumina from your notes"
        case .chat: return "\(verb) from a chat answer"
        case .query: return "\(verb) from a search answer"
        case .skill: return "\(verb) by a skill"
        case .vault: return "\(verb) from a vault note"
        case .import: return "\(verb) during an import"
        case .link: return "\(verb) from a saved link"
        case .manual, .legacy: return "\(verb) before sources were tracked"
        }
    }

    /// An agent key's save carries provider `mcp:<client kind>` and the key's
    /// name as the model; a session caller is `mcp` / `session`.
    private static func agentLabel(_ contribution: MemoryContributionDTO) -> String? {
        guard let model = contribution.model,
              model.provider == "mcp" || model.provider.hasPrefix("mcp:")
        else { return nil }
        let kind = AgentClientKind(rawValue: String(model.provider.dropFirst("mcp:".count)))
        let client = switch kind {
        case .claudeCode, .codex, .hermes: kind?.label ?? "an agent"
        case .other: "an MCP client"
        case nil: "an agent"
        }
        return model.model == "session" ? client : "\(client) (\(model.model))"
    }
}

extension MemoryKindDTO {
    var label: String {
        switch self {
        case .preference: "Preference"
        case .decision: "Decision"
        case .fact: "Fact"
        case .note: "Note"
        }
    }

    var pluralLabel: String {
        switch self {
        case .preference: "Preferences"
        case .decision: "Decisions"
        case .fact: "Facts"
        case .note: "Notes"
        }
    }
}
