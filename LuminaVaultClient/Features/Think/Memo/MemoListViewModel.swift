// LuminaVaultClient/LuminaVaultClient/Features/Think/Memo/MemoListViewModel.swift
// HER-37: drives Lumina's Notebook — the list of memos saved by the user.
import Foundation
import SwiftUI

@Observable
@MainActor
final class MemoListViewModel {
    enum Phase: Equatable {
        case loading
        case loaded([MemoSummaryDTO])
        case failed(message: String)
    }

    private let client: MemoClientProtocol

    var phase: Phase = .loading

    init(client: MemoClientProtocol) {
        self.client = client
    }

    var memos: [MemoSummaryDTO] {
        if case let .loaded(memos) = phase { return memos }
        return []
    }

    func load() async {
        phase = .loading
        do {
            let response = try await client.list()
            phase = .loaded(response.memos)
        } catch {
            let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message: message)
        }
    }
}
