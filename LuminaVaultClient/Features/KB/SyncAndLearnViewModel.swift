// LuminaVaultClient/LuminaVaultClient/Features/KB/SyncAndLearnViewModel.swift
// HER-108 — drives the home-tab "Sync & Learn" surface. Combines:
//   * HER-293 pending-count probe → disable button when nothing to learn.
//   * HER-288 WS subscription → live progress microcopy + memory list build.
//   * HER-290 PATCH approve/reject → review the freshly-saved memories.
// Pre-HER-108 the screen just spun and showed a final count.
import Foundation
import LuminaVaultShared
import PostHog
import SwiftUI

@Observable
@MainActor
final class SyncAndLearnViewModel {
    enum Phase: Equatable {
        case idle
        case syncing
        case reviewing
        case done(memoriesIngested: Int)
        /// HER-39 — offline-queued. Local CTA goes back to idle once the
        /// reachability daemon replays.
        case queued
        case failed(message: String)
    }

    // MARK: - Dependencies

    /// HER-39 — `VaultRepository` is the production path (online-first with
    /// offline queue). `KBCompileClientProtocol` is the legacy direct-call
    /// fallback retained for HomeView tests.
    private let repository: VaultRepository?
    private let client: KBCompileClientProtocol?
    /// HER-293 — cheap pending probe used to populate `pendingFiles` on
    /// init and refresh.
    private let pendingClient: KBCompileClientProtocol
    /// HER-288 — WS subscription opened just before each kb-compile run.
    private let webSocket: KBCompileWebSocketClientProtocol?
    /// HER-290 — PATCH approve/reject. Optional so test fixtures that don't
    /// need approve/reject can pass nil.
    private let memoryClient: MemoryClientProtocol?

    // MARK: - State

    var phase: Phase = .idle
    /// HER-293 — drives `isDisabled`. Refreshed on `.task` + after every run.
    var pendingFiles: Int = 0
    /// HER-288 — latest progress event for caption rendering.
    var lastProgressEvent: KBCompileProgressEvent?
    /// HER-288 — accumulated newly saved memories. Empty until the WS stream
    /// emits `.memorySaved` frames during a run.
    var savedMemories: [MemoryDTO] = []
    /// HER-108 — increment to trigger ConfettiSwiftUI's `.confettiCannon`.
    var confettiTrigger: Int = 0

    /// Auto-revert window after `.done` before going back to `.idle`. Long
    /// enough for the Rive mascot to land its `.happy` trigger but short
    /// enough that the button reads "ready" by the time the user looks back.
    private let happyDwell: Duration = .seconds(3)
    private var revertTask: Task<Void, Never>?
    private var wsTask: Task<Void, Never>?

    // MARK: - Init

    init(
        client: KBCompileClientProtocol,
        webSocket: KBCompileWebSocketClientProtocol? = nil,
        memoryClient: MemoryClientProtocol? = nil,
    ) {
        self.client = client
        self.repository = nil
        self.pendingClient = client
        self.webSocket = webSocket
        self.memoryClient = memoryClient
    }

    init(
        repository: VaultRepository,
        pendingClient: KBCompileClientProtocol,
        webSocket: KBCompileWebSocketClientProtocol? = nil,
        memoryClient: MemoryClientProtocol? = nil,
    ) {
        self.repository = repository
        self.client = nil
        self.pendingClient = pendingClient
        self.webSocket = webSocket
        self.memoryClient = memoryClient
    }

    // MARK: - Derived UI state

    var mascotState: HermieMascotState {
        switch phase {
        case .syncing: .thinking
        case .done, .reviewing: .happy
        case .idle, .failed, .queued: .idle
        }
    }

    var isBusy: Bool {
        if case .syncing = phase { return true }
        return false
    }

    /// HER-108 — button disabled while busy or when nothing's queued.
    var isDisabled: Bool {
        if isBusy { return true }
        if case .reviewing = phase { return true }
        return pendingFiles == 0
    }

    // MARK: - Pending probe

    /// HER-293 — refreshes `pendingFiles` from the cheap probe. Swallows
    /// errors silently: a transient failure shouldn't hide the button.
    func refreshPending() async {
        do {
            let response = try await pendingClient.pending()
            pendingFiles = response.pendingFiles
        } catch {
            // Leave pendingFiles unchanged; user can retry by re-focusing.
        }
    }

