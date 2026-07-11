// LuminaVaultClient/LuminaVaultClient/Features/Chat/ChatViewModel.swift
//
// HER-269 — multi-turn chat over Conversations SSE stream. Routes
// through LuminaVaultServer's `/v1/conversations/:id/messages/stream`
// endpoint which is BYO-Hermes-aware on the server side: when the user
// has a verified Hermes Gateway config, replies come from their gateway;
// otherwise from the platform default model.
//
// Lifecycle (one conversation per VM instance):
//   1. `start()` POSTs `/v1/conversations` once to obtain a conversation
//      id. Subsequent `send(_:)` calls reuse it.
//   2. `send(_:)` appends the user turn locally, then opens an SSE
//      stream to /messages/stream. Each `.token` event appends to
//      `pendingAssistant`. `.source` events populate `pendingSources`.
//      `.fallback` events surface a one-shot banner. `.done` flushes
//      `pendingAssistant` into `messages`. `.error` aborts.
//   3. `cancel()` tears down the live stream Task. UI keeps any partial
//      text already streamed.
import Foundation

@Observable
@MainActor
final class ChatViewModel {
    // `nonisolated`: the target builds with SWIFT_DEFAULT_ACTOR_ISOLATION =
    // MainActor, which would otherwise make this nested type @MainActor and
    // break its synthesized (nonisolated) `Decodable` conformance — which
    // `ChatHistoryStore.Snapshot` relies on when decoding from its actor.
    nonisolated struct Message: Identifiable, Equatable, Sendable, Codable {
        let id: UUID
        let role: ConversationMessageRole
        var content: String
        var sources: [QueryHitDTO]
        var parallelExecutionID: UUID?

        init(
            id: UUID = UUID(),
            role: ConversationMessageRole,
            content: String,
            sources: [QueryHitDTO] = [],
            parallelExecutionID: UUID? = nil
        ) {
            self.id = id
            self.role = role
            self.content = content
            self.sources = sources
            self.parallelExecutionID = parallelExecutionID
        }
    }

    enum Phase: Equatable, Sendable {
        case idle
        case starting
        case streaming
        case failed(message: String)
    }

    /// HER-107 — mode toggle on the chat toolbar.
    /// - `.memoryGrounded` (🧠) — SSE stream against
    ///   `/v1/conversations/:id/messages/stream`. Source chips, live
    ///   tokens, mascot pulses on each token.
    /// - `.fresh` (☁️) — one-shot `/v1/chat/completions`. No memory
    ///   retrieval, no streaming, single bubble lands when reply
    ///   arrives.
    nonisolated enum Transport: String, Sendable, Equatable, CaseIterable, Codable {
        case memoryGrounded = "memory_grounded"
        case fresh
        case hybrid
    }

    // MARK: - Observable state

    var phase: Phase = .idle
    var messages: [Message] = []
    /// Live token buffer for the in-flight assistant turn. Empty when no
    /// stream is active. This is the *authoritative* received-so-far text;
    /// the view renders `displayedAssistant`, not this.
    var pendingAssistant: String = ""
    /// Typewriter reveal buffer. Lags `pendingAssistant` and catches up on a
    /// timer so the answer types in progressively — even when a non-streaming
    /// provider (e.g. managed-brain Gemini) delivers the whole reply in one
    /// `.summary` event. Rendered by `PendingAssistantRow`.
    var displayedAssistant: String = ""
    var pendingSources: [QueryHitDTO] = []
    /// One-shot banner emitted by a `.fallback` SSE event (e.g. xAI
    /// credit exhaustion → fallback model). Cleared on next `send()`.
    var fallbackNotice: ProviderFallbackNoticeDTO?
    /// Prompt-free Cerberus route and terminal usage metadata for the live turn.
    var routingEvent: RouterRoutingEventDTO?
    var routeUsage: RouterUsageDTO?
    /// Explicit per-turn orchestration. Off by default to avoid surprising
    /// multi-provider spend; Auto uses the server task classifier.
    var multiModelEnabled = false
    var multiModelStrategy: ParallelStrategyDTO = .auto
    var parallelExecution: ParallelChatExecution?
    var composer: String = ""
    /// HER-107 — drives `HermieMascotView`. Transitions: idle → thinking
    /// (on send / streaming) → happy (on .done) → idle (after ~1.5s).
    var mascotState: HermieMascotState = .idle
    /// HER-107 — active transport. Defaults to memory-grounded (the
    /// HER-269 SSE path); user toggles via the toolbar.
    var transport: Transport = .memoryGrounded
    var hybridProfile: HybridExecutionProfile = .balanced
    private(set) var executionLabel: String?

