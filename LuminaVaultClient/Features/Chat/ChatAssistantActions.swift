// LuminaVaultClient/LuminaVaultClient/Features/Chat/ChatAssistantActions.swift
//
// What the assistant did in the app during a chat turn: a chip for each change
// it made, and a confirm card for each one it asks about first. The same
// frames the Quick Assistant card draws, kept per chat turn.
//
// The actions live in memory only. The server writes each confirm or cancel
// into the conversation as a line of its own, so a reloaded thread still says
// what happened; it just no longer offers the buttons.
import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class ChatAssistantActions: AssistantActionResolving {
    /// One action and the assistant message it sits under. `anchor` is nil
    /// while the turn that produced it is still streaming.
    struct Entry: Equatable {
        let action: AssistantActionDTO
        var anchor: UUID?
    }

    private(set) var entries: [Entry] = []
    private(set) var resolutions: [UUID: AssistantActionResolutionDTO] = [:]
    private(set) var actionErrors: [UUID: String] = [:]
    private(set) var resolving: Set<UUID> = []
    /// True while a reply is streaming. A card waits for the reply to end, as
    /// the Quick Assistant's does: the server saves the reply only then, and a
    /// confirm line must not land before the reply it answers.
    var isStreaming = false

    /// Called when a space, a note or a memory changed: at once for a `done`
    /// action, and after the server confirms a card.
    var onAppChange: ((AssistantResourceDTO) -> Void)?
    /// Called when a turn ends with an `openScreen` that goes somewhere.
    var onOpenScreen: ((QuickAssistantRoute) -> Void)?

    private let client: (any AssistantActionsClientProtocol)?
    /// The last `openScreen` of the turn in flight that goes somewhere.
    private var pendingRoute: QuickAssistantRoute?
    /// Bumped by `reset`, so an answer for a thread the user left is dropped.
    private var generation = 0

    init(client: (any AssistantActionsClientProtocol)?) {
        self.client = client
    }

    // MARK: - Frames

    func receive(_ action: AssistantActionDTO) {
        guard !entries.contains(where: { $0.action.id == action.id }) else { return }
        switch action.kind {
        case .done:
            entries.append(Entry(action: action, anchor: nil))
            if let resource = action.resource { onAppChange?(resource) }
        case .needsConfirm:
            entries.append(Entry(action: action, anchor: nil))
        case .openScreen:
            let route = QuickAssistantRoute.resolve(action)
            if route != .none { pendingRoute = route }
        case .needsPermission, .unknown:
            // Device permissions are asked for on the Quick Assistant card.
            // Chat has no tool that needs one.
            break
        }
    }

    /// The turn ended and its reply is `message`. Its actions move under it,
    /// and a screen it opened is opened now, unless a card is still waiting.
    func finishTurn(anchoredTo message: UUID?) {
        isStreaming = false
        for index in entries.indices where entries[index].anchor == nil {
            entries[index].anchor = message
        }
        let route = pendingRoute
        pendingRoute = nil
        guard let route else { return }
        let waiting = entries.contains { $0.action.kind == .needsConfirm && resolutions[$0.action.id] == nil }
        if !waiting { onOpenScreen?(route) }
    }

    /// The turn failed or was stopped. Changes that already happened keep
    /// their chips; a screen is not opened for a reply nobody got.
    func abandonTurn(anchoredTo message: UUID?) {
        pendingRoute = nil
        finishTurn(anchoredTo: message)
    }

    // MARK: - Reading

    /// Actions under `anchor`. Passing nil gives the ones still streaming and
    /// any whose message is no longer in `known`, so none is orphaned.
    func actions(anchoredTo anchor: UUID?, known: Set<UUID>) -> [AssistantActionDTO] {
        entries.compactMap { entry in
            if let anchor {
                return entry.anchor == anchor ? entry.action : nil
            }
            guard let own = entry.anchor else { return entry.action }
            return known.contains(own) ? nil : entry.action
        }
    }

    func confirmState(for action: AssistantActionDTO) -> QuickAssistantConfirmState {
        if let resolution = resolutions[action.id] { return .finished(resolution) }
        if resolving.contains(action.id) { return .resolving }
        if isStreaming { return .awaitingReply }
        return .ask(error: actionErrors[action.id])
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
        guard let client, !resolving.contains(action.id), resolutions[action.id] == nil else { return }
        let gen = generation
        resolving.insert(action.id)
        actionErrors[action.id] = nil
        defer { if gen == generation { resolving.remove(action.id) } }
        do {
            let resolution = try await call(client)
            guard gen == generation else { return }
            resolutions[action.id] = resolution
            if resolution.status == .confirmed, let resource = action.resource {
                onAppChange?(resource)
            }
        } catch {
            guard gen == generation else { return }
            actionErrors[action.id] = Self.message(for: error)
        }
    }

    /// A different thread, or a fresh one: nothing here belongs to it.
    func reset() {
        generation += 1
        entries = []
        resolutions = [:]
        actionErrors = [:]
        resolving = []
        pendingRoute = nil
        isStreaming = false
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case APIError.httpError(404, _):
            "This request is no longer available."
        case APIError.httpError(403, _):
            QuickAssistantModel.noWriteAccessMessage
        case APIError.networkFailure:
            "Couldn't reach Lumina. Check your connection and try again."
        default:
            (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Try again."
        }
    }
}

/// The chips and confirm cards of one chat turn.
struct ChatAssistantActionsView: View {
    let actions: [AssistantActionDTO]
    let model: ChatAssistantActions

    private var chips: [AssistantActionDTO] { actions.filter { $0.kind == .done } }
    private var cards: [AssistantActionDTO] { actions.filter { $0.kind == .needsConfirm } }

    var body: some View {
        if !actions.isEmpty {
            VStack(alignment: .leading, spacing: LVSpacing.sm) {
                if !chips.isEmpty {
                    LVFlowLayout(spacing: LVSpacing.sm) {
                        ForEach(chips, id: \.id) { QuickAssistantChip(summary: $0.summary) }
                    }
                }
                ForEach(cards, id: \.id) { action in
                    QuickAssistantConfirmCard(action: action, model: model)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
