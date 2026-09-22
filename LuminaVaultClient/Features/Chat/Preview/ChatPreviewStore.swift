// LuminaVaultClient/LuminaVaultClient/Features/Chat/Preview/ChatPreviewStore.swift
//
// State for the chat preview pane.
//
// The rule this type exists to enforce, from the desktop design contract and
// the web `PreviewStore`: **a tool producing something must not open a pane,
// move focus or navigate.** A pane that opens itself mid-answer steals the
// reader's place exactly when they are most likely to be reading.
//
// So the two actions are two functions, and only one can open the pane:
//
//   registerCandidate(_:)  never opens. Makes an affordance available.
//   open(_:)               opens. Only from a user gesture or a deep link.

import Foundation
import Observation

@Observable
@MainActor
final class ChatPreviewStore {
    /// Whether the pane is showing. Only `open`/`close` move this.
    private(set) var isOpen = false
    private(set) var target: ChatPreviewTarget?
    /// Offered but not shown. Newest first, deduped, capped so a long run
    /// cannot grow it without bound.
    private(set) var candidates: [ChatPreviewTarget] = []

    static let maxCandidates = 24

    /// Note that something is previewable. **Never opens the pane.** If you
    /// want the pane to appear, you want `open(_:)`, from a tap.
    func registerCandidate(_ candidate: ChatPreviewTarget) {
        guard !candidates.contains(candidate) else { return }
        candidates = Array(([candidate] + candidates).prefix(Self.maxCandidates))
    }

    func open(_ target: ChatPreviewTarget) {
        self.target = target
        isOpen = true
    }

    /// Opens from a deep link. A bad address lands on the conversation.
    @discardableResult
    func open(address: String?) -> Bool {
        guard let address, let target = ChatPreviewTarget(address: address) else { return false }
        open(target)
        return true
    }

    func close() {
        isOpen = false
    }

    /// Candidates belong to the conversation that produced them; carrying
    /// them over would offer a preview of someone else's turn.
    func reset() {
        candidates = []
        target = nil
        isOpen = false
    }
}
