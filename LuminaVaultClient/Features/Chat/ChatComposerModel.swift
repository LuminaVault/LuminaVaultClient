// LuminaVaultClient/LuminaVaultClient/Features/Chat/ChatComposerModel.swift
//
// The composer's own observable scope.
//
// The draft text and the staged references used to live directly on
// `ChatViewModel`, which also owns `messages`. Because the `TextField` binds
// straight to that property, every keystroke marked the object holding the
// whole transcript as changed — so typing one character invalidated every view
// observing the conversation. Splitting the draft onto its own `@Observable`
// means a keystroke can only ever dirty the composer.
//
// `ChatViewModel` holds this as a `let`, so the reference itself never changes
// and the parent's observation never fires for it.
import Foundation

@Observable
@MainActor
final class ChatComposerModel {
    /// The draft message. Mutated on every keystroke.
    var text: String = ""

    /// Files, vault notes, photos and links whose extracted text rides into
    /// the next send as a context block. There is no per-message attachment
    /// contract on the server, so the text is inlined into the turn.
    var stagedReferences: [ChatViewModel.StagedAttachment] = []

    /// True when there is something worth sending, ignoring stream state.
    var hasContent: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !stagedReferences.isEmpty
    }

    /// Clear the draft after a successful send.
    func clear() {
        text = ""
        stagedReferences = []
    }
}
