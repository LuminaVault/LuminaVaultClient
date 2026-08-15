import Foundation

enum SetupPreset: String, CaseIterable, Identifiable {
    case claude
    case codex
    case hermes
    case anything

    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .hermes: "Hermes"
        case .anything: "Anything"
        }
    }
}

enum SetupPrompts {
    static let preamble =
        "Set this up for me on this LuminaVault account. Hermes is the backend. Confirm when it is ready."

    static func prompt(for preset: SetupPreset, custom: String = "") -> String {
        switch preset {
        case .claude:
            return """
            \(preamble)

            Connect Claude Code so I can use it from this vault.
            1. Check whether the Claude Code CLI or skill is already available.
            2. If not, install or add the official skill the way Hermes expects.
            3. Authenticate if needed and verify a simple ping works.
            4. Tell me what I can ask you to do next.
            """
        case .codex:
            return """
            \(preamble)

            Connect Codex / the OpenAI coding agent so I can use it from this vault.
            1. Check whether Codex CLI or the matching skill is already available.
            2. If not, install or add it the way Hermes expects.
            3. Authenticate if needed and verify a simple ping works.
            4. Tell me what I can ask you to do next.
            """
        case .hermes:
            return """
            \(preamble)

            Connect or verify Hermes for this account.
            1. Check whether a Hermes gateway is already configured and reachable.
            2. If not, walk me through managed vs bring-your-own and apply the config.
            3. Confirm chat, skills, cron, and tools are visible.
            4. Tell me what I can ask you to do next.
            """
        case .anything:
            let request = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            let body = request.isEmpty ? "the integration I describe next" : request
            return """
            \(preamble)

            \(body)

            1. Figure out what needs to be installed, configured, or authenticated.
            2. Do the setup you can do yourself, and ask me only for secrets or logins you cannot complete.
            3. Verify it works, then tell me how to use it.
            """
        }
    }
}
