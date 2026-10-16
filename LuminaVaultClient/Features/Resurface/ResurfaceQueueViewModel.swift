// LuminaVaultClient/LuminaVaultClient/Features/Resurface/ResurfaceQueueViewModel.swift
//
// "To revisit": the few memories worth seeing again today, one at a time.
//
// Home fetches a short queue up front (three) and shows its head as a card.
// Answering it — Keep, Soon, Later, Never — posts a review and moves on to
// the next without another fetch; the card goes once the queue is empty. The
// same instance backs the "To revisit" tile's count and the Daily review
// list, so an answer anywhere is reflected everywhere on Home at once.
//
// Every change to the queue is published to the "Today's memory" widget.

import Foundation
import LuminaVaultShared
import Observation
import WidgetKit

@Observable
@MainActor
final class ResurfaceQueueViewModel {
    enum Phase: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    static let defaultLimit = 3

    private(set) var phase: Phase = .loading
    /// Best first. The card shows `items.first`.
    private(set) var items: [ResurfaceItemDTO] = []
    /// What the last answer did, in a sentence: "See it again in 3 days".
    /// The card shows it briefly, then the view clears it.
    private(set) var confirmation: String?
    /// The memory whose answer is in flight; its buttons are disabled.
    private(set) var pendingMemoryID: UUID?
    /// An answer that did not land. The item stays where it was.
    var actionError: String?

    var current: ResurfaceItemDTO? {
        items.first
    }

    /// The card's row stays while there is something to show or a
    /// confirmation to finish showing after the last item went.
    var showsCard: Bool {
        current != nil || confirmation != nil
    }

    private let resurfaceClient: any ResurfaceClientProtocol
    private let memoryClient: any MemoryClientProtocol
    private let limit: Int
    private let publish: @MainActor ([ResurfaceItemDTO]) -> Void
    private let now: @Sendable () -> Date

    init(
        resurfaceClient: any ResurfaceClientProtocol,
        memoryClient: any MemoryClientProtocol,
        limit: Int = ResurfaceQueueViewModel.defaultLimit,
        publish: @escaping @MainActor ([ResurfaceItemDTO]) -> Void = ResurfaceWidgetPublisher.publish,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.resurfaceClient = resurfaceClient
        self.memoryClient = memoryClient
        self.limit = limit
        self.publish = publish
        self.now = now
    }

    /// First load and pull-to-refresh. A failed refresh keeps the queue on
    /// screen: a memory worth revisiting does not stop being one because a
    /// pull dropped.
    func load() async {
        do {
            let response = try await resurfaceClient.resurface(limit: limit)
            items = response.items
            phase = .loaded
            publish(items)
        } catch {
            if case .loaded = phase { return }
            phase = .failed(error.localizedDescription)
        }
    }

    /// Answers one memory and moves on. On failure the item stays and
    /// `actionError` says why.
    func perform(_ action: MemoryReviewAction, on item: ResurfaceItemDTO) async {
        guard pendingMemoryID == nil else { return }
        pendingMemoryID = item.memoryId
        actionError = nil
        defer { pendingMemoryID = nil }
        do {
            let response = try await memoryClient.review(id: item.memoryId, action: action)
            items.removeAll { $0.memoryId == item.memoryId }
            confirmation = Self.confirmation(for: action, nextReviewAt: response.nextReviewAt, now: now())
            publish(items)
        } catch {
            actionError = "Couldn't save that. Try again."
        }
    }

    func clearConfirmation() {
        confirmation = nil
    }

    // MARK: - Copy

    /// The sentence after an answer. Uses the server's date when it sent
    /// one, and the action's promise when it did not.
    nonisolated static func confirmation(
        for action: MemoryReviewAction,
        nextReviewAt: Date?,
        now: Date
    ) -> String {
        switch action {
        case .kept:
            return "Kept. It stays in your vault."
        case .never:
            return "Won't show this one again."
        case .soon, .later:
            guard let nextReviewAt else {
                return action == .soon ? "See it again in a few days" : "See it again in about a month"
            }
            return "See it again \(relativeDays(from: now, to: nextReviewAt))"
        }
    }

    /// "tomorrow", "in 3 days", "in 2 weeks", "in about a month",
    /// "in 3 months". Whole days, rounded up, so a review due in 2.2 days
    /// does not read as "in 2 days" and then arrive on the third.
    nonisolated static func relativeDays(from now: Date, to date: Date) -> String {
        let days = max(1, Int((date.timeIntervalSince(now) / 86400).rounded(.up)))
        switch days {
        case 1: return "tomorrow"
        case ..<14: return "in \(days) days"
        case ..<28: return "in \(days / 7) weeks"
        case ..<60: return "in about a month"
        default: return "in \(days / 30) months"
        }
    }
}

/// App side of the "Today's memory" widget: turns the queue into the App
/// Group snapshot and asks WidgetKit to redraw.
enum ResurfaceWidgetPublisher {
    static func publish(_ items: [ResurfaceItemDTO]) {
        ResurfaceWidgetStore.shared.write(snapshot(for: items, at: Date()))
        WidgetCenter.shared.reloadTimelines(ofKind: ResurfaceWidgetStore.widgetKind)
    }

    nonisolated static func snapshot(for items: [ResurfaceItemDTO], at date: Date) -> ResurfaceWidgetSnapshot {
        ResurfaceWidgetSnapshot(
            items: items.map { ResurfaceWidgetItem(memoryId: $0.memoryId, snippet: $0.snippet, why: $0.why) },
            updatedAt: date
        )
    }
}
