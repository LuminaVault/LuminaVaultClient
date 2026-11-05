// LuminaVaultClient/LuminaVaultClient/Features/QuickAssistant/QuickAssistantModel.swift
//
// State behind the Quick Assistant card. One conversation per card session;
// `reset()` ends it. No UI here.
//
// Rules the model enforces:
//  * Nothing is sent unless the hybrid-execution gate says cloud. The card
//    needs server tools, so Private never sends and Balanced needs the cloud
//    fallback switched on.
//  * Actions come only from `assistant_action` frames, never from reply text.
//  * One turn at a time. A send while a turn is streaming is refused, which
//    cannot interleave two replies.
//  * `reset()` bumps a generation counter. Every await point re-checks it, so
//    a stream that outlives a reset cannot repopulate the state.
//  * Voice replies are spoken only after the stream has fully ended.
//  * The client never decides an action has expired; the server answers.
//  * `prepare` / `commit` (the local-execution path) are never called.
import Foundation
import LuminaVaultShared
import Observation

enum QuickAssistantPhase: Equatable {
    case idle
    case sending
    case blocked(String)
    case failed(String)
}

/// Whether the card may send, reusing the app-wide hybrid-execution decision.
enum QuickAssistantGate {
    static func evaluate(
        profile: HybridExecutionProfile,
        cloudFallbackEnabled: Bool,
        localFallbackEnabled: Bool,
        online: Bool
    ) -> HybridExecutionDecision {
        let decision = HybridExecutionCoordinator().decide(
            profile: profile,
            capabilities: HybridExecutionCapabilities(
                localAvailable: true,
                cloudAvailable: online,
                requiresCloudTool: true,
                contextFitsLocally: true,
                localFallbackEnabled: localFallbackEnabled,
                cloudFallbackEnabled: cloudFallbackEnabled
            )
        )
        // Offline is the actionable reason; the coordinator's wording blames
        // the fallback switch. Private keeps its own message.
        if case .unavailable = decision, !online, profile != .private {
            return .unavailable("You're offline. Quick Assistant needs a connection.")
        }
        return decision
    }
}

@Observable
@MainActor
final class QuickAssistantModel {
    private(set) var reply = ""
    private(set) var actions: [AssistantActionDTO] = []
    private(set) var phase: QuickAssistantPhase = .idle
    private(set) var conversationID: UUID?
    private(set) var pendingScreen: (AssistantScreenDTO, UUID?)?
    /// How each confirmed / cancelled action ended, from the server.
    private(set) var resolutions: [UUID: AssistantActionResolutionDTO] = [:]
    /// A failed confirm / cancel. The action stays actionable; the card shows this.
    private(set) var actionErrors: [UUID: String] = [:]
    /// Actions with a confirm / cancel in flight (disables double taps).
    private(set) var resolving: Set<UUID> = []

    private let conversations: any ConversationsClientProtocol
    private let actionsClient: any AssistantActionsClientProtocol
    private let settings: HybridExecutionSettingsStore
    private let synthesizer: any SpeechSynthesizing
    private let isOnline: @MainActor () -> Bool
    private var generation = 0

    init(
        conversations: any ConversationsClientProtocol,
        actions: any AssistantActionsClientProtocol,
        settings: HybridExecutionSettingsStore,
        synthesizer: any SpeechSynthesizing,
        isOnline: @escaping @MainActor () -> Bool
    ) {
        self.conversations = conversations
        actionsClient = actions
        self.settings = settings
        self.synthesizer = synthesizer
        self.isOnline = isOnline
    }

    // MARK: - Send

