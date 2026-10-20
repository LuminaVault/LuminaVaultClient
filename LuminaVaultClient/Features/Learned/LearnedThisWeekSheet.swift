// LuminaVaultClient/LuminaVaultClient/Features/Learned/LearnedThisWeekSheet.swift
//
// "What I learned this week" — what Lumina picked up about you and wants
// confirmed. "About you" holds proposed SOUL.md changes (Keep / Forget);
// "Your decisions & preferences" holds new memories of those kinds (Keep /
// Edit / Forget). Opened from Home's "Confirm what I learned" row and from a
// `learned` push (`luminavault://learned`).
//
// Edit opens the memory in its editor; when that sheet closes the digest is
// read again, since an edit can change what the snippet says.

import LuminaVaultShared
import SwiftUI

struct LearnedThisWeekSheet: View {
    @State private var vm: LearnedThisWeekViewModel
    /// The memory open in the editor.
    @State private var editing: LearnedMemoryLink?
    /// Bumped to read the digest again: after the editor closes, and on
    /// "Try again". Zero is the first load.
    @State private var reloadToken = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.lvPalette) private var palette

    private let memoryClient: any MemoryClientProtocol
    private let spacesClient: (any SpacesClientProtocol)?

    init(
        viewModel: LearnedThisWeekViewModel,
        memoryClient: any MemoryClientProtocol,
        spacesClient: (any SpacesClientProtocol)? = nil
    ) {
        _vm = State(initialValue: viewModel)
        self.memoryClient = memoryClient
        self.spacesClient = spacesClient
    }

    var body: some View {
        NavigationStack {
            content
                .background(palette.backgroundBase)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
                .task(id: reloadToken) { await vm.load() }
                .sheet(item: $editing, onDismiss: { reloadToken += 1 }, content: { link in
                    MemoryDetailSheet(
                        memoryID: link.id,
                        client: memoryClient,
                        spacesClient: spacesClient,
                        startsEditing: true
                    )
                })
        }
    }

    // MARK: - States

    @ViewBuilder private var content: some View {
        switch vm.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading what I learned")
        case let .failed(message):
            ContentUnavailableView {
                Label(message, systemImage: "sparkles")
            } actions: {
                Button("Try again") { reloadToken += 1 }
            }
        case .loaded:
            list
        }
    }

    private var list: some View {
        List {
            Section {
                header
                    .listRowInsets(EdgeInsets(top: 0, leading: LVSpacing.xs, bottom: LVSpacing.xs, trailing: LVSpacing.xs))
                    .listRowBackground(Color.clear)
            }

            if vm.isEmpty {
                Section {
                    emptyState
                        .listRowBackground(Color.clear)
                }
            }

            if !vm.soulChanges.isEmpty {
                Section {
                    ForEach(vm.soulChanges) { change in
                        LearnedSoulChangeRow(
                            change: change,
                            isPending: vm.pendingIDs.contains(change.id),
                            errorMessage: vm.errorMessage(for: change.id),
                            onKeep: { Task { await vm.keep(change) } },
                            onForget: { Task { await vm.forget(change) } }
                        )
                    }
                } header: {
                    Text("About you")
                } footer: {
                    Text("Kept changes go into how Lumina understands you.")
                }
            }

            if !vm.memories.isEmpty {
                Section("Your decisions & preferences") {
                    ForEach(vm.memories) { memory in
                        LearnedMemoryRow(
                            memory: memory,
                            isPending: vm.pendingIDs.contains(memory.id),
                            errorMessage: vm.errorMessage(for: memory.id),
                            onKeep: { Task { await vm.keep(memory) } },
                            onEdit: { editing = LearnedMemoryLink(id: memory.id) },
                            onForget: { Task { await vm.forget(memory) } }
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .refreshable { await vm.load() }
        // Reduced motion drops the slide (see `lvAnimation`).
        .lvAnimation(LVMotion.standard, value: vm.count)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LVSpacing.xs) {
            Text("What I learned this week")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(palette.textPrimary)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: LVSpacing.xs) {
                Image(systemName: "lock.fill")
                    .imageScale(.small)
                Text(subtitle)
            }
            .lvFont(.footnote)
            .foregroundStyle(palette.textSecondary)
            .accessibilityElement(children: .combine)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        if let range = vm.rangeText { return "\(range) · Private to you" }
        return "Private to you"
    }

    private var emptyState: some View {
        VStack(spacing: LVSpacing.md) {
            Image(systemName: "checkmark.seal")
                .font(.system(.largeTitle, weight: .light))
                .foregroundStyle(palette.accent)
                .accessibilityHidden(true)
            Text("Nothing new to confirm — I'll check again next week.")
                .lvFont(.callout)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LVSpacing.xl)
    }
}

// MARK: - Rows

/// One proposed SOUL.md change.
private struct LearnedSoulChangeRow: View {
    let change: LearnedSoulChangeDTO
    let isPending: Bool
    let errorMessage: String?
    let onKeep: () -> Void
    let onForget: () -> Void

    @Environment(\.lvPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(change.title)
                    .lvFont(.bodyEmphasis)
                    .foregroundStyle(palette.textPrimary)
                Text(change.summary)
                    .lvFont(.callout)
                    .foregroundStyle(palette.textSecondary)
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: LVSpacing.sm) {
                LearnedAnswerButton(title: "Keep", prominent: true, label: "Keep this about you", action: onKeep)
                LearnedAnswerButton(title: "Forget", label: "Forget this", action: onForget)
                Spacer(minLength: 0)
            }
            .disabled(isPending)

            if let errorMessage {
                LearnedErrorLabel(message: errorMessage)
            }
        }
        .padding(.vertical, LVSpacing.xs)
    }
}

/// One new preference or decision memory.
private struct LearnedMemoryRow: View {
    let memory: LearnedMemoryDTO
    let isPending: Bool
    let errorMessage: String?
    let onKeep: () -> Void
    let onEdit: () -> Void
    let onForget: () -> Void

    @Environment(\.lvPalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: LVSpacing.sm) {
            VStack(alignment: .leading, spacing: LVSpacing.xs) {
                Text(memory.snippet)
                    .lvFont(.callout)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(4)
                HStack(spacing: LVSpacing.xs) {
                    kindChip
                    Text(memory.createdAt.formatted(.dateTime.month(.abbreviated).day()))
                        .lvFont(.caption)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)

            HStack(spacing: LVSpacing.sm) {
                LearnedAnswerButton(title: "Keep", prominent: true, label: "Keep this memory", action: onKeep)
                LearnedAnswerButton(title: "Edit", label: "Edit this memory", action: onEdit)
                LearnedAnswerButton(title: "Forget", label: "Forget this memory", action: onForget)
                Spacer(minLength: 0)
            }
            .disabled(isPending)

            if let errorMessage {
                LearnedErrorLabel(message: errorMessage)
            }
        }
        .padding(.vertical, LVSpacing.xs)
    }

    /// The shared chip for a kind this build knows; the raw word, in the
    /// same capsule, for one it does not.
    @ViewBuilder private var kindChip: some View {
        if let kind = MemoryKindDTO(rawValue: memory.kind) {
            MemoryKindChip(kind: kind)
        } else if !memory.kind.isEmpty {
            Text(memory.kind.capitalized)
                .lvFont(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(.quaternary, in: Capsule())
        }
    }
}

private struct LearnedAnswerButton: View {
    let title: String
    var prominent = false
    let label: String
    let action: () -> Void

    var body: some View {
        if prominent {
            Button(title, action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel(label)
        } else {
            Button(title, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel(label)
        }
    }
}

private struct LearnedErrorLabel: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .lvFont(.footnote)
            .foregroundStyle(.orange)
    }
}

/// `.sheet(item:)` fodder for the memory being edited.
private struct LearnedMemoryLink: Identifiable, Equatable {
    let id: UUID
}
