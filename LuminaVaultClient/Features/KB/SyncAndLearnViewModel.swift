// LuminaVaultClient/LuminaVaultClient/Features/KB/SyncAndLearnViewModel.swift
// HER-36: drives the home-tab "Sync & Learn" button. Talks to POST
// /v1/kb-compile with a default request body — server compiles every
// vault file that has not been processed yet.
import Foundation
import LuminaVaultShared
import SwiftUI
import PostHog

@Observable
@MainActor
final class SyncAndLearnViewModel {
    enum Phase: Equatable {
        case idle
        case syncing
        case done(memoriesIngested: Int, durationMs: Int?)
        /// HER-39 — user tapped Sync while offline (or the network dropped
        /// mid-call). The compile operation is on the queue and will be
        /// replayed automatically when reachability returns.
        case queued
        case failed(message: String)
    }

    /// HER-39 — accepts either a `VaultRepository` (online-first w/ offline
    /// queueing) or a plain `KBCompileClientProtocol` (for tests + the
    /// legacy direct-call path). The repository is the production wiring;
    /// the protocol fallback keeps existing mocks compiling.
    private let repository: VaultRepository?
    private let client: KBCompileClientProtocol?

    var phase: Phase = .idle

    /// Auto-revert window after `.done` before going back to `.idle`. Long
    /// enough for the Rive mascot to land its `.happy` trigger but short
    /// enough that the button reads "ready" by the time the user looks back.
    private let happyDwell: Duration = .seconds(3)
    private var revertTask: Task<Void, Never>?

    init(client: KBCompileClientProtocol) {
        self.client = client
        self.repository = nil
    }

    init(repository: VaultRepository) {
        self.repository = repository
        self.client = nil
    }

    var mascotState: HermieMascotState {
        switch phase {
        case .syncing: .thinking
        case .done: .happy
        case .idle, .failed, .queued: .idle
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
            if let repository {
                switch try await repository.compile() {
                case let .synced(response):
                    phase = .done(memoriesIngested: response.memoriesIngested, durationMs: response.durationMs)
                    var props: [String: Any] = ["memories_ingested": response.memoriesIngested]
                    if let ms = response.durationMs { props["duration_ms"] = ms }
                    PostHogSDK.shared.capture("kb_compile_completed", properties: props)
                    scheduleRevert()
                case .queued:
                    phase = .queued
                    PostHogSDK.shared.capture("kb_compile_queued_offline")
                }
            } else if let client {
                let response = try await client.compile(KBCompileRequest())
                phase = .done(memoriesIngested: response.memoriesIngested, durationMs: response.durationMs)
                var props: [String: Any] = ["memories_ingested": response.memoriesIngested]
                if let ms = response.durationMs { props["duration_ms"] = ms }
                PostHogSDK.shared.capture("kb_compile_completed", properties: props)
                scheduleRevert()
            }
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