    func send(_ text: String, viaVoice: Bool, currentTab: String, activeSpaceID: UUID?) async {
        let content = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, phase != .sending else { return }

        let decision = QuickAssistantGate.evaluate(
            profile: settings.profile,
            cloudFallbackEnabled: settings.cloudFallbackEnabled,
            localFallbackEnabled: settings.localFallbackEnabled,
            online: isOnline()
        )
        switch decision {
        case let .unavailable(message):
            phase = .blocked(message)
            return
        case .local:
            // Unreachable while requiresCloudTool is true; never send locally.
            phase = .blocked("Quick Assistant needs the cloud.")
            return
        case .cloud:
            break
        }

        synthesizer.stop()
        reply = ""
        actions = []
        pendingScreen = nil
        resolutions = [:]
        actionErrors = [:]
        phase = .sending
        let gen = generation

        do {
            let id = try await ensureConversation()
            guard gen == generation else { return }
            let stream = conversations.streamReply(
                conversationID: id,
                request: MessageStreamRequest(
                    content: content,
                    quickAssistant: QuickAssistantContextDTO(currentTab: currentTab, activeSpaceID: activeSpaceID)
                )
            )
            for try await event in stream {
                guard gen == generation else { return }
                if let failure = apply(event) {
                    phase = .failed(failure)
                    return
                }
            }
            guard gen == generation else { return }
            phase = .idle
            if viaVoice { speakReply() }
        } catch {
            guard gen == generation else { return }
            phase = .failed(Self.message(for: error))
        }
    }

    private func ensureConversation() async throws -> UUID {
        if let conversationID { return conversationID }
        let gen = generation
        let dto = try await conversations.create(ConversationCreateRequest())
        // A reset while the create was in flight must not adopt the result.
        guard gen == generation else { throw CancellationError() }
        conversationID = dto.id
        return dto.id
    }

    /// Returns a failure message when the frame ends the turn in error.
    private func apply(_ event: QueryStreamEvent) -> String? {
        switch event {
        case let .token(delta):
            reply += delta
        case let .summary(final):
            if !final.isEmpty { reply = final }
        case let .assistantAction(action):
            guard !actions.contains(where: { $0.id == action.id }) else { return nil }
            actions.append(action)
            if action.kind == .openScreen {
                pendingScreen = (action.screen ?? .unknown, action.memoryID)
            }
        case let .error(message):
            return message
        case let .errorDetail(detail):
            return detail.message
        default:
            break // sources, routing, usage, follow-ups, unrecognized: not for this card
        }
        return nil
    }

    private func speakReply() {
        let spoken: String
        if let ask = actions.first(where: { $0.kind == .needsConfirm }) {
            spoken = ask.summary
        } else {
            spoken = reply
        }
        let trimmed = spoken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        synthesizer.speak(trimmed, onStart: {}, onFinish: {})
    }

    // MARK: - Confirm / cancel

    func confirm(_ action: AssistantActionDTO) async {
        await resolve(action) { try await $0.confirm(action.id) }
    }

    func cancel(_ action: AssistantActionDTO) async {
        await resolve(action) { try await $0.cancel(action.id) }
    }

    private func resolve(
        _ action: AssistantActionDTO,
        _ call: (any AssistantActionsClientProtocol) async throws -> AssistantActionResolutionDTO
    ) async {
        guard !resolving.contains(action.id) else { return }
        let gen = generation
        resolving.insert(action.id)
        actionErrors[action.id] = nil
        defer { if gen == generation { resolving.remove(action.id) } }
        do {
            // Sent even if `expiresAt` has passed: the server answers `.expired`.
            let resolution = try await call(actionsClient)
            guard gen == generation else { return }
            resolutions[action.id] = resolution
        } catch {
            guard gen == generation else { return }
            actionErrors[action.id] = Self.actionMessage(for: error)
        }
    }

    // MARK: - Reset

    func reset() {
        generation += 1
        synthesizer.stop()
        reply = ""
        actions = []
        pendingScreen = nil
        resolutions = [:]
        actionErrors = [:]
        resolving = []
        conversationID = nil
        phase = .idle
    }

    // MARK: - Messages

    private static func message(for error: any Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Try again."
    }

    private static func actionMessage(for error: any Error) -> String {
        if case let APIError.httpError(statusCode, _) = error, statusCode == 404 {
            return "This request is no longer available."
        }
        if case APIError.networkFailure = error {
            return "Couldn't reach Lumina. Check your connection and try again."
        }
        return message(for: error)
    }
}