    /// Chat preferences (server-backed `autoExpandThinking`/`sendOnReturn` +
    /// device-local `hapticsEnabled`), pushed in by `ThinkWithLuminaView` after
    /// fetching `/v1/me/chat-preferences`.
    /// Expands the live pre-token thinking state. The stream currently has no
    /// separate model-reasoning payload, so only truthful activity copy is
    /// shown rather than synthesizing hidden reasoning.
    var autoExpandThinking = true
    /// When true the composer's Return key sends; when false Return inserts a
    /// newline (send via the button).
    var sendOnReturn = false
    /// Device-local haptic feedback on send.
    var hapticsEnabled = true
    /// SwiftUI observes these counters through `.sensoryFeedback`, keeping
    /// UIKit feedback generators out of the view model and making the gating
    /// behavior testable.
    private(set) var sendHapticTrigger = 0
    private(set) var completionHapticTrigger = 0
    /// HER-107 — transient banner after `saveAsMemory(...)`. Auto-clears
    /// after ~2s so the chat surface doesn't grow stale toasts.
    var savedMemoryToast: String?
    /// Lumina Jobs P3 — when the last user message reads as a recurring-job
    /// request, the server classifier returns a proposal and the chat shows a
    /// "Create Job" card. Cleared on confirm/dismiss/next send.
    var jobProposal: JobProposalDTO?
    /// Transient confirmation after a job is created (auto-clears ~2.5s).
    var jobToast: String?
    /// HER-55 — when the last user message reads as a "remind me…" request,
    /// the server classifier returns a proposal and the chat shows a
    /// "Set a reminder?" card. Cleared on confirm/dismiss/next send.
    var reminderProposal: ReminderProposalDTO?
    /// Transient confirmation after a reminder is created (auto-clears ~2.5s).
    var reminderToast: String?
    /// Client-extracted file staged for the next send. There is no
    /// per-message attachment contract on the server, so the extracted
    /// text is prepended into the outgoing message `content` (see
    /// `wireText`) and the file is cleared once sent.
    /// Phase 2 — multiple context references ride into the next `send()`.
    /// Each is a file, vault note, photo, or link whose extracted text is
    /// inlined into the turn (no server attachment contract exists).
    var stagedReferences: [StagedAttachment] = []

    struct StagedAttachment: Equatable, Sendable, Identifiable {
        let id = UUID()
        let name: String
        let text: String

        init(name: String, text: String) {
            self.name = name
            self.text = text
        }
    }

    private let conversationsClient: any ConversationsClientProtocol
    private let chatClient: any ChatClientProtocol
    private let memoryClient: any MemoryClientProtocol
    private let historyStore: ChatHistoryStore?
    private let localExecutor: (any LocalChatExecuting)?
    private let localMemorySync: LocalMemorySyncService?
    private let cloudAvailable: @MainActor @Sendable () -> Bool
    /// Lumina Jobs P3 — optional; when wired, each user turn is classified for
    /// recurring-job intent and a proposal card may surface.
    private let jobsClient: (any JobsClientProtocol)?
    /// HER-55 — optional; when wired, each user turn is classified for
    /// reminder intent and a "Set a reminder?" card may surface.
    private let remindersClient: (any RemindersClientProtocol)?
    /// HER-153 — owns the hold-to-talk recording state and Lumina's
    /// spoken-reply pipeline. Lazily wired through the init chain so
    /// existing call sites and previews don't need to know about it.
    let voice: VoiceModeController
    /// HER-153 — set true when the user's prompt came from the mic
    /// (`sendVoiceTranscript`). On `.done`, the assistant reply is
    /// auto-spoken iff this flag is set. Reset after each finalize.
    private var lastInputWasVoice = false
    /// Last user turn content, retained so `retryLast()` can re-send after
    /// a failure (e.g. a timed-out stream) without the user retyping.
    private var lastSentContent: String?
    private(set) var conversationID: UUID?
    private var streamTask: Task<Void, Never>?
    /// Drives the `displayedAssistant` typewriter reveal. Self-clears when it
    /// catches up so it never idle-spins.
    private var typewriterTask: Task<Void, Never>?
    private var mascotDecayTask: Task<Void, Never>?
    private var toastDecayTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var hasRestored = false

    init(
        conversationsClient: any ConversationsClientProtocol,
        chatClient: any ChatClientProtocol,
        memoryClient: any MemoryClientProtocol,
        historyStore: ChatHistoryStore? = nil,
        voice: VoiceModeController = VoiceModeController(),
        jobsClient: (any JobsClientProtocol)? = nil,
        remindersClient: (any RemindersClientProtocol)? = nil,
        localExecutor: (any LocalChatExecuting)? = nil,
        localMemorySync: LocalMemorySyncService? = nil,
        cloudAvailable: @escaping @MainActor @Sendable () -> Bool = { true }
    ) {
        self.conversationsClient = conversationsClient
        self.chatClient = chatClient
        self.memoryClient = memoryClient
        self.historyStore = historyStore
        self.jobsClient = jobsClient
        self.remindersClient = remindersClient
        self.localExecutor = localExecutor
        self.localMemorySync = localMemorySync
        self.cloudAvailable = cloudAvailable
        self.voice = voice
        self.voice.onFinalTranscript = { [weak self] transcript in
            self?.sendVoiceTranscript(transcript)
        }
    }

