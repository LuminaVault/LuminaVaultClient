// LuminaVaultClient/LuminaVaultClient/Features/Tasks/TasksListView.swift
//
// HER-246 — Tasks screen. Consumes /v1/tasks (HER-244 stub). Empty
// until real job tracking lands.

import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class TasksListViewModel {
    enum LoadState: Equatable { case loading, loaded, failed(String) }
    var state: LoadState = .loading
    var tasks: [TaskDTO] = []
    private let client: TasksClientProtocol

    init(client: TasksClientProtocol) { self.client = client }

    func load() async {
        state = .loading
        do {
            let response = try await client.list(state: nil, limit: 50)
            tasks = response.tasks
            state = .loaded
        } catch {
            state = .failed("Couldn't load tasks.")
        }
    }

    var running: [TaskDTO] { tasks.filter { $0.state == .running } }
    var queued: [TaskDTO] { tasks.filter { $0.state == .queued } }
    var completed: [TaskDTO] { tasks.filter { $0.state == .completed } }
    var failed: [TaskDTO] { tasks.filter { $0.state == .failed } }
}

struct TasksListView: View {

    @Environment(\.lvPalette) private var palette

    @State var vm: TasksListViewModel

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Tasks")
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
        case .loaded where vm.tasks.isEmpty:
            LVEmptyState(
                mascot: .idle,
                headline: "Inbox zero.",
                supporting: "Long-running Hermes operations will appear here."
            )
        case .loaded:
            List {
                section("Running", items: vm.running, tint: palette.primary)
                section("Queued", items: vm.queued, tint: palette.textSecondary)
                section("Completed", items: vm.completed, tint: palette.accent)
                section("Failed", items: vm.failed, tint: .red)
            }
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func section(_ title: String, items: [TaskDTO], tint: Color) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { task in
                    HStack(spacing: 10) {
                        Circle().fill(tint).frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.label)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(palette.textPrimary)
                            if let progress = task.progress {
                                ProgressView(value: progress).tint(tint)
                            }
                        }
                        Spacer()
                        if let elapsed = task.elapsedSeconds {
                            Text("\(elapsed)s")
                                .font(.system(size: 11))
                                .foregroundStyle(Color.lvTextMuted)
                        }
                    }
                    .listRowBackground(palette.backgroundBase.opacity(0.5))
                }
            }
        }
    }
}
