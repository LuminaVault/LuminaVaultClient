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
    struct Message: Identifiable, Equatable, Sendable, Codable {
        let id: UUID
        let role: ConversationMessageRole
        var content: String
        var sources: [QueryHitDTO]

        init(
            id: UUID = UUID(),
            role: ConversationMessageRole,
            content: String,
            sources: [QueryHitDTO] = [],
        ) {
            self.id = id
            self.role = role
            self.content = content
            self.sources = sources
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
    enum Transport: String, Sendable, Equatable, CaseIterable, Codable {
        case memoryGrounded = "memory_grounded"
        case fresh
    }

    // MARK: - Observable state

    var phase: Phase = .idle
    var messages: [Message] = []
    /// Live token buffer for the in-flight assistant turn. Empty when no
    /// stream is active. Rendered as a non-finalized bubble by the view.
    var pendingAssistant: String = ""
    var pendingSources: [QueryHitDTO] = []
    /// One-shot banner emitted by a `.fallback` SSE event (e.g. xAI
    /// credit exhaustion → fallback model). Cleared on next `send()`.
    var fallbackNotice: ProviderFallbackNoticeDTO?
    var composer: String = ""
    /// HER-107 — drives `HermieMascotView`. Transitions: idle → thinking
    /// (on send / streaming) → happy (on .done) → idle (after ~1.5s).
    var mascotState: HermieMascotState = .idle
    /// HER-107 — active transport. Defaults to memory-grounded (the
    /// HER-269 SSE path); user toggles via the toolbar.
    var transport: Transport = .memoryGrounded
    /// HER-107 — transient banner after `saveAsMemory(...)`. Auto-clears
    /// after ~2s so the chat surface doesn't grow stale toasts.
    var savedMemoryToast: String?
    /// Client-extracted file staged for the next send. There is no
    /// per-message attachment contract on the server, so the extracted
    /// text is prepended into the outgoing message `content` (see
    /// `wireText`) and the file is cleared once sent.
    var stagedAttachment: StagedAttachment?

    struct StagedAttachment: Equatable, Sendable {
        let name: String
        let text: String
    }

    private let conversationsClient: any ConversationsClientProtocol
    private let chatClient: any ChatClientProtocol
    private let memoryClient: any MemoryClientProtocol
    private let historyStore: ChatHistoryStore?
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
    ) {
        self.conversationsClient = conversationsClient
        self.chatClient = chatClient
        self.memoryClient = memoryClient
        self.historyStore = historyStore
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
            historyStore: nil,
        )
    }

    var isStreaming: Bool {
        if case .streaming = phase { return true }
        return false
    }

    var canSend: Bool {
        let hasText = !composer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || stagedAttachment != nil)
            && !isStreaming
            && phase != .starting
    }

    /// Stage a client-extracted file. Its text rides into the next
    /// `send()` as a context block prepended to the user's turn.
    func attach(name: String, text: String) {
        stagedAttachment = StagedAttachment(name: name, text: text)
    }

    func clearAttachment() {
        stagedAttachment = nil
    }

    /// Lazy conversation create. Called once on first memory-grounded
    /// send. `.fresh` transport never calls this — it doesn't persist a
    /// server-side conversation.
    private func ensureConversation() async throws -> UUID {
        if let id = conversationID { return id }
        phase = .starting
        let dto = try await conversationsClient.create(ConversationCreateRequest())
        conversationID = dto.id
        return dto.id
    }

    func send() {
        let trimmed = composer.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachment = stagedAttachment
        guard (!trimmed.isEmpty || attachment != nil), !isStreaming, phase != .starting else { return }
        composer = ""
        stagedAttachment = nil

        // The bubble shows just the user's text (+ a compact file marker);
        // the wire content carries the full extracted file so the model
        // can reason over it.
        let displayContent = Self.displayText(typed: trimmed, attachment: attachment)
        let wireContent = Self.wireText(typed: trimmed, attachment: attachment)

        lastSentContent = wireContent
        fallbackNotice = nil
        setMascot(.thinking)

        let userMessage = Message(role: .user, content: displayContent)
        messages.append(userMessage)
        schedulePersist()

        streamTask?.cancel()
        streamTask = Task { [weak self] in
            await self?.runSend(content: wireContent)
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
        }
    }

    private func runMemoryGroundedSend(content: String) async {
        do {
            let id = try await ensureConversation()
            phase = .streaming
            pendingAssistant = ""
            pendingSources = []

            let stream = conversationsClient.streamReply(
                conversationID: id,
                request: MessageStreamRequest(content: content),
            )
            for try await event in stream {
                if Task.isCancelled { break }
                switch event {
                case .source(let hit):
                    pendingSources.append(hit)
                case .token(let delta):
                    pendingAssistant.append(delta)
                case .summary(let final):
                    // Server-provided final summary overrides the
                    // concatenated tokens. Some backends only emit a
                    // summary (no per-token deltas).
                    if !final.isEmpty { pendingAssistant = final }
                case .fallback(let notice):
                    fallbackNotice = notice
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
                    finalizeAssistantTurn()
                    phase = .idle
                    flashHappyThenIdle()
                    return
                case .error(let message):
                    phase = .failed(message: message)
                    setMascot(.idle)
                    return
                }
            }
            // Stream ended without `.done` (e.g. server hung up). Treat
            // any buffered text as a complete turn.
            if !pendingAssistant.isEmpty {
                finalizeAssistantTurn()
            }
            phase = .idle
            flashHappyThenIdle()
        } catch is CancellationError {
            // User-initiated cancel via `cancel()` — preserve partials.
            if !pendingAssistant.isEmpty {
                finalizeAssistantTurn()
            }
            phase = .idle
            setMascot(.idle)
        } catch {
            let message = friendlyError(error)
            phase = .failed(message: message)
            setMascot(.idle)
        }
    }

    /// `.fresh` transport — single POST to /v1/chat/completions. No
    /// streaming UI: the assistant turn lands fully formed when the
    /// server replies. Routes through BYO Hermes when configured.
    private func runFreshSend(content: String) async {
        // Fresh mode doesn't allocate a server-side conversation row.
        // Mint a client-side UUID so the local cache still has a key
        // to snapshot under (one snapshot per "fresh session").
        if conversationID == nil { conversationID = UUID() }
        phase = .streaming
        pendingAssistant = ""
        pendingSources = []
        let history = messages.map { msg in
            ChatMessage(role: msg.role.rawValue, content: msg.content)
        }
        let request = ChatRequest(
            messages: history,
            model: nil,
            temperature: nil,
            stream: false,
        )
        do {
            let response = try await chatClient.complete(request)
            let assistant = Message(
                role: .assistant,
                content: response.message.content,
            )
            messages.append(assistant)
            phase = .idle
            flashHappyThenIdle()
            schedulePersist()
        } catch is CancellationError {
            phase = .idle
            setMascot(.idle)
        } catch {
            let message = friendlyError(error)
            phase = .failed(message: message)
            setMascot(.idle)
        }
    }

    /// Cycle the transport. Used by the toolbar toggle.
    func toggleTransport() {
        transport = transport == .memoryGrounded ? .fresh : .memoryGrounded
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
            updatedAt: Date(),
        )
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
                    MemoryUpsertRequest(content: message.content),
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

    private func finalizeAssistantTurn() {
        let assistant = Message(
            role: .assistant,
            content: pendingAssistant,
            sources: pendingSources,
        )
        messages.append(assistant)
        let spokenBody = pendingAssistant
        pendingAssistant = ""
        pendingSources = []
        schedulePersist()
        // HER-153 — speak reply iff the user's prompt was voice. Typed
        // prompts stay silent regardless of voice availability.
        if lastInputWasVoice {
            voice.speak(spokenBody)
        }
        lastInputWasVoice = false
    }

    /// Cancel the in-flight stream. Partial text already streamed is
    /// preserved as a complete assistant turn so the user can read it.
    /// Also silences Lumina mid-utterance if she's currently speaking.
    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        if voice.isSpeaking { voice.stopSpeaking() }
    }

    /// Wipe the conversation client-side and forget the server id. Also
    /// clears the cached snapshot so the next launch starts blank. The
    /// server-side conversation row stays (call `conversationsClient.delete`
    /// separately to wipe that too).
    func reset() {
        cancel()
        mascotDecayTask?.cancel()
        persistTask?.cancel()
        let oldID = conversationID
        conversationID = nil
        messages = []
        pendingAssistant = ""
        pendingSources = []
        fallbackNotice = nil
        stagedAttachment = nil
        phase = .idle
        mascotState = .idle
        if let store = historyStore, let oldID {
            Task { try? await store.clear(conversationID: oldID) }
        }
    }
}

/// Throwing stub returned by the back-compat init. Lets ChatViewModel
/// keep a non-optional `chatClient` so the runtime switch is total. Any
/// `.fresh` send through the convenience init throws — callers that
/// flip the toggle without supplying a real chat client will see a
/// clean error instead of a silent no-op.
private struct NoChatClient: ChatClientProtocol {
    func complete(_ request: ChatRequest) async throws -> ChatResponse {
        throw APIError.unauthorized
    }
}

private struct NoMemoryClient: MemoryClientProtocol {
    func upsert(_ request: MemoryUpsertRequest) async throws -> MemoryUpsertResponse {
        throw APIError.unauthorized
    }

    func get(id: UUID) async throws -> MemoryDTO {
        throw APIError.unauthorized
    }

    func patch(id: UUID, _ request: MemoryPatchRequest) async throws -> MemoryDTO {
        throw APIError.unauthorized
    }
}