    /// Back-compat overload for callers that only need memory-grounded
    /// behavior. The `.fresh` transport will throw if invoked through
    /// this initializer because no chat client was supplied. Save-to-
    /// memory is also disabled (throws on call). No history persistence.
    convenience init(client: any ConversationsClientProtocol) {
        self.init(
            conversationsClient: client,
            chatClient: NoChatClient(),
            memoryClient: NoMemoryClient(),
            historyStore: nil
        )
    }

    var isStreaming: Bool {
        if case .streaming = phase {
            return true
        }
        return false
    }

    var canSend: Bool {
        let hasText = !composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || !stagedReferences.isEmpty)
            && !isStreaming
            && phase != .starting
    }

    /// Stage a client-extracted reference (file / vault note / link). Its
    /// text rides into the next `send()` as a context block prepended to the
    /// user's turn.
    func attach(name: String, text: String) {
        stagedReferences.append(StagedAttachment(name: name, text: text))
    }

    func removeReference(_ reference: StagedAttachment) {
        stagedReferences.removeAll { $0.id == reference.id }
    }

    /// Clears all staged references.
    func clearAttachment() {
        stagedReferences.removeAll()
    }

    /// Lazy conversation create. Called once on first memory-grounded
    /// send. `.fresh` transport never calls this — it doesn't persist a
    /// server-side conversation.
    private func ensureConversation() async throws -> UUID {
        if let id = conversationID {
            return id
        }
        phase = .starting
        let dto = try await conversationsClient.create(ConversationCreateRequest())
        conversationID = dto.id
        return dto.id
    }

    func send() {
        let trimmed = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        let references = stagedReferences
        guard !trimmed.isEmpty || !references.isEmpty, !isStreaming, phase != .starting else { return }
        if hapticsEnabled {
            sendHapticTrigger += 1
        }
        composer = ""
        stagedReferences = []

        // The bubble shows just the user's text (+ compact reference markers);
        // the wire content carries the full extracted references so the model
        // can reason over them.
        let displayContent = Self.displayText(typed: trimmed, references: references)
        let wireContent = Self.wireText(typed: trimmed, references: references)

        lastSentContent = wireContent
        fallbackNotice = nil
        routingEvent = nil
        routeUsage = nil
        parallelExecution = nil
        setMascot(.thinking)

        let userMessage = Message(role: .user, content: displayContent)
        messages.append(userMessage)
        schedulePersist()

        // Jobs P3 — classify the turn for recurring-job intent in the
        // background; never blocks the chat stream.
        jobProposal = nil
        let allowsCloudSideEffects = !(transport == .hybrid && hybridProfile == .private)
        if allowsCloudSideEffects, jobsClient != nil, !trimmed.isEmpty {
            let probe = trimmed
            Task { [weak self] in await self?.detectJob(probe) }
        }

        // HER-55 — classify the turn for reminder intent in the background;
        // never blocks the chat stream.
        reminderProposal = nil
        if allowsCloudSideEffects, remindersClient != nil, !trimmed.isEmpty {
            let probe = trimmed
            Task { [weak self] in await self?.detectReminder(probe) }
        }

        streamTask?.cancel()
        streamTask = Task { [weak self] in
            await self?.runSend(content: wireContent)
        }
    }

    // MARK: - Jobs (P3)

    private func detectJob(_ text: String) async {
        guard let jobsClient else { return }
        guard let proposal = try? await jobsClient.detect(text: text), proposal.isJob else { return }
        jobProposal = proposal
    }

    /// Create the proposed job, then clear the card and show a toast.
    func confirmJob() {
        guard let jobsClient, let proposal = jobProposal,
              let cron = proposal.cron, let spec = proposal.spec
        else { jobProposal = nil; return }
        let request = JobCreateRequest(
            title: proposal.title ?? "Job",
            cron: cron,
            domain: proposal.domain,
            spec: spec,
            spaceId: nil
        )
        jobProposal = nil
        Task { [weak self] in
            guard let self else { return }
            if (try? await jobsClient.create(request)) != nil {
                self.jobToast = "Job created — find it in the Jobs tab."
                self.scheduleJobToastDecay()
            }
        }
    }

    func dismissJob() {
        jobProposal = nil
    }

    private func scheduleJobToastDecay() {
        toastDecayTask?.cancel()
        toastDecayTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            self?.jobToast = nil
        }
    }

    // MARK: - Reminders (HER-55)

    private var reminderToastDecayTask: Task<Void, Never>?

    private func detectReminder(_ text: String) async {
        guard let remindersClient else { return }
        guard let proposal = try? await remindersClient.detect(text: text),
              proposal.isReminder, proposal.fireAt != nil
        else { return }
        reminderProposal = proposal
    }

    /// Create the proposed reminder, then clear the card and show a toast.
    func confirmReminder() {
        guard let remindersClient, let proposal = reminderProposal,
              let fireAt = proposal.fireAt
        else { reminderProposal = nil; return }
        let request = ReminderCreateRequest(
            title: proposal.title ?? "Reminder",
            body: proposal.body ?? "",
            fireAt: fireAt,
            recurrenceCron: proposal.recurrenceCron
        )
        reminderProposal = nil
        Task { [weak self] in
            guard let self else { return }
            if (try? await remindersClient.create(request)) != nil {
                self.reminderToast = "Reminder set — find it in the Reminders tab."
                self.scheduleReminderToastDecay()
            }
        }
    }

    func dismissReminder() {
        reminderProposal = nil
    }

    private func scheduleReminderToastDecay() {
        reminderToastDecayTask?.cancel()
        reminderToastDecayTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            self?.reminderToast = nil
        }
    }

    /// User-visible bubble text: their typed message, with a compact
    /// "📎 name" marker when a file is attached (the bulky extracted text
    /// is never shown in the bubble). Internal (not private) so it can be
    /// unit-tested directly.
    static func displayText(typed: String, attachment: StagedAttachment?) -> String {
        guard let attachment else { return typed }
        let marker = "📎 \(attachment.name)"
        return typed.isEmpty ? marker : "\(marker)\n\(typed)"
    }

    /// Multi-reference bubble text: one compact marker per reference.
    static func displayText(typed: String, references: [StagedAttachment]) -> String {
        guard !references.isEmpty else { return typed }
        let markers = references.map { "📎 \($0.name)" }.joined(separator: "\n")
        return typed.isEmpty ? markers : "\(markers)\n\(typed)"
    }

    /// Multi-reference wire content: each reference in its own fenced block,
    /// followed by the user's message.
    static func wireText(typed: String, references: [StagedAttachment]) -> String {
        guard !references.isEmpty else { return typed }
        let blocks = references.map { ref in
            """
            [Attached: \(ref.name)]
            \"\"\"
            \(ref.text)
            \"\"\"
            """
        }.joined(separator: "\n\n")
        return typed.isEmpty
            ? "\(blocks)\n\nPlease use the attached context."
            : "\(blocks)\n\n\(typed)"
    }

    /// Outgoing wire content: the extracted file wrapped in a fenced
    /// block, followed by the user's message. No server attachment
    /// contract exists, so the file rides inside `content`. Internal (not
    /// private) so it can be unit-tested directly.
    static func wireText(typed: String, attachment: StagedAttachment?) -> String {
        guard let attachment else { return typed }
        let block = """
        [Attached file: \(attachment.name)]
        \"\"\"
        \(attachment.text)
        \"\"\"
        """
        return typed.isEmpty
            ? "\(block)\n\nPlease use the attached file."
            : "\(block)\n\n\(typed)"
    }

    /// Re-run the last user turn after a failure (e.g. a timed-out stream).
    /// The user bubble is already in `messages`, so we only restart the
    /// send pipeline — no duplicate user message is appended.
    func retryLast() {
        guard let content = lastSentContent, !isStreaming, phase != .starting else { return }
        fallbackNotice = nil
        routingEvent = nil
        routeUsage = nil
        setMascot(.thinking)
        streamTask?.cancel()
        streamTask = Task { [weak self] in
            await self?.runSend(content: content)
        }
    }

    /// Maps transport errors to user-facing copy. `URLError.timedOut`
    /// (often a cold managed-brain that hasn't emitted its first SSE byte)
    /// gets a friendlier, retry-oriented message instead of Foundation's
    /// "The request timed out."
    private func friendlyError(_ error: Error) -> String {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return "Lumina took too long to respond. Tap Retry."
        }
        return (error as? APIError)?.errorDescription ?? error.localizedDescription
    }

    /// Programmatic seed — used by empty-state suggestion chips.
    func sendSuggestion(_ text: String) {
        composer = text
        send()
    }

    /// HER-153 — entry point from `VoiceModeController.onFinalTranscript`.
    /// Seeds the composer with the recognized text, flags the next
    /// reply as voice-originated, and triggers a normal send. Marker
    /// is consumed in `finalizeAssistantTurn` to decide whether to
    /// auto-speak.
    func sendVoiceTranscript(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        composer = trimmed
        lastInputWasVoice = true
        send()
    }

    private func runSend(content: String) async {
        switch transport {
        case .memoryGrounded: await runMemoryGroundedSend(content: content)
        case .fresh: await runFreshSend(content: content)
        case .hybrid: await runHybridSend(content: content)
        }
    }

    private func runHybridSend(content: String) async {
        let localAvailable = await localExecutor?.isAvailable() == true
        let decision = HybridExecutionCoordinator().decide(
            profile: hybridProfile,
            capabilities: HybridExecutionCapabilities(
                localAvailable: localAvailable,
                cloudAvailable: cloudAvailable(),
                requiresCloudTool: multiModelEnabled,
                contextFitsLocally: content.count < 32000
            )
        )
        switch decision {
        case .cloud:
            executionLabel = "Cloud"
            await runMemoryGroundedSend(content: content)
        case let .unavailable(message):
            phase = .failed(message: message)
            setMascot(.idle)
        case .local:
            guard let localExecutor else {
                phase = .failed(message: "No local model is configured.")
                return
            }
            var prepared: ConversationPrepareResponse?
            var degradedContext = false
            do {
                await localMemorySync?.synchronize()
                phase = .streaming
                pendingAssistant = ""
                displayedAssistant = ""
                pendingSources = []
                var prompt: [ChatMessage]
                if hybridProfile == .private {
                    prompt = messages.map { ChatMessage(role: $0.role.rawValue, content: $0.content) }
                } else {
                    do {
                        let id = try await ensureConversation()
                        let response = try await conversationsClient.prepare(
                            conversationID: id,
                            request: ConversationPrepareRequest(content: content)
                        )
                        prepared = response
                        prompt = response.messages
                        pendingSources = response.sources
                    } catch {
                        degradedContext = true
                        prompt = messages.map { ChatMessage(role: $0.role.rawValue, content: $0.content) }
                        if let cached = await localMemorySync?.context(for: content), !cached.isEmpty {
                            let context = cached.map(\.content).joined(separator: "\n\n")
                            prompt.insert(ChatMessage(role: "system", content: "Relevant local memories:\n\(context)"), at: 0)
                        }
                    }
                }
                executionLabel = degradedContext
                    ? "Offline local · \(localExecutor.modelID)"
                    : hybridProfile == .private
                    ? "Private · \(localExecutor.displayName) · \(localExecutor.modelID)"
                    : "Local · \(localExecutor.displayName) · \(localExecutor.modelID)"
                for try await delta in localExecutor.stream(messages: prompt) {
                    pendingAssistant.append(delta)
                    startTypewriter()
                }
                await drainTypewriter()
                if let prepared, let id = conversationID {
                    _ = try await conversationsClient.commit(
                        conversationID: id,
                        request: ConversationCommitRequest(
                            executionID: prepared.executionID,
                            content: pendingAssistant,
                            location: .localEndpoint,
                            provider: localExecutor.displayName,
                            model: localExecutor.modelID
                        )
                    )
                }
                finalizeAssistantTurn()
                phase = .idle
                flashHappyThenIdle()
            } catch is CancellationError {
                await cancelPreparedExecutionIfNeeded(prepared)
                drainTypewriterNow()
                phase = .idle
                setMascot(.idle)
            } catch {
                await cancelPreparedExecutionIfNeeded(prepared)
                drainTypewriterNow()
                phase = .failed(message: friendlyError(error))
                setMascot(.idle)
            }
        }
    }

    private func cancelPreparedExecutionIfNeeded(_ prepared: ConversationPrepareResponse?) async {
        guard let prepared, let conversationID else { return }
        try? await conversationsClient.cancelPreparedExecution(
            conversationID: conversationID,
            executionID: prepared.executionID
        )
    }

    private func runMemoryGroundedSend(content: String) async {
        do {
            let id = try await ensureConversation()
            phase = .streaming
            pendingAssistant = ""
            displayedAssistant = ""
            pendingSources = []

            let stream = conversationsClient.streamReply(
                conversationID: id,
                request: MessageStreamRequest(
                    content: content,
                    multiModel: multiModelEnabled
                        ? ChatMultiModelOptionsDTO(enabled: true, strategy: multiModelStrategy)
                        : nil
                )
            )
            for try await event in stream {
                if Task.isCancelled {
                    break
                }
                switch event {
                case let .source(hit):
                    pendingSources.append(hit)
                case let .token(delta):
                    pendingAssistant.append(delta)
                    startTypewriter()
                case let .summary(final):
                    // Server-provided final summary overrides the
                    // concatenated tokens. Some backends only emit a
                    // summary (no per-token deltas) — the typewriter reveals
                    // it progressively instead of popping it in at once.
                    if !final.isEmpty {
                        pendingAssistant = final
                        startTypewriter()
                    }
                case let .fallback(notice):
                    fallbackNotice = notice
                case let .routing(event):
                    routingEvent = event
                case let .usage(usage):
                    routeUsage = usage
                case let .parallel(event):
                    reduceParallelEvent(event)
                case .followUps:
                    // HER-37b will surface these as tappable chips.
                    // For now they're observable but not stored.
                    continue
                case .linkSaved:
                    // HER-274 — server auto-captured a URL to the vault.
                    // Not surfaced in chat UI yet; the link will show up
                    // in the vault on next refresh.
                    continue
                case .done:
                    // Let the reveal finish typing the tail, then freeze the
                    // fully-revealed text into a finalized bubble.
                    await drainTypewriter()
                    finalizeAssistantTurn()
                    phase = .idle
                    flashHappyThenIdle()
                    return
                case let .error(message):
                    drainTypewriterNow()
                    phase = .failed(message: message)
                    setMascot(.idle)
                    return
                }
            }
            // Stream ended without `.done` (e.g. server hung up). Treat
            // any buffered text as a complete turn.
            await drainTypewriter()
            if !pendingAssistant.isEmpty {
                finalizeAssistantTurn()
            }
            phase = .idle
            flashHappyThenIdle()
        } catch is CancellationError {
            // User-initiated cancel via `cancel()` — reveal-all, preserve
            // partials (no point animating after teardown).
            drainTypewriterNow()
            if !pendingAssistant.isEmpty {
                finalizeAssistantTurn(playsCompletionHaptic: false)
            }
            phase = .idle
            setMascot(.idle)
        } catch {
            drainTypewriterNow()
            let message = friendlyError(error)
            phase = .failed(message: message)
            setMascot(.idle)
        }
    }

    /// `.fresh` transport — single POST to /v1/chat/completions. No
    /// streaming UI: the assistant turn lands fully formed when the
    /// server replies. Routes through BYO Hermes when configured.
    private func runFreshSend(content _: String) async {
        // Fresh mode doesn't allocate a server-side conversation row.
        // Mint a client-side UUID so the local cache still has a key
        // to snapshot under (one snapshot per "fresh session").
        if conversationID == nil {
            conversationID = UUID()
        }
        phase = .streaming
        pendingAssistant = ""
        displayedAssistant = ""
        pendingSources = []
        let history = messages.map { msg in
            ChatMessage(role: msg.role.rawValue, content: msg.content)
        }
        let request = ChatRequest(
            messages: history,
            model: nil,
            temperature: nil,
            stream: false
        )
        do {
            let response = try await chatClient.complete(request)
            // Reveal the one-shot reply through the same typewriter so ☁️ mode
            // feels consistent with the SSE path, then finalize.
            pendingAssistant = response.message.content
            startTypewriter()
            await drainTypewriter()
            finalizeAssistantTurn()
            phase = .idle
            flashHappyThenIdle()
        } catch is CancellationError {
            drainTypewriterNow()
            phase = .idle
            setMascot(.idle)
        } catch {
            drainTypewriterNow()
            let message = friendlyError(error)
            phase = .failed(message: message)
            setMascot(.idle)
        }
    }

    /// Cycle the transport. Used by the toolbar toggle.
    func toggleTransport() {
        switch transport {
        case .memoryGrounded: transport = .fresh
        case .fresh: transport = .hybrid
        case .hybrid: transport = .memoryGrounded
        }
        schedulePersist()
    }

    /// HER-107 — restore the most-recent conversation snapshot from
    /// disk. Idempotent; safe to call from `.task { … }` on every
    /// appear. Skips when no snapshot exists or the store is wired off.
    func restore() async {
        guard !hasRestored, let store = historyStore else { hasRestored = true; return }
        hasRestored = true
        do {
            guard let snapshot = try await store.loadMostRecent() else { return }
            // Don't clobber an in-flight conversation if the view re-appears.
            guard messages.isEmpty, conversationID == nil else { return }
            conversationID = snapshot.id
            messages = snapshot.messages
            transport = snapshot.transport
        } catch {
            // Non-fatal — the user gets a fresh chat instead of a crash.
        }
    }

    /// Loads a persisted server conversation selected from the Chats inbox.
    /// This intentionally bypasses the local snapshot restore path so the inbox
    /// remains the source of truth when the user chooses an older thread.
    func loadConversation(id: UUID) async {
        guard !isStreaming, phase != .starting else { return }
        phase = .starting
        fallbackNotice = nil
        routingEvent = nil
        routeUsage = nil
        pendingAssistant = ""
        displayedAssistant = ""
        pendingSources = []
        jobProposal = nil
        reminderProposal = nil
        hasRestored = true

        do {
            let detail = try await conversationsClient.get(id)
            conversationID = detail.conversation.id
            messages = detail.messages.map { message in
                Message(
                    id: message.id,
                    role: message.role,
                    content: message.content,
                    sources: []
                )
            }
            transport = .memoryGrounded
            phase = .idle
            schedulePersist()
        } catch is CancellationError {
            phase = .idle
        } catch {
            phase = .failed(message: friendlyError(error))
        }
    }

    /// Debounce-persist current chat state. Called after every turn
    /// transition. 250ms window collapses bursts (multiple .token events
    /// finalizing into a single .done don't each trigger a write).
    private func schedulePersist() {
        guard let store = historyStore else { return }
        let snapshot = currentSnapshot()
        guard let snapshot else { return }
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !(Task.isCancelled) else { return }
            do { try await store.save(snapshot) } catch { _ = self /* swallow */ }
        }
    }

    private func currentSnapshot() -> ChatHistoryStore.Snapshot? {
        guard let id = conversationID else { return nil }
        return ChatHistoryStore.Snapshot(
            id: id,
            transport: transport,
            messages: messages,
            updatedAt: Date()
        )
    }

    /// Conversation rewind: trims this message and everything after it,
    /// returning the chat to its state just before this turn. The feasible
    /// form of "rollback" — Hermes-native checkpoints aren't exposed to the
    /// routed chat path, but LuminaVault owns the conversation history.
    func rewind(to message: Message) {
        guard !isStreaming, phase != .starting else { return }
        guard let idx = messages.firstIndex(where: { $0.id == message.id }) else { return }
        messages.removeSubrange(idx...)
        pendingAssistant = ""
        displayedAssistant = ""
        schedulePersist()
    }

    /// HER-107 — long-press save assistant turn as a Memory row.
    /// User turns are excluded (the chat itself is the persistence) —
    /// the UI should only surface this action on assistant bubbles.
    func saveAsMemory(_ message: Message) {
        guard !message.content.isEmpty else { return }
        Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await self.memoryClient.upsert(
                    MemoryUpsertRequest(content: message.content)
                )
                await MainActor.run { self.showSavedToast("Saved to memory") }
            } catch {
                let msg = (error as? APIError)?.errorDescription ?? error.localizedDescription
                await MainActor.run { self.showSavedToast("Save failed: \(msg)") }
            }
        }
    }

    private func showSavedToast(_ text: String) {
        savedMemoryToast = text
        toastDecayTask?.cancel()
        toastDecayTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run { self?.savedMemoryToast = nil }
        }
    }

    // MARK: - Mascot

    private func setMascot(_ state: HermieMascotState) {
        mascotDecayTask?.cancel()
        mascotState = state
    }

    /// Pulse happy, then decay back to idle after 1.5s. Cancellable so
    /// rapid-fire turns don't accumulate timers.
    private func flashHappyThenIdle() {
        setMascot(.happy)
        mascotDecayTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            await MainActor.run { self?.mascotState = .idle }
        }
    }

    // MARK: - Typewriter reveal

    /// Spawn the reveal driver if not already running. Cheap no-op while a
    /// task is live, so it can be called on every `.token`/`.summary`.
    private func startTypewriter() {
        guard typewriterTask == nil else { return }
        typewriterTask = Task { [weak self] in
            await self?.pumpTypewriter()
        }
    }

    /// Advance `displayedAssistant` toward `pendingAssistant` on a ~60fps
    /// timer. Bounded drain: each tick reveals a fraction of the remaining
    /// gap, so any answer (incl. a one-shot Gemini dump) finishes in ~1s
    /// while the tail still feels typed. Self-clears when caught up.
    private func pumpTypewriter() async {
        while !Task.isCancelled {
            let gap = pendingAssistant.count - displayedAssistant.count
            if gap <= 0 {
                break
            }
            let stride = max(1, gap / 8)
            // `displayedAssistant` is always a prefix of `pendingAssistant`,
            // so extend it by slicing the next `stride` chars from the
            // authoritative buffer at the current offset.
            let lower = pendingAssistant.index(pendingAssistant.startIndex, offsetBy: displayedAssistant.count)
            let upper = pendingAssistant.index(lower, offsetBy: stride)
            displayedAssistant.append(contentsOf: pendingAssistant[lower ..< upper])
            try? await Task.sleep(for: .milliseconds(16))
        }
        typewriterTask = nil
    }

    /// Await the live reveal so it finishes typing the tail before we freeze
    /// the turn. Returns immediately if nothing is animating.
    private func drainTypewriter() async {
        await typewriterTask?.value
        // Guard against an interleaved write landing after the loop exited.
        if displayedAssistant.count < pendingAssistant.count {
            displayedAssistant = pendingAssistant
        }
    }

    /// Instant catch-up — reveal everything and tear down the driver. Used on
    /// cancel/error where animating is pointless.
    private func drainTypewriterNow() {
        typewriterTask?.cancel()
        typewriterTask = nil
        displayedAssistant = pendingAssistant
    }

    private func finalizeAssistantTurn(playsCompletionHaptic: Bool = true) {
        let assistant = Message(
            role: .assistant,
            content: pendingAssistant,
            sources: pendingSources,
            parallelExecutionID: parallelExecution?.id
        )
        messages.append(assistant)
        let spokenBody = pendingAssistant
        pendingAssistant = ""
        displayedAssistant = ""
        pendingSources = []
        schedulePersist()
        // HER-153 — speak reply iff the user's prompt was voice. Typed
        // prompts stay silent regardless of voice availability.
        if lastInputWasVoice {
            voice.speak(spokenBody)
        }
        lastInputWasVoice = false
        if hapticsEnabled, playsCompletionHaptic {
            completionHapticTrigger += 1
        }
    }

    /// Cancel the in-flight stream. Partial text already streamed is
    /// preserved as a complete assistant turn so the user can read it.
    /// Also silences Lumina mid-utterance if she's currently speaking.
    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        // The stream's CancellationError path reveals + preserves partials;
        // tear the reveal driver down here so it can't outlive the stream.
        typewriterTask?.cancel()
        typewriterTask = nil
        if voice.isSpeaking {
            voice.stopSpeaking()
        }
    }

    /// Wipe the conversation client-side and forget the server id. Also
    /// clears the cached snapshot so the next launch starts blank. The
    /// server-side conversation row stays (call `conversationsClient.delete`
    /// separately to wipe that too).
    func reset() {
        cancel()
        mascotDecayTask?.cancel()
        persistTask?.cancel()
        typewriterTask?.cancel()
        typewriterTask = nil
        let oldID = conversationID
        conversationID = nil
        messages = []
        pendingAssistant = ""
        displayedAssistant = ""
        pendingSources = []
        fallbackNotice = nil
        routingEvent = nil
        routeUsage = nil
        parallelExecution = nil
        stagedReferences = []
        phase = .idle
        mascotState = .idle
        if let store = historyStore, let oldID {
            Task { try? await store.clear(conversationID: oldID) }
        }
    }

    private func reduceParallelEvent(_ event: ParallelStreamEventDTO) {
        if event.kind == .executionStarted || parallelExecution?.id != event.executionID {
            parallelExecution = ParallelChatExecution(
                id: event.executionID,
                strategy: event.strategy ?? multiModelStrategy,
                status: event.status ?? .running
            )
        }
        guard var execution = parallelExecution else { return }
        execution.status = event.status ?? execution.status
        if let outputID = event.outputID {
            if let index = execution.outputs.firstIndex(where: { $0.id == outputID }) {
                if let delta = event.delta {
                    execution.outputs[index].content.append(delta)
                }
                execution.outputs[index].status = event.status ?? execution.outputs[index].status
            } else {
                execution.outputs.append(ParallelChatOutput(
                    id: outputID,
                    participantID: event.participantID,
                    role: event.role ?? "Model",
                    route: event.route,
                    stage: event.stage ?? .answer,
                    round: event.round ?? 1,
                    content: event.delta ?? "",
                    status: event.status ?? .running
                ))
            }
        } else if event.kind == .outputFailed, let participantID = event.participantID,
                  let index = execution.outputs.firstIndex(where: { $0.participantID == participantID })
        {
            execution.outputs[index].status = .failed
        }
        parallelExecution = execution
    }
}

/// Throwing stub returned by the back-compat init. Lets ChatViewModel
/// keep a non-optional `chatClient` so the runtime switch is total. Any
/// `.fresh` send through the convenience init throws — callers that
/// flip the toggle without supplying a real chat client will see a
/// clean error instead of a silent no-op.
private struct NoChatClient: ChatClientProtocol {
    func complete(_: ChatRequest) async throws -> ChatResponse {
        throw APIError.unauthorized
    }
}

private struct NoMemoryClient: MemoryClientProtocol {
    func upsert(_: MemoryUpsertRequest) async throws -> MemoryUpsertResponse {
        throw APIError.unauthorized
    }

    func get(id _: UUID) async throws -> MemoryDTO {
        throw APIError.unauthorized
    }

    func patch(id _: UUID, _: MemoryPatchRequest) async throws -> MemoryDTO {
        throw APIError.unauthorized
    }

    func list(limit _: Int, offset _: Int) async throws -> MemoryListResponse {
        throw APIError.unauthorized
    }

    func search(_: MemorySearchRequest) async throws -> MemorySearchResponse {
        throw APIError.unauthorized
    }

    func delete(id _: UUID) async throws {
        throw APIError.unauthorized
    }
}
