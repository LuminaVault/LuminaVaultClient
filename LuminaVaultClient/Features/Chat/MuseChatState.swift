// LuminaVaultClient/LuminaVaultClient/Features/Chat/MuseChatState.swift
//
// Muse Stage B — what Hermie is doing, as one value
// (`_reviews/muse-chat-contract.md`, "Avatar states + status copy").
//
// The header used to guess its status line from the phase alone, so a reply
// that was already typing still said "is thinking" and a run grinding through
// a web search said nothing about it. This file turns everything the chat
// knows — the turn phase, whether tokens have landed, the last step on the
// run's trail, a pending approval, composer focus, voice capture, a finished
// turn's celebration — into one state with its copy, mascot art and ring.
//
// `derive(_:)` is a pure function of `Inputs`, so every row of the contract
// is a unit test rather than a simulator session. UI-only view state, not a
// DTO: nothing here crosses the wire.

import Foundation

enum MuseChatState: Equatable, Sendable {
    /// Nothing happening. "Ready".
    case idle
    /// Composer focused or voice capture running.
    case listening
    /// Turn open, no token yet.
    case thinking
    /// Tokens arriving.
    case writing
    /// A tool is running and we know what it is. The label is a verb phrase,
    /// ≤ ``MuseToolLabel/maxLength`` characters.
    case tool(label: String)
    /// The run is blocked on the user answering an approval prompt.
    case awaitingApproval
    /// Escalated to an agent run with nothing more specific to say.
    case delegated
    /// A turn just finished. Held for ``celebrationDuration``, then idle.
    case celebrating
    /// The last turn failed.
    case failed

    /// How long `celebrating` holds before the header falls back to idle.
    static let celebrationDuration: Duration = .milliseconds(1200)

    struct Inputs: Equatable, Sendable {
        var phase: ChatViewModel.Phase
        /// At least one token of the answer has arrived — on the chat stream
        /// for an ordinary turn, on the run feed for a delegated one.
        var hasFirstToken = false
        /// Newest row on the run's trail. Only its `toolLabel` is read: a
        /// label means a tool is in flight; a completed or failed row carries
        /// none, which is what ends the "is searching the web" line.
        var lastTrailItem: HermesRunTrailItem?
        var isAwaitingApproval = false
        var isComposerFocused = false
        var isRecordingVoice = false
        /// Inside the celebration window after a completed turn.
        var isCelebrating = false
    }

    static func derive(_ inputs: Inputs) -> MuseChatState {
        // Speech capture is listening whatever else is going on: the mic is
        // live and that is the thing the user needs to know.
        if inputs.isRecordingVoice { return .listening }

        switch inputs.phase {
        case .starting:
            return .thinking

        case .streaming:
            if let label = inputs.lastTrailItem?.toolLabel { return .tool(label: label) }
            return inputs.hasFirstToken ? .writing : .thinking

        case .delegated:
            // Most specific first: a blocked run is waiting on the user, a
            // running tool has a name, an answer arriving is writing. Only
            // when none of those is true is it the long "you can leave" wait.
            if inputs.isAwaitingApproval { return .awaitingApproval }
            if let label = inputs.lastTrailItem?.toolLabel { return .tool(label: label) }
            if inputs.hasFirstToken { return .writing }
            return .delegated

        case .failed:
            // Typing a retry is listening; until then the snag stays said.
            return inputs.isComposerFocused ? .listening : .failed

        case .idle:
            if inputs.isCelebrating { return .celebrating }
            return inputs.isComposerFocused ? .listening : .idle
        }
    }

    /// The second line of the name pill, in the contract's copy.
    var status: String {
        switch self {
        case .idle, .celebrating: "Ready"
        case .listening: "is listening"
        case .thinking: "is thinking"
        case .writing: "is writing"
        case let .tool(label): "is \(label)"
        case .awaitingApproval: "is waiting for you"
        case .delegated: "is still working — you can leave"
        case .failed: "hit a snag"
        }
    }

    /// Art for the avatar. There is no "working" art (contract): working
    /// states keep the thinking pose and the ring carries the rest.
    var mascotState: HermieMascotState {
        switch self {
        case .idle, .listening, .failed: .idle
        case .thinking, .writing, .tool, .awaitingApproval, .delegated: .thinking
        case .celebrating: .happy
        }
    }

    /// Draws the animated ring around the avatar.
    var isWorking: Bool {
        switch self {
        case .thinking, .writing, .tool, .awaitingApproval, .delegated: true
        case .idle, .listening, .celebrating, .failed: false
        }
    }
}

// MARK: - Tool labels

/// Turns a Hermes tool identifier into the verb phrase the header shows after
/// "is". The run feed names tools by id (`web_search`, `terminal`, …) and
/// carries no human label, so the client owns this table. A `label` field on
/// the event, if Hermes ever sends one, wins over the table.
enum MuseToolLabel {
    static let maxLength = 32

    static func phrase(tool: String?, explicitLabel: String? = nil) -> String {
        if let explicit = explicitLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
           !explicit.isEmpty {
            return clamp(explicit)
        }
        guard let tool = tool?.trimmingCharacters(in: .whitespacesAndNewlines), !tool.isEmpty else {
            return "using a tool"
        }
        let id = tool.lowercased()
        if let known = known(id) { return known }
        let humanized = id
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
        return clamp("using \(humanized)")
    }

    /// Ordered: the first matching rule wins, so the specific ones
    /// (`search_files`) sit above the broad ones (`search`).
    private static let rules: [(matches: [String], phrase: String)] = [
        (["web_search", "search_web", "websearch", "x_search"], "searching the web"),
        (["web_extract", "web_fetch", "fetch_url", "browser", "browse", "crawl", "scrape"], "reading a page"),
        (["search_files", "grep", "find_files"], "searching files"),
        (["read_file", "file_read"], "reading files"),
        (["write_file", "file_write", "patch", "edit_file", "apply_patch"], "editing files"),
        (["terminal", "shell", "bash", "execute_code", "code_exec", "python", "run_command"], "running code"),
        (["vault", "kb_", "knowledge", "memory_search", "recall", "query"], "searching your vault"),
        (["memory"], "checking memory"),
        (["image_generate", "image_gen", "generate_image"], "making an image"),
        (["vision", "image_analy", "analyze_image"], "looking at an image"),
        (["calendar"], "checking your calendar"),
        (["gmail", "mail", "email", "inbox"], "checking email"),
        (["weather", "forecast"], "checking the weather"),
        (["location"], "checking your location"),
        (["health"], "reading health data"),
        (["todo", "planner"], "planning"),
        (["delegate", "subagent"], "handing off a task"),
        (["cron", "schedule", "job"], "scheduling"),
        (["send_message", "notify", "push"], "sending a message"),
        (["skill"], "using a skill"),
        (["search"], "searching"),
    ]

    private static func known(_ id: String) -> String? {
        rules.first { rule in rule.matches.contains { id.contains($0) } }?.phrase
    }

    private static func clamp(_ phrase: String) -> String {
        guard phrase.count > maxLength else { return phrase }
        return String(phrase.prefix(maxLength - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
