@testable import LuminaVaultClient
import Testing

@Suite("Setup with Lumina prompts")
struct SetupPromptsTests {
    @Test func claudePromptMentionsHermesAndClaude() {
        let prompt = SetupPrompts.prompt(for: .claude)
        #expect(prompt.contains("Claude Code"))
        #expect(prompt.contains("Hermes is the backend"))
    }

    @Test func anythingPromptIncludesCustomRequest() {
        let prompt = SetupPrompts.prompt(for: .anything, custom: "Install Higgsfield")
        #expect(prompt.contains("Install Higgsfield"))
    }
}