    // MARK: - Sync run

    func sync() async {
        revertTask?.cancel()
        wsTask?.cancel()
        lastProgressEvent = nil
        savedMemories = []
        phase = .syncing

        // HER-288 — start the WS pump BEFORE the POST so we don't miss
        // early `.started` / `.preparing` frames.
        if let webSocket {
            let stream = webSocket.events()
            wsTask = Task { [weak self] in
                for await event in stream {
                    await self?.handle(event: event)
                }
            }
        }

        do {
            if let repository {
                switch try await repository.compile() {
                case let .synced(response):
                    finalize(response: response)
                case .queued:
                    phase = .queued
                    await webSocket?.disconnect()
                    PostHogSDK.shared.capture("kb_compile_queued_offline")
                }
            } else if let client {
                let response = try await client.compile(KBCompileRequest())
                finalize(response: response)
            }
        } catch {
            await webSocket?.disconnect()
            let message = (error as? APIError)?.errorDescription ?? error.localizedDescription
            phase = .failed(message: message)
        }

        await refreshPending()
    }

    private func finalize(response: KBCompileResponse) {
        var props: [String: Any] = ["memories_ingested": response.memoriesIngested]
        if let ms = response.durationMs { props["duration_ms"] = ms }
        PostHogSDK.shared.capture("kb_compile_completed", properties: props)

        // HER-290 — if the server flagged memories pending review, show the
        // review sheet. Otherwise short-circuit to a brief `.done` then idle.
        if !savedMemories.isEmpty {
            phase = .reviewing
            confettiTrigger += 1
        } else {
            phase = .done(memoriesIngested: response.memoriesIngested)
            if response.memoriesIngested > 0 {
                confettiTrigger += 1
            }
            scheduleRevert()
        }

        let ws = webSocket
        Task { await ws?.disconnect() }
    }

    // MARK: - WS event handler

    private func handle(event: KBCompileProgressEvent) {
        lastProgressEvent = event
        switch event {
        case .memorySaved(let payload):
            // HER-290 — collect for the review sheet. Skip if duplicate (WS
            // and HTTP response may report the same memory; dedup by id).
            if !savedMemories.contains(where: { $0.id == payload.memory.id }) {
                savedMemories.append(payload.memory)
            }
        case .completed, .error:
            // Final frame handled by the HTTP response path. Leave the WS
            // task to terminate naturally when the connection drops.
            break
        case .started, .preparing, .thinking:
            break
        }
    }

    // MARK: - Memory review actions

    /// HER-290 — PATCH `reviewState=approved`. Removes the memory from the
    /// review list optimistically; rolls back on failure.
    func approve(_ memory: MemoryDTO) async {
        await patchReview(memory, to: MemoryReviewState.approved)
    }

    /// HER-290 — PATCH `reviewState=rejected`. Server also lands the source
    /// + content_hash on the kb-compile reject list so future runs skip it.
    func reject(_ memory: MemoryDTO) async {
        await patchReview(memory, to: MemoryReviewState.rejected)
    }

    private func patchReview(_ memory: MemoryDTO, to target: String) async {
        guard let memoryClient else { return }
        let original = savedMemories
        savedMemories.removeAll(where: { $0.id == memory.id })
        if savedMemories.isEmpty, case .reviewing = phase {
            phase = .done(memoriesIngested: original.count)
            scheduleRevert()
        }
        do {
            _ = try await memoryClient.patch(
                id: memory.id,
                MemoryPatchRequest(reviewState: target),
            )
            PostHogSDK.shared.capture(
                "memory_review_action",
                properties: ["action": target],
            )
        } catch {
            // Roll back optimistic removal.
            savedMemories = original
            phase = .reviewing
        }
    }

    /// HER-108 — user dismissed the review sheet without approving or
    /// rejecting every memory. Treat as accepted (the memory stays
    /// `pending` server-side until the next visit).
    func dismissReview() {
        phase = .done(memoriesIngested: savedMemories.count)
        savedMemories = []
        scheduleRevert()
    }

    // MARK: - Helpers

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
