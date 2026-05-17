// LuminaVaultClient/LuminaVaultClient/Features/KB/SyncAndLearnViewModel.swift
// HER-36: drives the home-tab "Sync & Learn" button. Talks to POST
// /v1/kb-compile with a default request body — server compiles every
// vault file that has not been processed yet.
import Foundation
import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class SyncAndLearnViewModel {
    enum Phase: Equatable {
        case idle
        case syncing
        case done(memoriesIngested: Int, durationMs: Int?)
        case failed(message: String)
    }

    private let client: KBCompileClientProtocol

    var phase: Phase = .idle

    /// Auto-revert window after `.done` before going back to `.idle`. Long
    /// enough for the Rive mascot to land its `.happy` trigger but short
    /// enough that the button reads "ready" by the time the user looks back.
    private let happyDwell: Duration = .seconds(3)
    private var revertTask: Task<Void, Never>?

    init(client: KBCompileClientProtocol) {
        self.client = client
    }

    var mascotState: HermieMascotState {
        switch phase {
        case .syncing: .thinking
        case .done: .happy
        case .idle, .failed: .idle
        }
    }

    var isBusy: Bool {
        if case .syncing = phase { return true }
        return false
    }

    func sync() async {
        revertTask?.cancel()
        phase = .syncing
        do {
            let response = try await client.compile(KBCompileRequest())
            phase = .done(memoriesIngested: response.memoriesIngested, durationMs: response.durationMs)
            scheduleRevert()
        } catch {
            let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message: message)
        }
    }

    private func scheduleRevert() {
        revertTask = Task { [happyDwell] in
            try? await Task.sleep(for: happyDwell)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                if case .done = phase {
                    phase = .idle
                }
            }
        }
    }
}
