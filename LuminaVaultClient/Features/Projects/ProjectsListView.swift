// LuminaVaultClient/LuminaVaultClient/Features/Projects/ProjectsListView.swift
//
// Projects screen. Reached from the Home "Your Brain" Projects tile.
// Consumes /v1/dashboard/projects via ProjectsClientProtocol. Modeled on
// TasksListView (loading / empty / failed states, lvBackground, pull to
// refresh).

import LuminaVaultShared
import SwiftUI

@Observable
@MainActor
final class ProjectsListViewModel {
    enum LoadState: Equatable { case loading, loaded, failed(String) }
    var state: LoadState = .loading
    var projects: [ProjectDTO] = []
    private let client: ProjectsClientProtocol

    init(client: ProjectsClientProtocol) { self.client = client }

    func load() async {
        state = .loading
        do {
            projects = try await client.list(limit: 100)
            state = .loaded
        } catch {
            state = .failed("Couldn't load projects.")
        }
    }

    var active: [ProjectDTO] { projects.filter { !$0.archived } }
    var archived: [ProjectDTO] { projects.filter { $0.archived } }
}

struct ProjectsListView: View {

    @Environment(\.lvPalette) private var palette

    @State var vm: ProjectsListViewModel

    var body: some View {
        ZStack {
            palette.backgroundBase.ignoresSafeArea()
            content
        }
        .navigationTitle("Projects")
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
        case .loaded where vm.projects.isEmpty:
            LVEmptyState(
                mascot: .idle,
                headline: "No projects yet.",
                supporting: "Group related work into projects to track it here."
            )
        case .loaded:
            List {
                section("Active", items: vm.active, tint: palette.primary)
                section("Archived", items: vm.archived, tint: palette.textSecondary)
            }
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private func section(_ title: String, items: [ProjectDTO], tint: Color) -> some View {
        if !items.isEmpty {
            Section(title) {
                ForEach(items) { project in
                    HStack(spacing: 10) {
                        Circle().fill(tint).frame(width: 6, height: 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.name)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(palette.textPrimary)
                            if let description = project.description, !description.isEmpty {
                                Text(description)
                                    .font(.system(size: 12))
                                    .foregroundStyle(palette.textSecondary)
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if let todoCount = project.todoCount {
                            Text("\(todoCount)")
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
