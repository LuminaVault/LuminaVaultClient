// LuminaVaultClient/LuminaVaultClient/Features/Workspace/WorkspaceView.swift
//
// The agent's checkout on a phone: a file tree and the changed-file list,
// with the file or diff pushed as a detail screen.
//
// A phone gets a navigation stack rather than the side-by-side panes the web
// app uses. Two columns at this width means two cramped columns; a diff needs
// the whole screen to be readable at all.
//
// Read-only. Nothing here can stage, commit or push.

import LuminaVaultShared
import SwiftUI

struct WorkspaceView: View {
    @State private var viewModel: WorkspaceViewModel
    @State private var rootInput: String
    @Environment(\.lvPalette) private var palette

    /// Remembered between visits so the reader does not retype an absolute
    /// path every time. Per-device convenience only.
    @AppStorage("lv.workspace.root") private var rememberedRoot: String = ""

    init(client: any HermesWorkspaceClientProtocol) {
        _viewModel = State(initialValue: WorkspaceViewModel(client: client))
        _rootInput = State(initialValue: "")
    }

    var body: some View {
        List {
            repositoryField

            if viewModel.isUnsupported {
                // A configuration state, not a fault: nothing is broken, there
                // is simply no checkout to read.
                LVEmptyState(
                    headline: "No workspace to show",
                    supporting: "This account has no remote Hermes, so there is no checkout for Lumina to read."
                )
                .listRowSeparator(.hidden)
            } else if let error = viewModel.error {
                LVEmptyState(headline: "Could not read the workspace", supporting: error)
                    .listRowSeparator(.hidden)
            } else if !viewModel.root.isEmpty {
                changesSection
                filesSection
            }
        }
        .listStyle(.plain)
        .navigationTitle("Code")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !rememberedRoot.isEmpty, viewModel.root.isEmpty else { return }
            rootInput = rememberedRoot
            await viewModel.open(root: rememberedRoot)
        }
    }

    private var repositoryField: some View {
        Section {
            HStack(spacing: LVSpacing.sm) {
                TextField("/absolute/path/to/repo", text: $rootInput)
                    .font(.footnote.monospaced())
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .onSubmit { openRoot() }
                Button("Open", action: openRoot)
                    .font(.footnote.weight(.medium))
                    .disabled(rootInput.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } footer: {
            // Asked for rather than guessed, matching the server: defaulting to
            // the agent's working directory would make a typo silently show a
            // different tree.
            Text("Read-only. Nothing here can stage, commit or push.")
        }
    }

    @ViewBuilder
    private var changesSection: some View {
        if !viewModel.changes.isEmpty {
            Section {
                ForEach(viewModel.changes, id: \.path) { change in
                    NavigationLink {
                        WorkspaceDetailView(viewModel: viewModel, target: .diff(path: change.path))
                    } label: {
                        changeRow(change)
                    }
                }
            } header: {
                HStack {
                    Text("Changes")
                    Spacer()
                    Text("+\(viewModel.churn.added)  −\(viewModel.churn.removed)")
                        .monospacedDigit()
                }
            }
        }
    }

    private func changeRow(_ change: HermesWorkspaceChangeDTO) -> some View {
        HStack(spacing: LVSpacing.sm) {
            // The raw upstream word when it is not one of the familiar few, so
            // an unfamiliar state shows as itself.
            Text(Self.badge(for: change.status))
                .font(.caption2.monospaced())
                .foregroundStyle(palette.textSecondary)
                .frame(width: 16, alignment: .center)
            Text(change.path)
                .font(.footnote)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: LVSpacing.sm)
            Text("+\(change.added) −\(change.removed)")
                .font(.caption2.monospaced())
                .foregroundStyle(palette.textSecondary)
        }
    }

    private var filesSection: some View {
        Section {
            if viewModel.canGoUp {
                Button {
                    Task { await viewModel.goUp() }
                } label: {
                    Label("Up a level", systemImage: "chevron.up")
                        .font(.footnote)
                }
            }

            ForEach(viewModel.entries, id: \.path) { entry in
                if entry.isDirectory {
                    Button {
                        Task { await viewModel.open(entry: entry) }
                    } label: {
                        Label(entry.name, systemImage: "folder")
                            .font(.footnote.weight(.medium))
                    }
                } else {
                    NavigationLink {
                        WorkspaceDetailView(viewModel: viewModel, target: .file(path: entry.path))
                    } label: {
                        Label(entry.name, systemImage: "doc")
                            .font(.footnote)
                    }
                }
            }

            if viewModel.entries.isEmpty, !viewModel.isLoadingTree {
                Text("This folder is empty.")
                    .font(.footnote)
                    .foregroundStyle(palette.textSecondary)
            }
        } header: {
            Text(viewModel.cwd)
                .font(.caption2.monospaced())
                .lineLimit(1)
                .truncationMode(.head)
        }
    }

    private func openRoot() {
        let trimmed = rootInput.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        rememberedRoot = trimmed
        Task { await viewModel.open(root: trimmed) }
    }

    static func badge(for status: String) -> String {
        switch status {
        case "added": "A"
        case "deleted": "D"
        case "renamed": "R"
        case "untracked": "U"
        case "modified": "M"
        default: status
        }
    }
}
