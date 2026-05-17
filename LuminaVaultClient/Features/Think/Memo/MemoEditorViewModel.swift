// LuminaVaultClient/LuminaVaultClient/Features/Think/Memo/MemoEditorViewModel.swift
// HER-37: drives the Memo creation flow reached from any insight card.
//
// Scaffold-vs-impl: the editor surfaces a topic field + optional hint;
// the actual markdown body is produced by the server-side agent loop in
// `POST /v1/memos`. A live rich-markdown editor + LuminaSuggestionsSidebar
// content land in HER-37b.
import Foundation
import SwiftUI

@Observable
@MainActor
final class MemoEditorViewModel {
    enum Phase: Equatable {
        case editing
        case saving
        case saved(MemoResponse)
        case failed(message: String)
    }

    enum Event: String {
        case opened = "her37.memo.opened"
        case saved = "her37.memo.saved"
        case failed = "her37.memo.save_failed"
    }

    private let client: MemoClientProtocol

    var phase: Phase = .editing
    var topic: String
    var hint: String

    init(client: MemoClientProtocol, seed: MemoRequest? = nil) {
        self.client = client
        self.topic = seed?.topic ?? ""
        self.hint = seed?.hint ?? ""
    }

    var isBusy: Bool {
        if case .saving = phase { return true }
        return false
    }

    var canSave: Bool {
        !topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isBusy
    }

    func save() async {
        let trimmedTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHint = hint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTopic.isEmpty else { return }
        phase = .saving
        let request = MemoRequest(
            topic: trimmedTopic,
            hint: trimmedHint.isEmpty ? nil : trimmedHint,
            save: true,
        )
        do {
            let response = try await client.generate(request)
            phase = .saved(response)
        } catch {
            let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message: message)
        }
    }
}
