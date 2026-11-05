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
//  * An `openScreen` routes when the turn ends cleanly, never when its frame
//    arrives (closing the card cancels the stream, so an early route would cut
//    the reply off), and never after a failure. A confirm card the user has not
//    answered holds the screen back instead: closing would discard it.
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
        // The coordinator's wording is written for chat. Each case here says
        // what the card needs and names the Settings control that fixes it
        // (Settings > Intelligence > Hybrid execution).
        guard case .unavailable = decision else { return decision }
        if profile == .private { return .unavailable(privateMessage) }
        if !online { return .unavailable(offlineMessage) }
        if profile == .balanced, !cloudFallbackEnabled { return .unavailable(balancedMessage) }
        return decision
    }

    static let privateMessage =
        "Your Execution profile is Private, so nothing is sent to Lumina. To use Quick Assistant, switch it to Balanced or Quality in Settings > Intelligence."
    static let balancedMessage =
        "Quick Assistant needs the cloud. Turn on Allow cloud fallback in Settings > Intelligence, or switch the Execution profile to Quality."
    static let offlineMessage =
        "You're offline. Quick Assistant needs a connection."
    static let emptyReplyMessage = "Lumina didn't answer. Try again."
    static let cutOffMessage = "The reply was cut off. Try again."
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
    /// Called once when a turn ends cleanly with an `openScreen` that goes somewhere
    /// and nothing left to answer. The shell closes the card and routes.
    var onOpenScreen: ((QuickAssistantRoute) -> Void)?
    /// The screen an `openScreen` named when the turn ended with a confirm card
    /// still unanswered. The card shows it as a row to tap instead of routing.
    private(set) var heldScreenRoute: QuickAssistantRoute?
    /// While the app is in the background a finished voice turn is not read out.
    /// The text is there on return.
    var isSpeechSuspended = false

    private let conversations: any ConversationsClientProtocol
    private let actionsClient: any AssistantActionsClientProtocol
    private let settings: HybridExecutionSettingsStore
    private let synthesizer: any SpeechSynthesizing
    private let isOnline: @MainActor () -> Bool
    private var generation = 0
    private var streamTask: Task<Void, Never>?

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

        // Clear first so a blocked turn never shows the previous turn's cards.
        synthesizer.stop()
        reply = ""
        actions = []
        pendingScreen = nil
        heldScreenRoute = nil
        resolutions = [:]
        actionErrors = [:]

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

        phase = .sending
        let gen = generation
        // Held so `reset()` can cancel it: dismissing the card closes the
        // connection even when the server never answers.
        let task = Task { await self.stream(content, viaVoice: viaVoice, currentTab: currentTab, activeSpaceID: activeSpaceID, gen: gen) }
        streamTask = task
        await task.value
        if gen == generation { streamTask = nil }
    }

    private func stream(_ content: String, viaVoice: Bool, currentTab: String, activeSpaceID: UUID?, gen: Int) async {
        do {
            let id = try await ensureConversation()
            guard gen == generation else { return }
            let events = conversations.streamReply(
                conversationID: id,
                request: MessageStreamRequest(
                    content: content,
                    quickAssistant: QuickAssistantContextDTO(currentTab: currentTab, activeSpaceID: activeSpaceID)
                )
            )
            var sawDone = false
            for try await event in events {
                guard gen == generation, !Task.isCancelled else { return endCancelled(gen) }
                if case .done = event { sawDone = true }
                if let failure = apply(event) {
                    phase = .failed(failure)
                    return
                }
            }
            guard gen == generation, !Task.isCancelled else { return endCancelled(gen) }
            // Every normal server end sends `done` or an error frame, so a
            // close without one is a cut-off connection. Keep what arrived.
            if reply.isEmpty, actions.isEmpty {
                phase = .failed(QuickAssistantGate.emptyReplyMessage)
            } else if !sawDone {
                phase = .failed(QuickAssistantGate.cutOffMessage)
            } else {
                phase = .idle
                if viaVoice { speakReply() }
                routePendingScreen()
            }
        } catch {
            guard gen == generation else { return }
            // `reset()` bumps the generation, so a cancellation anyone asked for
            // returned above or has `Task.isCancelled` set. A cancellation error
            // with neither is the system dropping the stream (iOS tearing down a
            // connection): the reply is cut off, not finished.
            if Task.isCancelled { return endCancelled(gen) }
            if APIError.isBenignCancellation(error) {
                phase = .failed(QuickAssistantGate.cutOffMessage)
                return
            }
            phase = .failed(Self.message(for: error))
        }
    }

    private func endCancelled(_ gen: Int) {
        if gen == generation { phase = .idle }
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

    /// The turn ended cleanly. A routed screen closes the card, which stops any
    /// speech still going: accepted, the user asked to be taken there.
    private func routePendingScreen() {
        guard let (screen, memoryID) = pendingScreen else { return }
        let route = QuickAssistantRoute.resolve(screen, memoryID: memoryID)
        guard route != .none else { return }
        if actions.contains(where: { $0.kind == .needsConfirm && resolutions[$0.id] == nil }) {
            heldScreenRoute = route
        } else {
            onOpenScreen?(route)
        }
    }

    private func speakReply() {
        guard !isSpeechSuspended else { return }
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
        guard !resolving.contains(action.id), resolutions[action.id] == nil else { return }
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
        streamTask?.cancel()
        streamTask = nil
        synthesizer.stop()
        reply = ""
        actions = []
        pendingScreen = nil
        heldScreenRoute = nil
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
