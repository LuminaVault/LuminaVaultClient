// LuminaVaultClient/LuminaVaultClient/Features/Reminders/RemindersListView.swift
//
// Reminders screen. Reached from the Home "Your Brain" Reminders tile.
// Consumes /v1/dashboard/reminders via RemindersClientProtocol. Modeled on
// TasksListView (loading / empty / failed states, lvBackground, pull to
// refresh).

import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class RemindersListViewModel {
    enum LoadState: Equatable { case loading, loaded, failed(String) }
    var state: LoadState = .loading
    var reminders: [ReminderDTO] = []
    private let client: RemindersClientProtocol

    init(client: RemindersClientProtocol) { self.client = client }

    func load() async {
        state = .loading
        do {
            reminders = try await client.list(limit: 100)
            state = .loaded
        } catch {
            state = .failed("Couldn't load reminders.")
        }
    }

    /// Pending = not yet fired, soonest first. Fired drop to a history group.
    var pending: [ReminderDTO] {
        reminders.filter { $0.firedAt == nil }.sorted { $0.fireAt < $1.fireAt }
    }
    var fired: [ReminderDTO] {
        reminders.filter { $0.firedAt != nil }.sorted { ($0.firedAt ?? $0.fireAt) > ($1.firedAt ?? $1.fireAt) }
    }
}

struct RemindersListView: View {

    @Environment(\.lvPalette) private var palette

    @State var vm: RemindersListViewModel

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Reminders")
        .lvBackground()
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    @ViewBuilder
    private var content: some View {
        switch vm.state {
        case .loading:
            ProgressView().tint(palette.primary)
        case .failed(let message):
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(Color.lvTextMuted)
                .padding()
        case .loaded where vm.reminders.isEmpty:
            LVEmptyState(
                mascot: .idle,
                headline: "No reminders.",
                supporting: "Reminders you schedule will appear here."
            )
        case .loaded:
            List {
                section("Upcoming", items: vm.pending, tint: palette.primary)
                section("Fired", items: vm.fired, tint: palette.textSecondary)
            }
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func section(_ title: String, items: [ReminderDTO], tint: Color) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { reminder in
                    HStack(spacing: 10) {
                        Circle().fill(tint).frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(reminder.title)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(palette.textPrimary)
                            if !reminder.body.isEmpty {
                                Text(reminder.body)
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        Text(reminder.fireAt, format: .dateTime.month().day().hour().minute())
                            .font(.system(size: 11))
                            .foregroundStyle(Color.lvTextMuted)
                    }
                    .listRowBackground(palette.backgroundBase.opacity(0.5))
                }
            }
        }
    }
}
