// LuminaVaultClient/LuminaVaultClient/Features/Vault/VaultTrashView.swift
// Backlog E3.4: the Trash screen, reached from the Vault file list. Swipe right
// to restore, left to delete for good (with a confirmation). Files stay 30 days.
import SwiftUI

struct VaultTrashView: View {
    @Environment(\.lvPalette) private var palette

    @State private var vm: VaultTrashViewModel
    @State private var itemToDelete: VaultTrashItem?

    init(vaultClient: VaultClientProtocol) {
        _vm = State(wrappedValue: VaultTrashViewModel(vaultClient: vaultClient))
    }

    var body: some View {
        content
            .navigationTitle("Trash")
            .navigationBarTitleDisplayMode(.inline)
            .lvBackground()
            .task { await vm.load() }
            .refreshable { await vm.load() }
            .alert("Delete for good?",
                   isPresented: Binding(
                       get: { itemToDelete != nil },
                       set: { if !$0 { itemToDelete = nil } }
                   ),
                   presenting: itemToDelete) { item in
                Button("Delete", role: .destructive) {
                    Task { await vm.deleteForever(item) }
                    itemToDelete = nil
                }
                Button("Cancel", role: .cancel) { itemToDelete = nil }
            } message: { item in
                Text("\(item.path) can't be restored after this.")
            }
            .alert("Trash",
                   isPresented: Binding(
                       get: { vm.error != nil },
                       set: { if !$0 { vm.error = nil } }
                   )) {
                Button("OK", role: .cancel) { vm.error = nil }
            } message: {
                Text(vm.error ?? "")
            }
            .sensoryFeedback(.success, trigger: vm.notice)
    }

    @ViewBuilder
    private var content: some View {
        if vm.isLoading && !vm.hasLoaded {
            ProgressView().controlSize(.large)
        } else if vm.items.isEmpty {
            LVEmptyState(
                mascot: .idle,
                headline: "Trash is empty.",
                supporting: "Files you delete stay here for \(VaultTrashItem.retentionDays) days.",
                backgroundImage: "LogoMark"
            )
        } else {
            list
        }
    }

    private var list: some View {
        List {
            if let notice = vm.notice {
                Text(notice)
                    .font(.footnote)
                    .foregroundStyle(palette.textSecondary)
                    .listRowBackground(Color.clear)
            }
            Section {
                ForEach(vm.items) { item in
                    row(item)
                        .swipeActions(edge: .leading) {
                            Button {
                                Task { await vm.restore(item) }
                            } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                                .tint(palette.glowPrimary)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                itemToDelete = item
                            } label: { Label("Delete forever", systemImage: "trash") }
                        }
                        .contextMenu {
                            Button {
                                Task { await vm.restore(item) }
                            } label: { Label("Restore", systemImage: "arrow.uturn.backward") }
                            Button(role: .destructive) {
                                itemToDelete = item
                            } label: { Label("Delete forever", systemImage: "trash") }
                        }
                        .disabled(vm.busy.contains(item.id))
                        .listRowBackground(Color.clear)
                }
            } footer: {
                Text("Swipe right to restore. Files are deleted for good after \(VaultTrashItem.retentionDays) days.")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func row(_ item: VaultTrashItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title ?? item.path)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(detail(item))
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Swipe right to restore, left to delete for good.")
    }

    private func detail(_ item: VaultTrashItem) -> String {
        var parts: [String] = []
        if item.title != nil { parts.append(item.path) }
        parts.append(ByteCountFormatter.string(fromByteCount: item.sizeBytes, countStyle: .file))
        let days = item.daysLeft()
        parts.append(days <= 1 ? "Deleted for good within a day" : "\(days) days left")
        return parts.joined(separator: " · ")
    }
}
